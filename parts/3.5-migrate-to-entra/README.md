# Part 3.5: Migrate ServiceNow to Entra ID and Decommission AD FS

[← 3.4 SAML on AD FS](../3.4-saml-adfs/README.md) · **3.5** · 3.6 OIDC and OAuth (next)

> **In this part:** I moved ServiceNow's sign-in from AD FS to Entra ID without changing a single user's identity, proved it with allowed and refused sign-ins while the AD FS server was switched off, then removed AD FS completely: its trust, its signing-key container in AD, its certificate (revoked and published), its accounts and records, and the server itself.
>
> **Scripts:** [`3.5-add-app-ou-to-sync-scope.ps1`](../../scripts/3.5-add-app-ou-to-sync-scope.ps1) · [`3.5-decommission-adfs.ps1`](../../scripts/3.5-decommission-adfs.ps1)

**Why migrate:** on AD FS, Monica signed in to ServiceNow with **only a password**, because AD FS doesn't apply Entra's Conditional Access. On Entra ID, the Project 2 policies cover the app automatically: MFA, the leaver block and the location rule. Retiring AD FS also removes a Tier 0 server whose signing key is the target of Golden SAML attacks.

| # | Section | The lesson |
|---|---|---|
| 1 | [Getting the access group to Entra](#1-getting-the-access-group-to-entra) | A new group outside the sync scope silently never arrives |
| 2 | [ServiceNow in Entra ID](#2-servicenow-in-entra-id) | Same identifier, fewer claims |
| 3 | [Conditional Access covers it](#3-conditional-access-covers-it) | No new policy needed |
| 4 | [Connecting ServiceNow to Entra](#4-connecting-servicenow-to-entra) | The built-in test fails for every identity provider |
| 5 | [The cutover](#5-the-cutover) | |
| 6 | [Testing with AD FS switched off](#6-testing-with-ad-fs-switched-off) | Authenticated is not authorized |
| 7 | [Decommissioning AD FS](#7-decommissioning-ad-fs) | Deleting the server isn't the end |
| 8 | [Findings](#8-findings) | |

---

## 1. Getting the access group to Entra

`GG-App-ServiceNow` (from 3.4) never appeared in Entra ID. The other synced groups live in `OU=Role`, but this one was directly in `OU=Groups`:

![Group locations](images/3.5-01-group-ou.png)

Entra Connect's scope confirmed it: only **People**, **Groups\Role** and **Disabled** are synced. Nothing errored. The group just never arrived.

![Sync scope: three OUs](images/3.5-02-sync-scope.png)

**The fix:** a dedicated `OU=App` for application access groups. I didn't move the group into `OU=Role`, because the Project 1 JML engine manages role group memberships from HR data and could strip memberships it doesn't expect.

Adding the OU to the sync scope took three tries:

- **The Entra Connect wizard** needs a cloud admin sign-in, and mine failed (wrong password: I'd been signing in with a passkey for weeks). Even with the password, completing phishing-resistant MFA from inside a server is impractical.
- **Synchronization Service Manager** opened read-only, because the abandoned wizard was still open and locked the configuration.
- **PowerShell** worked: I added the OU to the connector's inclusion list with the ADSync module, then ran a full sync.

![Four OUs in scope](images/3.5-03-app-ou-in-scope.png)

![GG-App-ServiceNow in Entra, Monica a member](images/3.5-04-group-synced.png)

Monica's **employee ID is 100170 in Entra too**, the same value AD FS sent. So ServiceNow will see exactly the same identity:

![Employee ID 100170 in Entra](images/3.5-05-monica-employee-id.png)

## 2. ServiceNow in Entra ID

I added the **ServiceNow gallery app**, which also brings the provisioning connector used in 3.7.

| Setting | Value | Why |
|---|---|---|
| Identifier | `https://<instance>.service-now.com` | **The same identifier AD FS used** |
| Reply URLs | `…/navpage.do`, `…/consumer.do` | Where tokens are posted, matching ServiceNow's metadata |
| Sign on URL | `…/login_with_sso.do?glide_sso_id=<Entra IdP>` | The My Apps tile goes straight into ServiceNow |
| Name ID | `user.employeeid`, format *Unspecified* | **The same identity AD FS sent** |

![Basic SAML configuration](images/3.5-06-entra-saml-config.png)

**Fewer claims.** The gallery app also sends email (`user.mail`, empty here), **name (the UPN)** and given name. ServiceNow needs only the Name ID, so I removed them and kept surname:

![Claims after cleanup](images/3.5-07-claims.png)

**Assignment required = Yes**, with `GG-App-ServiceNow` assigned. That's the Entra version of AD FS's group access policy:

![Group assignment](images/3.5-08-app-assignment.png)

## 3. Conditional Access covers it

What If for Monica and ServiceNow: **CA001 (MFA) applies**, with no new policy. The all-resources policies from Project 2 cover every app added later. I used a US test IP so the location policy stayed out of the result.

![What If: CA001 applies](images/3.5-09-whatif-servicenow.png)

## 4. Connecting ServiceNow to Entra

In 3.4, I turned ServiceNow's Test Connection requirement off because the test never completed against AD FS, and I suspected AD FS being unreachable from the internet. **I turned the requirement back on first** so Entra would have to pass the real test:

![Test requirement back on](images/3.5-10-test-required-again.png)

I imported Entra's metadata from its URL into a new identity provider, with User Field `employee_number`. The import set the Name ID format to `urn:oasis:names:tc:SAML:2.0:nameid-format:unspecified`, which isn't a real format, because *unspecified* is defined in SAML 1.1. I changed it to `…SAML:1.1:nameid-format:unspecified`. Choosing *transient* would have sent a random one-time value instead of the employee ID.

![Entra ID identity provider in ServiceNow](images/3.5-11-servicenow-entra-idp.png)

**Test Connection behaved exactly as it did with AD FS:** no results page, and activation still blocked. Entra's side was fine. Monica's sign-ins to ServiceNow show **Interrupted** (the MFA prompt) then **Success**:

![Entra sign-in log](images/3.5-12-entra-signin-log.png)

![MFA satisfied](images/3.5-13-mfa-details.png)

![CA001 applied](images/3.5-14-ca001-applied.png)

So my 3.4 theory was wrong: the test fails the same way for an internet-facing identity provider. Others report the same behavior in ServiceNow's community, with no fix posted. I used the property again for activation and relied on real sign-ins as the proof, as in 3.4.

## 5. The cutover

ServiceNow's restricted recovery session can't change system properties, so the cutover happened in **one short full-admin session**: multi-provider SSO and account recovery off, then:

1. Test requirement off
2. **Entra ID activated and made the default**
3. **AD FS identity provider deactivated:** ServiceNow stops accepting AD FS tokens
4. Test requirement back on

Then account recovery and multi-provider SSO back on.

![Entra ID active and default](images/3.5-15-entra-idp-active-default.png)

![AD FS identity provider inactive](images/3.5-16-adfs-idp-inactive.png)

## 6. Testing with AD FS switched off

**The AD FS server was powered off for every test,** so any sign-in that worked went entirely through Entra.

**Allowed:** Monica, with an MFA prompt (CA001), landed in ServiceNow as herself:

![Monica via Entra](images/3.5-17-monica-via-entra.png)

**Refused:** Chris, who isn't in `GG-App-ServiceNow`, was stopped by Entra with **AADSTS50105**. ServiceNow never got a token:

![AADSTS50105](images/3.5-18-chris-refused-entra.png)

![Sign-in log: 50105](images/3.5-19-chris-50105-log.png)

**Chris authenticated successfully and was still refused.** His password was correct (checked by Password Hash Sync, with no AD FS involved) and he completed MFA, but he isn't assigned to the app. That's the difference between authentication and authorization, in one log entry:

![Password and MFA succeeded](images/3.5-20-chris-auth-details.png)

## 7. Decommissioning AD FS

**Nothing used it after the cutover.** The last token AD FS issued was Monica's 3.4 test, before the migration. Then I removed the ServiceNow trust, stopped AD FS and disabled the service:

![Last token before the cutover](images/3.5-21-adfs-last-use.png)

![Trust removed, service stopped and disabled](images/3.5-22-adfs-stopped.png)

**Its key container in AD.** AD FS protects its token-signing key with a key stored in Active Directory, under Program Data. **Deleting the server doesn't remove it.** Anyone holding a copy of AD FS's database could use it to unlock the signing key, which is exactly what Golden SAML needs. I deleted the container:

![AD FS key container](images/3.5-23-adfs-key-container.png)

With the **AD Recycle Bin** on, deleted objects keep their attributes and can be restored for 180 days, key included. I checked rather than assumed: the Recycle Bin is off here, the objects went straight to the recycled state, and **the key attribute is gone**:

![Objects recycled](images/3.5-24-adfs-objects-recycled.png)

![Recycle Bin off, KeyPresent False](images/3.5-25-adfs-key-gone.png)

**Its certificate.** AD FS's TLS certificate was valid until November 2027. I revoked it (reason: Cessation of Operation), published a new CRL and uploaded it right away, and removed the web server template. The CA issues nothing again, the same as when it was built:

![The certificate issued to FRD-ADFS-01](images/3.5-26-cert-found.png)

![Revoked](images/3.5-27-cert-revoked.png)

**The internet copy of the CRL lists it within minutes,** so anything checking that certificate now refuses it:

![CRL from Blob Storage shows the revocation](images/3.5-28-crl-shows-revoked.png)

**Everything else:** the gMSA, the enrollment group, the `sts` DNS record and the computer account. The computer account first failed with *"only on a leaf object"*: Azure VMs register a **"Windows Virtual Machine"** object inside their own computer account, so it had to be removed recursively.

![The child object](images/3.5-29-computer-children.png)

![All four gone](images/3.5-30-ad-cleanup.png)

Finally, the VM (with its disk and network interface, which also frees 2 vCPUs of quota) and ServiceNow's AD FS identity provider record. **Entra ID is the only active identity provider:**

![VM deleted](images/3.5-31-vm-deleted.png)

![Entra ID the only active identity provider](images/3.5-32-adfs-idp-deleted.png)

## 8. Findings

| # | Finding | Impact | Fix |
|---|---|---|---|
| 1 | **A new group outside the synced OUs silently never reaches Entra** | App access can't be assigned in the cloud, and nothing alerts | `OU=App` for application groups, added to the sync scope (done) |
| 2 | **Changing Entra Connect's scope through the wizard needs a cloud admin sign-in on the sync server** | Phishing-resistant MFA is impractical from inside a VM | Changed it with the ADSync PowerShell module instead (done). Production: a FIDO2 security key or a privileged access workstation (open) |
| 3 | **Synchronization Service Manager is read-only while the Entra Connect wizard is open** | Configuration looks locked for no visible reason | Close the wizard first (done) |
| 4 | **AD FS never applied Conditional Access** | ServiceNow sign-ins were password-only | Migrated. CA001 now requires MFA (done) |
| 5 | **The gallery app sends claims the app doesn't need, including the UPN** | Unnecessary identity data in every token | Removed all but the Name ID and surname (done) |
| 6 | **Without "assignment required", any user in the tenant could sign in to the app** | App access wouldn't follow the access group | Assignment required, group assigned. Refusal verified (done) |
| 7 | **The import set a Name ID format that doesn't exist** (SAML 2.0 *unspecified*) | Requests could fail or return the wrong identifier | Set to SAML 1.1 *unspecified* (done) |
| 8 | **ServiceNow's Test Connection never completes, for AD FS or Entra** | Activation is blocked. Others report the same, with no fix posted | Activated with the documented property, verified with real sign-ins, requirement restored (done) |
| 9 | **The cutover needed SSO protections briefly turned off** | A short window with reduced protection | Kept to one short session (done). Production: a planned change window (open) |
| 10 | **Deleting the AD FS server leaves its key container in AD** | A database backup plus that key enables Golden SAML | Deleted. Recycle Bin state checked and key confirmed gone (done). On the decommission checklist |
| 11 | **AD FS's TLS certificate stays valid for a year unless revoked** | A copied key could impersonate the federation service name | Revoked and published to the internet CRL (done) |
| 12 | **Azure VM computer accounts contain a child object** | `Remove-ADComputer` fails | Remove recursively (done) |

## Test results

| Test | Result |
|---|---|
| ServiceNow sees the same identity after the migration | ✅ employeeID 100170 from both identity providers |
| A group member signs in through Entra, with MFA | ✅ Monica, CA001 applied |
| A non-member is refused by Entra | ✅ Chris, AADSTS50105, even after correct password and MFA |
| Nothing depends on AD FS | ✅ All tests ran with AD FS powered off. Last AD FS token pre-dates the cutover |
| AD FS key removed from AD | ✅ KeyPresent False |
| AD FS certificate revoked and visible from the internet | ✅ |
| ServiceNow's Test Connection | ❌ Never completed. Real sign-ins used as the proof |

## What I had at the end of 3.5

- [x] ServiceNow signing in through Entra ID, protected by Conditional Access
- [x] The same user identity before and after the migration
- [x] AD FS fully decommissioned: trust, key, certificate, accounts, DNS and server
- [x] One identity provider for ServiceNow, and 2 vCPUs of quota back

---

**Next:** 3.6 OIDC and OAuth · [← Back to the project overview](../../README.md)
