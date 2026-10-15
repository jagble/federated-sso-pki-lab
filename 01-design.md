# Design: Federation, SSO and PKI for PDS

> **Summary:** The planned AD FS deployment, application migration to Entra ID, SAML and OIDC integrations, SCIM provisioning and PKI for certificate-based authentication in the Potomac Defense Systems lab, written before implementation. Each section ends with how I'll test it.

> **About this lab:** Potomac Defense Systems is a fictional company. All people and data are made up.

**Status:** design written, build not started. Anything that changes during the build gets recorded in the build log.

---

## 1. Guiding rules

1. **Federation servers are Tier 0.** AD FS and the certificate authority can both mint credentials for any user, so they get domain-controller-level protection: Tier 0 OU, no internet browsing, admin only from Tier 0 accounts
2. **Migrate, then remove.** AD FS exists in this lab to be migrated away from. The project isn't done until it's decommissioned
3. **No app without Conditional Access.** Every app integrated with Entra ID is covered by the Project 2 policies
4. **Least privilege for apps too.** Apps get only the claims, scopes and permissions they need

## 2. Servers

| Server | Role | Tier | Why separate |
|---|---|---|---|
| `FRD-ADFS-01` | AD FS federation server | 0 | Holds the token-signing key. Not on the DC, so a compromise of one doesn't hand over both |
| `FRD-CA-01` | AD CS enterprise certificate authority | 0 | Can issue certificates that authenticate as any user |

Both are joined to `ad.potomacdefense.internal`, placed in `Tier0\Servers`, and reached only through the DC, like `FRD-SYNC-01` in Project 1. To control cost, both are stopped when not in use and deleted after the project.

**Production note:** a real PKI would use an **offline root CA** plus an online issuing CA. This lab uses a single enterprise CA and documents that trade-off.

## 3. AD FS (the legacy starting point)

- **Federation service name:** `sts.ad.potomacdefense.internal`
- **TLS certificate:** issued by `FRD-CA-01`, so the CA is built first (section 7 happens before section 3 in build order)
- **Service account:** a **gMSA** (`gmsa-adfs`), the same pattern as the Project 1 JML engine. Nobody knows the password
- **Token-signing and decryption certificates:** AD FS-managed, with automatic rollover. Their private keys are what a Golden SAML attack steals, so access to the server is restricted to Tier 0
- **Auditing:** AD FS auditing enabled, and events forwarded to the Log Analytics workspace from Project 2

**Test:** the AD FS sign-in page loads, and `Get-AdfsProperties` shows the expected service name and certificate.

## 4. SAML application: on AD FS, then migrated

**Before migration:** a SAML test application configured as a **relying party trust** on AD FS.
- **Claims:** NameID = UPN, plus email and group claims, using only what the app needs
- **Test:** a PDS user signs in through AD FS and the app shows the claims it received

**Migration steps:**
1. **Inventory:** review AD FS application activity and the relying party's claim rules (Entra has a report for this once AD FS sign-ins are monitored)
2. **Recreate** the app in Entra ID as an enterprise application with SAML single sign-on, matching identifier, reply URL and claims
3. **Assign** the app to a group, so only the right users see it
4. **Apply Conditional Access** (Project 2 policies)
5. **Cut over:** switch the app to Entra's SAML metadata. Test sign-in, then disable the relying party trust in AD FS
6. **Monitor** Entra sign-in logs for the app, and AD FS logs to confirm no traffic remains

**Test:** after cutover, sign-in works through Entra, MFA is enforced by Conditional Access, a user in `CA-Block-Leavers` is blocked, and AD FS shows no new sign-ins for the app.

## 5. OIDC and OAuth application

- **App registration** in Entra ID for a simple web application
- **Flow:** authorization code flow with PKCE (the current recommended flow for interactive sign-in)
- **Permissions:** delegated `User.Read` only. Consent is reviewed and documented, including what *admin consent* means and why users shouldn't be able to consent to risky permissions
- **Tokens:** an ID token and an access token are decoded and every important claim is explained: `iss`, `aud`, `sub`, `oid`, `scp`, `exp`, `amr`
- **Secrets:** the app uses a **certificate**, not a client secret, continuing the "zero secrets" rule from Project 1

**Test:** sign in through the app, decode both tokens, and confirm the access token has only the expected scope.

## 6. SCIM provisioning

- **Target:** an application that accepts SCIM provisioning from Entra ID (see open decisions)
- **Scope:** users assigned to the app through a group
- **Attribute mapping:** username, name, email, department and `employeeId`, matching on `employeeId` like every other match in this portfolio
- **Deprovisioning:** when a user is removed from the group or disabled, the account in the app is disabled. This extends the Project 1 leaver to downstream apps

**Test:** run a Project 1 joiner and confirm the account appears in the app. Run a leaver and confirm it's disabled in the app. Record how long each takes.

## 7. PKI and certificate-based authentication

**Certificate authority (`FRD-CA-01`):**
- Enterprise CA with templates for **user authentication** and **web server** certificates
- Template permissions: only the right groups can enroll. Misconfigured templates are a known path to domain compromise, so each template's enrollment rights and settings are reviewed and documented
- Certificate revocation list published, with the revocation process tested

**Entra certificate-based authentication:**
- Upload the CA certificate to Entra's trusted certificate authorities
- Bind certificates to users with a **strong (high-affinity) binding**
- Configure certificate-based authentication as **multifactor**, so it satisfies the Project 2 phishing-resistant authentication strength
- **Lab limitation:** Entra checks revocation lists over the internet, and this lab's CRL is internal only. The build log documents how revocation checking is handled and what production would need

**Test:** a user signs in to Entra with a certificate instead of a password, the sign-in log shows certificate-based authentication, and a revoked certificate is refused (or the limitation is documented).

## 8. Decommission and security review

- Confirm no relying party trusts still receive sign-ins
- Remove AD FS, and remove its gMSA and DNS records
- Review: token-signing key handling while AD FS was running, CA template permissions, app consents and permissions, and which apps are covered by Conditional Access
- Write up how this lab maps to real migrations, and what an organization would need to watch for (Golden SAML, certificate template abuse, over-permissioned app registrations)

## 9. Open decisions

These get settled during part 3.1 and are recorded in the build log:

| Decision | Options |
|---|---|
| SAML test application | A self-hosted SAML test app on IIS, or a free SaaS app that supports SAML from both AD FS and Entra |
| SCIM target | A free-tier SaaS app with SCIM support, or a SCIM test endpoint |
| Client for AD FS and CA testing | A domain-joined test VM that trusts the internal CA, or the DC itself (avoided, since browsing from Tier 0 breaks the Project 1 rules) |
| Cost | Run order that keeps the two new VMs off when not in use |
