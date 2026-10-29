# Federated SSO and PKI Lab: AD FS to Entra Migration, SAML, OIDC and Certificate-Based Authentication

**Status: 🔨 In progress, 2 of 8 parts done.** The design was written before the build, and parts are checked off as they're completed.

This is Project 3 of my IAM portfolio. It uses the same fictional company, **Potomac Defense Systems (PDS)**, the same Active Directory domain from [Project 1](https://github.com/jagble/hybrid-iam-jml-lab), and the Conditional Access policies from Project 2.

> **About this lab:** PDS is a fictional defense and space contractor. Every person, account and piece of data is made up. The lab runs in my own Azure subscription and Entra ID tenant.

---

## Why this project

Projects 1 and 2 control **who** has access. This one is about **how** that access reaches applications:

| Question | What this project builds |
|---|---|
| Many organizations still run **AD FS** for single sign-on. How do you move apps off it safely? | Deploy AD FS as the "legacy" starting point, federate an app with it, then **migrate** that app to Entra ID and decommission AD FS |
| How do SAML, OpenID Connect and OAuth actually differ? | One **SAML** app and one **OIDC/OAuth** app, with the tokens inspected and explained |
| How do accounts get into SaaS apps without someone creating them by hand? | **Automatic provisioning** from Entra ID to ServiceNow, including deprovisioning when someone leaves |
| How do federal environments sign in with smart cards (CAC/PIV)? | An internal **PKI** (AD CS) and **certificate-based authentication** in Entra ID, the closest lab equivalent to CAC/PIV |

## Parts

| Part | Title | What gets built | Status |
|:---:|---|---|:---:|
| **3.1** | [Design and prep](parts/3.1-design-and-prep/README.md) | Decisions, build order, capacity plan, the CA server | ✅ Done |
| **3.2** | [PKI](parts/3.2-pki/README.md) | Enterprise CA with no default templates, auditing, a public CRL published daily by a managed identity | ✅ Done |
| **3.3** | AD FS | AD FS server (Tier 0) running as a gMSA, TLS certificate from the CA | Next |
| **3.4** | SAML on AD FS | ServiceNow signing in through AD FS: relying party trust, claim rules | Planned |
| **3.5** | Migrate to Entra ID | ServiceNow moved to Entra SAML, Conditional Access applied, AD FS decommissioned | Planned |
| **3.6** | OIDC and OAuth | App registration, authorization code flow with PKCE, scopes and consent, token inspection | Planned |
| **3.7** | Provisioning | Automatic provisioning and deprovisioning to ServiceNow, tied to the JML lifecycle | Planned |
| **3.8** | Certificate-based authentication and review | User certificates, Entra certificate-based authentication, revocation test, final security review | Planned |

## Results so far

| Area | Result |
|---|---|
| **Certificate authority** | `PDS-Root-CA` issues **nothing until a template is added on purpose**. By default a new enterprise CA would publish about 11 certificate types, some open to every user |
| **Revocation** | The CRL is **public over HTTP**, so Entra ID can check revocation. A scheduled task uploads it daily using the CA VM's **managed identity**, scoped to one container, with storage account keys disabled |
| **Privileged access** | Enterprise Admins was granted for the CA install only. The group is now **empty** |
| **Findings** | 10 so far. See [3.1](parts/3.1-design-and-prep/README.md#5-findings) and [3.2](parts/3.2-pki/README.md#8-findings) |

## Repository

| Folder | What's in it |
|---|---|
| [`parts/`](parts/) | Step-by-step walkthroughs with screenshots, one per part |
| [`docs/`](docs/) | The design |
| [`scripts/`](scripts/) | CA policy file, CA install and configuration, CRL publishing |

## Design

The full design is in [`docs/01-design.md`](docs/01-design.md). In short:

- **AD FS is treated as Tier 0.** Whoever controls its token-signing key can forge sign-ins for any user (a "Golden SAML" attack), so it gets the same protection as a domain controller, and the end goal is removing it
- **Migration, not just setup.** The project starts where many real organizations are: apps on AD FS. It ends with the apps in Entra ID and AD FS gone
- **Every federated app gets Conditional Access** from Project 2, so MFA and the leaver block apply to it automatically
- **Provisioning closes the loop on JML.** A leaver in Project 1 gets removed from the downstream app automatically, not just from AD and Entra
- **Certificate-based authentication** counts as phishing-resistant MFA, the same assurance level federal environments get from CAC/PIV

## Skills this project covers

AD FS · federation · SAML 2.0 · OpenID Connect · OAuth 2.0 · app registrations and enterprise apps · claims and token inspection · app provisioning · AD CS / PKI · CRL publishing · managed identities · certificate lifecycle · certificate-based authentication · application migration · Golden SAML and token-signing key protection

---

Built by **Josh Agble** · [github.com/jagble](https://github.com/jagble)
