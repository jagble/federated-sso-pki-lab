<#
  Part 3.6: test an OIDC / OAuth public client with the authorization code flow and PKCE.

  Runs in Windows PowerShell on the workstation that has the browser (FRD-WS-01).
  READ-ONLY: changes no settings anywhere. It creates sign-in events and tokens in Entra ID,
  keeps tokens in memory only, and never prints a full token.

  Run the sections in order, in ONE PowerShell window: later sections reuse the verifier,
  code and tokens from earlier ones. Section 6 needs "Revoke sessions" done in the portal first.
#>

# ---------- 0. Your values (no secrets: a public client has none) ----------
$tenant = '<Directory (tenant) ID>'
$client = '<PDS Inventory Portal - Application (client) ID>'
$api    = 'api://<PDS Inventory API - Application ID>/Inventory.Read'
$scope  = "openid profile email offline_access $api"
$tokenUrl = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token"
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'

function ConvertTo-Base64Url([byte[]]$b) {
    [Convert]::ToBase64String($b).TrimEnd('=').Replace('+','-').Replace('/','_')
}
function New-RandomBase64Url { $b = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); ConvertTo-Base64Url $b }
function Get-JwtClaims($jwt) {            # decodes the claims; decoding is NOT verifying
    $p = $jwt.Split('.')[1].Replace('-','+').Replace('_','/')
    switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
}
function Get-Time($s) { [DateTimeOffset]::FromUnixTimeSeconds($s).LocalDateTime }
function Invoke-Token($body) {            # returns tokens, or prints Entra's error and returns $null
    try   { Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded' }
    catch { ($_.ErrorDetails.Message | ConvertFrom-Json) | Format-List error, error_description; $null }
}

# ---------- 1. PKCE pair, sign-in, and the code ----------
# Close every Edge window first: InPrivate windows share one session while any is open.
$verifier  = New-RandomBase64Url                                     # never leaves this window
$sha       = [System.Security.Cryptography.SHA256]::Create()
$challenge = ConvertTo-Base64Url ($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier)))
$state = [guid]::NewGuid().ToString('N')                             # anti-forgery for the redirect
$nonce = [guid]::NewGuid().ToString('N')                             # anti-replay for the ID token
$authUrl = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/authorize?" + (@(
    "client_id=$client", "response_type=code"
    "redirect_uri=$([uri]::EscapeDataString('http://localhost'))", "response_mode=query"
    "scope=$([uri]::EscapeDataString($scope))", "state=$state", "nonce=$nonce"
    "code_challenge=$challenge", "code_challenge_method=S256"
) -join '&')
Start-Process msedge -ArgumentList '-inprivate', $authUrl
$redirect = Read-Host "Sign in, then paste the full http://localhost/?code=... URL"

$params = @{}
foreach ($p in ([uri]$redirect).Query.TrimStart('?').Split('&')) {
    $k, $v = $p.Split('=', 2); $params[$k] = [uri]::UnescapeDataString($v) }
$code = $params['code']
"State matches: $($params['state'] -eq $state)"

# ---------- 2. Negative test, then the real exchange (seconds apart, before the code expires) ----------
$exchange = @{ client_id = $client; grant_type = 'authorization_code'; code = $code
               redirect_uri = 'http://localhost'; scope = $scope }

"`n=== WRONG VERIFIER (expect AADSTS501481) ==="
$null = Invoke-Token ($exchange + @{ code_verifier = (New-RandomBase64Url) })

"`n=== CORRECT VERIFIER (expect tokens) ==="
$tok = Invoke-Token ($exchange + @{ code_verifier = $verifier })

"`n=== SAME CODE AGAIN (expect AADSTS54005) ==="
$null = Invoke-Token ($exchange + @{ code_verifier = $verifier })

# ---------- 3. What came back ----------
[pscustomobject]@{ scope = $tok.scope; expires_in_sec = $tok.expires_in
    id_token = [bool]$tok.id_token; access_token = [bool]$tok.access_token; refresh_token = [bool]$tok.refresh_token
} | Format-List

$id = Get-JwtClaims $tok.id_token          # for the portal: who signed in
"=== ID TOKEN ==="
[pscustomobject]@{ aud = $id.aud; iss = $id.iss; name = $id.name; preferred_username = $id.preferred_username
    email = $id.email; nonce_matches = ($id.nonce -eq $nonce); ver = $id.ver; expires = Get-Time $id.exp
} | Format-List

$at = Get-JwtClaims $tok.access_token      # for the API: what the app may do
"=== ACCESS TOKEN ==="
[pscustomobject]@{ aud = $at.aud; iss = $at.iss; scp = $at.scp
    client = $(if ($at.azp) { $at.azp } else { $at.appid })
    user   = $(if ($at.upn) { $at.upn } else { $at.preferred_username })
    amr = ($at.amr -join ', '); ver = $at.ver; expires = Get-Time $at.exp
} | Format-List

# ---------- 4. Refresh: new access token with no browser ----------
$refresh = @{ client_id = $client; grant_type = 'refresh_token'; scope = $scope }
$tok2 = Invoke-Token ($refresh + @{ refresh_token = $tok.refresh_token })
$at2  = Get-JwtClaims $tok2.access_token
"=== REFRESH ==="
[pscustomobject]@{ amr = ($at2.amr -join ', '); new_expires = Get-Time $at2.exp
    refresh_token_rotated = ($tok2.refresh_token -ne $tok.refresh_token) } | Format-List

# ---------- 5. Does the OLD (rotated) refresh token still work? ----------
"=== OLD REFRESH TOKEN ==="
if (Invoke-Token ($refresh + @{ refresh_token = $tok.refresh_token })) { 'Old refresh token still ACCEPTED' }

# ---------- 6. After "Revoke sessions" on the user in the Entra portal (wait ~1 minute) ----------
"=== REFRESH AFTER REVOKE (expect AADSTS50173) ==="
if (Invoke-Token ($refresh + @{ refresh_token = $tok2.refresh_token })) { 'Refresh ACCEPTED after revoke (bad)' }
"Access token already issued is still valid until $(Get-Time $at2.exp) (now $(Get-Date))"

# ---------- 7. Unassigned user ----------
# Close every Edge window, open $authUrl again and sign in as a user who is NOT assigned:
#   Start-Process msedge -ArgumentList '-inprivate', $authUrl
# Expect AADSTS50105 in the browser. No code is issued, so there is nothing to exchange.
