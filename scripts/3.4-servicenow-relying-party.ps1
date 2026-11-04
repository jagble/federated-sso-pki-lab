<#
  Part 3.4: ServiceNow sign-in through AD FS (SAML 2.0).

  PART A - on the DC (CHANGES AD): the group that controls who may sign in to ServiceNow.
  PART B - on FRD-ADFS-01 (CHANGES AD FS): the ServiceNow relying party trust.

  Identifier choice: users are identified by employeeID, not UPN or email.
  - AD UPNs use the non-routable suffix ad.potomacdefense.internal, so Entra ID gives every user a
    different (onmicrosoft.com) UPN. An app keyed on UPN would see new users after the move to Entra.
  - The JML engine doesn't populate 'mail'.
  - employeeID is identical in AD and Entra and never changes.
#>

# ---------- PART A: on the DC ----------
New-ADGroup -Name 'GG-App-ServiceNow' -GroupScope Global -GroupCategory Security `
  -Path 'OU=Groups,OU=PDS,DC=ad,DC=potomacdefense,DC=internal' `
  -Description 'Users allowed to sign in to ServiceNow'
Add-ADGroupMember -Identity 'GG-App-ServiceNow' -Members 'monica.hayes'

# ---------- PART B: on FRD-ADFS-01 ----------
# ServiceNow's SP metadata (Multi-Provider SSO > Identity Provider > Generate Metadata), saved to a file
$metadata = 'C:\ADFS\servicenow-sp-metadata.xml'

# Claim rules, in order:
#  1. After sign-in, look the user up in AD and issue employeeID, given name and surname
#  2. Copy employeeID into the SAML Name ID, format 'unspecified' (matches the ServiceNow IdP record)
$rules = @'
@RuleName = "Send employeeID and name from AD"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
 => issue(store = "Active Directory",
    types = ("https://schemas.potomacdefense.internal/claims/employeeid",
             "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
             "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname"),
    query = ";employeeID,givenName,sn;{0}", param = c.Value);

@RuleName = "employeeID as Name ID"
c:[Type == "https://schemas.potomacdefense.internal/claims/employeeid"]
 => issue(Type = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier",
    Issuer = c.Issuer, OriginalIssuer = c.OriginalIssuer, Value = c.Value, ValueType = c.ValueType,
    Properties["http://schemas.xmlsoap.org/ws/2005/05/identity/claimproperties/format"] = "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified");
'@

# Only members of GG-App-ServiceNow get a token. Everyone else is refused by AD FS (event 1201)
Add-AdfsRelyingPartyTrust -Name 'ServiceNow' `
  -MetadataFile $metadata `
  -AccessControlPolicyName 'Permit specific group' `
  -AccessControlPolicyParameters @{ GroupParameter = @('PDS\GG-App-ServiceNow') } `
  -IssuanceTransformRules $rules

# Read-only checks
$rp = Get-AdfsRelyingPartyTrust -Name 'ServiceNow'
$rp | Format-List Name, Enabled, Identifier, AccessControlPolicyName
$rp.SamlEndpoints | Format-Table Protocol, Binding, Location -AutoSize

# Evidence: allowed (1202 + 1200) and refused (1202 + 1201) sign-ins
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; ProviderName = 'AD FS Auditing'; Id = 1200, 1201, 1202, 1203 } -MaxEvents 12 |
  Format-Table TimeCreated, Id, @{n='Meaning';e={ switch ($_.Id) { 1200 {'Token issued'} 1201 {'Token REFUSED'} 1202 {'Credentials validated'} 1203 {'Credentials FAILED'} } }} -AutoSize
