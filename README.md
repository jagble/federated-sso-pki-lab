# Federated SSO and PKI Lab: AD FS to Entra Migration, SAML, OIDC and Certificate-Based Authentication


This is Project 3 of my IAM portfolio. It uses the same fictional company, **Potomac Defense Systems (PDS)**, the same Active Directory domain from [Project 1](https://github.com/jagble/hybrid-iam-jml-lab), and the Conditional Access policies from Project 2.

> **About this lab:** PDS is a fictional defense and space contractor. Every person, account and piece of data is made up. The lab runs in my own Azure subscription and Entra ID tenant.

---

## Why this project

Projects 1 and 2 control **who** has access. This one is about **how** that access reaches applications:

| Question | What this project builds |
|---|---|
| Many organizations still run **AD FS** for single sign-on. How do you move apps off it safely? | Deploy AD FS as the "legacy" starting point, federate an app with it, then **migrate** that app to Entra ID and decommission AD FS |
| How do SAML, OpenID Connect and OAuth actually differ? | One **SAML** app and one **OIDC/OAuth** app, with the tokens inspected and explained |
| How do accounts get into SaaS apps without someone creating them by hand? | **SCIM** provisioning from Entra ID to an application, including deprovisioning when someone leaves |
| How do federal environments sign in with smart cards (CAC/PIV)? | An internal **PKI** (AD CS) and **certificate-based authentication** in Entra ID, the closest lab equivalent to CAC/PIV |

## Parts

| Part | Title | What gets built | Status |
|:---:|---|---|:---:|
| **3.1** | Design and prep | Design doc, server plan, open decisions | ✅ Design written |
| **3.2** | AD FS deployment | AD FS server (Tier 0), federation service certificate | Planned |
| **3.3** | SAML app on AD FS | A relying party trust, claim rules, test sign-in | Planned |
| **3.4** | Migrate to Entra ID | App activity review, recreate the app in Entra as SAML, cut over, Conditional Access applied | Planned |
| **3.5** | OIDC and OAuth | App registration, authorization code flow, scopes and consent, token inspection | Planned |
| **3.6** | SCIM provisioning | Automatic provisioning and deprovisioning to an app, tied to the JML lifecycle | Planned |
| **3.7** | PKI and certificate-based authentication | AD CS certificate authority, user certificates, Entra certificate-based authentication | Planned |
| **3.8** | Decommission and review | Remove AD FS, protect token-signing keys while it runs, final security review | Planned |

## Design

The full design is in [`docs/01-design.md`](docs/01-design.md). In short:

- **AD FS is treated as Tier 0.** Whoever controls its token-signing key can forge sign-ins for any user (a "Golden SAML" attack), so it gets the same protection as a domain controller, and the end goal is removing it
- **Migration, not just setup.** The project starts where many real organizations are: apps on AD FS. It ends with the apps in Entra ID and AD FS gone
- **Every federated app gets Conditional Access** from Project 2, so MFA and the leaver block apply to it automatically
- **SCIM closes the loop on JML.** A leaver in Project 1 gets removed from the downstream app automatically, not just from AD and Entra
- **Certificate-based authentication** counts as phishing-resistant MFA, the same assurance level federal environments get from CAC/PIV

## Skills this project covers

AD FS · federation · SAML 2.0 · OpenID Connect · OAuth 2.0 · app registrations and enterprise apps · claims and token inspection · SCIM provisioning · AD CS / PKI · certificate lifecycle · certificate-based authentication · application migration · Golden SAML and token-signing key protection

---

Built by **Josh Agble** · [github.com/jagble](https://github.com/jagble)
