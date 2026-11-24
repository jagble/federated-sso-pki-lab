# Part 3.8: Certificate-Based Authentication, and the Project Review

[← 3.7 Provisioning](../3.7-provisioning/README.md) · **3.8** · [Project overview](../../README.md)

> **In this part:** Monica signs in to Entra ID with a certificate from my own CA, with no password and no phone prompt: the lab version of a CAC or PIV card. A Conditional Access policy then makes a certificate the **only** way in for the pilot group. Getting there took three attempts at matching the certificate to her account, because of the same `.internal` username problem from 3.4. Then I revoked her certificate, published the revocation, and **Entra kept accepting it**. The part ends with a review of the whole project.
>
> **Script:** [`3.8-request-user-certificate.ps1`](../../scripts/3.8-request-user-certificate.ps1)

**Why certificates count as phishing-resistant:** the private key never leaves the user's device and is never typed or sent anywhere. A fake sign-in page can steal a password or trick someone into approving a push, but it can't make the device sign for a different website. That's why federal zero trust guidance points to PIV and FIDO2.

| # | Section | The lesson |
|---|---|---|
| 1 | [A template for sign-in certificates](#1-a-template-for-sign-in-certificates) | The default User template would have failed, and over-granted |
| 2 | [Monica's certificate](#2-monicas-certificate) | |
| 3 | [Entra trusts the CA](#3-entra-trusts-the-ca) | Adding a CA lets it sign in *any* user, unless it's scoped |
| 4 | [Matching the certificate to Monica](#4-matching-the-certificate-to-monica) | Three attempts. The `.internal` UPN again |
| 5 | [Certificates only](#5-certificates-only) | The password path offered nothing but the certificate |
| 6 | [Revocation](#6-revocation) | Entra accepted a revoked certificate 40 minutes later |
| 7 | [Findings](#7-findings) | |
| 8 | [Project 3 review](#8-project-3-review) | |

---

## 1. A template for sign-in certificates

An enrollment group first, with one member:

![GG-PKI-UserAuth-Enroll](images/3.8-01-enroll-group.png)

Then a new template, **PDS User Authentication**, duplicated from **User** and tightened:

| Setting | Value | Why |
|---|---|---|
| Subject | **Built from AD**. **UPN only** in the alternate name, **no email** | Monica's AD `mail` is empty (3.4 finding 2), so the User template's email fields would make enrollment fail. Building from AD also means **nobody can ask for someone else's name** |
| Application policies | **Client Authentication only** | User includes Secure Email and EFS. This certificate is for signing in, nothing else |
| Private key | **Not exportable** | It can't be copied off the device |
| Issuance | **CA manager approval** | No sign-in certificate without a person approving it |
| Enrollment | **GG-PKI-UserAuth-Enroll** only (Read + Enroll). Domain Users keep Read, without Enroll | |

![Subject name](images/3.8-02-template-subject-name.png)

![Client Authentication only](images/3.8-03-template-extensions.png)

![Enrollment group: Read and Enroll](images/3.8-04-template-security.png)

![Domain Users: Read only](images/3.8-05-domain-users-no-enroll.png)

**The template's creator was given its own permissions automatically**, the same thing 3.3 found (finding 4 there). My Tier 0 account already has control through Domain Admins, so I removed the extra entry:

![Creator entry removed](images/3.8-06-creator-removed.png)

The CA now issues exactly two templates: one for servers, one for user sign-in.

![Two templates](images/3.8-07-templates-issued.png)

## 2. Monica's certificate

Monica signed in to the Tier 2 workstation (allowed through its local Remote Desktop Users group) and requested the certificate as herself. It stopped at **Pending**:

![Pending](images/3.8-08-request-pending.png)

![Issued after approval](images/3.8-09-request-issued.png)

Collected and checked:

![Monica's certificate](images/3.8-10-monica-cert.png)

- **Client Authentication** only, with her private key on the workstation
- The UPN inside is **`monica.hayes@ad.potomacdefense.internal`**, her AD name, **not** her cloud username. That's the problem section 4 had to solve

`certutil -verify -urlfetch` built the chain and **downloaded the CA certificate and CRL from Blob Storage**, the same path Entra uses:

![Chain and CRL from Blob Storage](images/3.8-11-cert-verify.png)

![Revocation check passed](images/3.8-12-revocation-passed.png)

The output also shows something that matters later: **the CRL then in Blob Storage was issued Nov 20 and valid until Nov 28.** The daily task uploads the current CRL, but the CA only issues a new one about once a week.

## 3. Entra trusts the CA

I uploaded PDS-Root-CA to the **classic** certificate authority list first, with the Blob Storage CRL address:

![Classic trust store](images/3.8-13-entra-trusts-ca.png)

Entra recommends its newer **PKI-based trust store**, so I moved the CA there, turned on **issuer hints** (the sign-in page offers only certificates from trusted CAs), and deleted the classic entry so there's one source of truth. The classic list needs **Global Administrator**, while the new store can be managed by the less-privileged **Privileged Authentication Administrator**.

![PKI-based trust store](images/3.8-14-pki-trust-store.png)

![CRL endpoint](images/3.8-15-crl-url.png)

Then CBA itself, **for a pilot group only**:

![Pilot group](images/3.8-16-cba-pilot-group.png)

![CBA enabled for GG-CBA-Pilot](images/3.8-17-cba-enabled.png)

| Setting | Value |
|---|---|
| CRL validation | **Required**: a certificate that can't be checked for revocation is refused |
| Authentication binding | Certificates from PDS-Root-CA count as **multi-factor** |
| **Certificate issuer scoping** | PDS-Root-CA certificates are accepted **only for members of GG-CBA-Pilot** |

![Issuer rule: multi-factor](images/3.8-18-issuer-rule-mfa.png)

![Issuer scoping rule](images/3.8-19-issuer-scoping-rule.png)

**Why the scoping rule matters:** Microsoft warns that adding a CA lets certificates it issues authenticate **any** user in the tenant, synced or cloud-only. A mistake on the CA, or a compromise of it, would reach every account. The scoping rule limits PDS-Root-CA to the pilot group.

## 4. Matching the certificate to Monica

Entra has to decide **which account** a certificate belongs to. Her certificate says `monica.hayes@ad.potomacdefense.internal`, and her cloud username is `@PotomacDefenseSystems.onmicrosoft.com`.

**Attempt 1: PrincipalName → `onPremisesUserPrincipalName`**, her AD UPN as stored in Entra:

![Bindings, attempt 1](images/3.8-20-cba-bindings.png)

Entra offered only her PDS certificate (issuer hints working):

![Certificate picker](images/3.8-21-certificate-picker.png)

…and refused it with **AADSTS1001009**: *no value in the certificate is able to validate the user claim.*

![AADSTS1001009](images/3.8-22-aadsts1001009.png)

Her on-premises UPN in Entra was **exactly** the value in the certificate:

![On-premises UPN](images/3.8-23-onprem-upn.png)

The sign-in log showed every other check passing: the certificate was read, the **PKI-based store** was used (legacy store: 0), and CRL enforcement was on. Only the matching failed. It still failed an hour later, so it wasn't a delay in the policy taking effect.

![Failed sign-in](images/3.8-24-failed-cba-basic.png)

![Certificate details in the failed sign-in](images/3.8-25-failed-cba-additional.png)

**Attempt 2: was the scoping rule blocking her?** I removed it, waited and retried: same error. I put it back.

**Attempt 3: `certificateUserIds`, populated from AD.** This attribute is what Entra's certificate matching is built around, and it accepts non-routable names. For a synced user it can **only** be written by Entra Connect, so I added an outbound sync rule:

| Rule | Value |
|---|---|
| Name | `Custom Out to Entra ID - certificateUserIds (PN)` |
| Direction / object | Outbound, person → user, Join, precedence 90 |
| Transformation | Expression → `certificateUserIds` = `"X509:<PN>"&[userPrincipalName]` |

![Sync rule](images/3.8-26-sync-rule.png)

In Entra Connect, `userPrincipalName` is still the AD value, so after a full sync:

![Full sync](images/3.8-27-full-sync.png)

![Certificate user IDs](images/3.8-28-certificate-user-ids.png)

Then the binding **PrincipalName → certificateUserIds**:

![Binding to certificateUserIds](images/3.8-29-binding-certuserids.png)

**She signed in with the certificate alone:**

![Signed in with the certificate](images/3.8-30-signed-in-with-cert.png)

The app opened right after reused that sign-in: *"MFA requirement satisfied by claim in the token."*

![MFA satisfied by the certificate sign-in](images/3.8-31-signin-followup.png)

| Attempt | Binding | Result |
|---|---|---|
| 1 | PrincipalName → `onPremisesUserPrincipalName` | ❌ AADSTS1001009, with identical values, for over an hour |
| 2 | Same, issuer scoping removed | ❌ Same error, so the rule was restored |
| 3 | PrincipalName → **`certificateUserIds`**, written by an Entra Connect rule | ✅ Signed in |

I don't know why attempt 1 failed. I followed the documented setting and the values matched. Attempt 3 is the route Microsoft documents for non-routable names, and it worked.

## 5. Certificates only

**CA009** requires the **Phishing-resistant MFA** authentication strength for the pilot group, on all resources, with break-glass excluded.

![CA009](images/3.8-32-ca009-policy.png)

**With her password**, Entra wouldn't finish signing her in, and the only option it offered was the certificate. No Authenticator, no phone:

![Password, then certificate only](images/3.8-33-password-then-cert-only.png)

**A browser quirk worth knowing:** I had cancelled the certificate picker to try the password first. Edge remembered that "no certificate" choice, so choosing the certificate afterwards failed with **"No certificate detected"** (500192) until the browser was fully closed:

![No certificate detected](images/3.8-34-no-certificate-detected.png)

![500192 in the sign-in log](images/3.8-35-signin-500192.png)

After closing the browser and choosing the certificate first:

![Certificate satisfies CA009](images/3.8-36-cert-satisfies-ca009.png)

![CA009: Success](images/3.8-37-ca009-results.png)

## 6. Revocation

I revoked Monica's certificate on the CA, reason **Key Compromise**, then published a new CRL and uploaded it:

![Revoked](images/3.8-38-cert-revoked.png)

The **public** CRL, downloaded from Blob Storage on the workstation, listed her serial number right away (redacted here), along with the AD FS certificate revoked in 3.5:

![Public CRL with the revocation](images/3.8-39-public-crl.png)

| Time (UTC) | Event |
|---|---|
| **17:08** | Certificate revoked, Key Compromise. New CRL published and uploaded (its ThisUpdate shows 16:58, because AD CS backdates by 10 minutes for clock skew) |
| 17:09 | A sign-in succeeds (I didn't check its authentication details) |
| **17:23** | **A real certificate sign-in: X.509 Certificate, succeeded**, 15 minutes after revocation |
| **~17:48** | **InPrivate window, no cookies: let in again**, about 40 minutes after revocation |

![Sign-ins after revocation](images/3.8-40-signin-list-after-revoke.png)

Checking the details mattered. One success was only **"Previously satisfied"**: the existing session, not the certificate:

![Previously satisfied](images/3.8-41-previously-satisfied.png)

But the 17:23 sign-in **presented the revoked certificate, and Entra accepted it**:

![X.509 accepted after revocation](images/3.8-42-x509-accepted-after-revoke.png)

![InPrivate: let in again](images/3.8-43-inprivate-let-in.png)

**What this means:** Entra checks revocation against **its own copy** of the CRL, and the copy it already had (valid until Nov 28) didn't list her certificate. A new CRL in Blob Storage doesn't help until Entra fetches it. **The CRL's lifetime, about a week here, is the worst-case window for a revoked certificate.**

**Where I stopped:** I didn't keep testing to find exactly when Entra picked up the new CRL, and I didn't test the identity-side cut-off (removing her from GG-CBA-Pilot and revoking her sessions). Both are in the findings as open items.

## 7. Findings

| # | Finding | Impact | Fix |
|---|---|---|---|
| 1 | **Entra accepted a revoked certificate**: a real certificate sign-in succeeded 15 minutes after revocation, and a fresh one about 40 minutes after | A stolen or compromised certificate keeps working until Entra refreshes its cached CRL | Pair every revocation with identity-side action: remove the user from the CBA group (the issuer scoping rule), revoke sessions, and if needed disable the account (open, untested) |
| 2 | **The CRL is reissued about once a week**, even though it's uploaded daily | The CRL's lifetime sets the worst-case revocation window | Shorter CRL validity and delta CRLs, published after every revocation (open) |
| 3 | **Revoking a certificate doesn't end the sessions it created** ("Previously satisfied") | The same lesson as 3.6: sessions outlive the credential | Revoke sessions as part of every certificate revocation (open) |
| 4 | **Binding PrincipalName → `onPremisesUserPrincipalName` never matched**, though the values were identical | Certificate sign-in failed with AADSTS1001009 | `certificateUserIds` written by an Entra Connect outbound rule (done) |
| 5 | **For synced users, certificate mapping is controlled from AD**: `certificateUserIds` can only come through Entra Connect, from the AD UPN here | Whoever can change a user's AD UPN, or the sync rules, controls which certificate opens which cloud account | Treat UPN changes and Entra Connect rules as Tier 0 changes. Move to **high-affinity** mapping (issuer and serial number, or SKI) so a certificate maps to one specific user (open) |
| 6 | **Adding a CA trusts it for every user in the tenant** | A CA mistake or compromise reaches every account | Issuer scoping rule: PDS-Root-CA only for GG-CBA-Pilot (done) |
| 7 | **The default User template includes email and extra purposes** | Enrollment would fail (empty `mail`), and certificates could do more than sign in | New template: UPN only, Client Authentication only, approval, one group (done) |
| 8 | **The template's creator got permissions on it automatically** | Unplanned rights on a sign-in template (3.3 finding 4 again) | Removed (done) |
| 9 | **The classic CA list needs Global Administrator** | The highest role for routine PKI changes | PKI-based trust store, which supports Privileged Authentication Administrator. Classic entry deleted (done) |
| 10 | **A cancelled certificate prompt is remembered by the browser** | "No certificate detected" until every browser window is closed | Help desk guidance for a CBA rollout (open) |
| 11 | **The private key is a software key on a VM** | Anyone with admin rights on the workstation could try to extract it | TPM-backed keys or smart cards in production. A real CAC keeps the key on the card (open) |
| 12 | **Monica was added to the workstation's Remote Desktop Users to enroll** | Extra access left behind after the test | Remove it during cleanup (open) |

## Test results

| Test | Result |
|---|---|
| Only the enrollment group can request the template, and approval is required | ✅ Pending, then issued |
| The certificate checks its revocation over the internet | ✅ AIA and CRL from Blob Storage |
| Certificate sign-in with a non-routable UPN | ✅ After moving the binding to `certificateUserIds` |
| A certificate sign-in counts as MFA | ✅ "MFA requirement satisfied by claim in the token" |
| Password alone can't satisfy CA009 | ✅ Only the certificate was offered |
| A revoked certificate is refused | ❌ Accepted 15 and about 40 minutes after revocation. Finding 1 |

## 8. Project 3 review

### What Project 3 built

| Part | Outcome |
|---|---|
| 3.1–3.2 | An enterprise CA that issues **nothing by default**, audited, publishing its CRL to the internet through a **managed identity** |
| 3.3–3.4 | AD FS in Tier 0 as a gMSA, ServiceNow on SAML, users identified by **employeeID** because of the `.internal` UPN suffix |
| 3.5 | ServiceNow **migrated to Entra ID** with no identity changes and MFA from Conditional Access, then AD FS **decommissioned**, signing-key container included |
| 3.6 | OIDC/OAuth with **PKCE and no client secret**, attacks refused, revocation measured |
| 3.7 | Provisioning **blocked** by a ServiceNow platform change, and the diagnosis documented |
| 3.8 | **Certificate-only sign-in** for a pilot group, and a revocation gap found |

### The thread through the whole project
**The non-routable `.internal` UPN suffix shaped almost every part.** It decided the SAML identifier in 3.4, made the cloud username differ from the AD one in 3.5, left `email` empty in 3.6's tokens, and broke certificate matching in 3.8. **The one change that would remove most of these workarounds is a routable UPN suffix on a verified domain.**

### Open risks, most important first
1. **Revocation lag** (3.8, findings 1–3): a compromised certificate, refresh token or access token keeps working for minutes to days. Response runbooks need identity-side steps, not just revocation at the source
2. **Orphaned ServiceNow accounts** (3.7, finding 6): leavers are blocked at SSO, but their accounts remain
3. **Low-affinity certificate mapping controlled from AD** (3.8, finding 5): move to high-affinity mapping
4. **User consent still Microsoft-managed** (3.6, finding 1)
5. **The Azure control plane is Tier 0 too.** Anyone who can run commands on the domain controller's VM through Azure (Run command runs as SYSTEM) can take over the domain without an AD password, so VM, resource group and subscription access deserve the same protection as Domain Admins

### What I'd do differently
- **Test the integration path first.** 3.7 lost most of a day before the transaction log showed the requests never reached ServiceNow
- **Check the exact sign-in in the log, not just the result.** In 3.8, one "successful revoked sign-in" was really an old session, and only the Authentication Details tab showed the difference
- **Do admin setup before enabling SSO.** ServiceNow's recovery session blocked routine work in 3.4 and again in 3.7

---

[← Back to the project overview](../../README.md)
