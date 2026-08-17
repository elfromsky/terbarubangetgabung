# PRD auth model decision (Issue #18)

> Authoritative clarification / revision for the PRD v0.1 user/authentication
> model referenced by Issue #18
> (<https://github.com/elfromsky/esh-smart-home/issues/18>).

The PRD v0.1 is maintained outside this repository. This document is the
linked, repository-tracked revision that resolves the ambiguity between the
PRD's no-user-login / no-user-role requirement and the project's settled
Firebase trusted-device authorization contract (Issues #3, #5). It refers to
the affected PRD sections (Target User, Acceptance Criteria, Future
Development) instead of reconstructing the whole PRD.

## 1. Decision

The application distinguishes two non-overlapping authorization layers.

- **Human / product layer:** the PRD statement "no login / no user
  authentication / no role / no access-right differentiation" is TRUE at the
  household-user level.
- **Infrastructure / security layer:** Firebase Authentication with the
  strict-boolean custom claims `owner` and `controller` is a security control
  that exists invisibly to the household user and is NOT a user-facing login.

This reconciliation is called **Outcome A** in Issue #18.

## 2. Human / product layer (the three household users)

- The system targets three household users.
- All three use the same APK/application build.
- There is no login screen and no credential entry as part of normal product
  UX.
- There is no household-user account selection and no household-user role
  selection.
- There is no household-user RBAC and no permission differentiation between
  the three users.
- All three household users receive equal monitoring and control capabilities.

No household user is classified as an `owner human`, `controller human`, `admin
human`, or `viewer human`. The words `owner` and `controller` are reserved for
the security-principal layer below and never describe a human role unless a
future PRD explicitly introduces human roles.

## 3. Infrastructure / security layer (Firebase principals)

- Firebase Authentication exists and is required by the Firebase Security
  Rules; it operates invisibly to the household user.
- Firebase Authentication does NOT imply a product-level human account. An
  authenticated Firebase identity is a client/device principal.
- A generated Firebase anonymous UID identifies a trusted Flutter application
  installation, NOT a human household user.
- `owner` and `controller` are strict-boolean security authorization claims
  (security principals), NOT household-user roles and NOT three-human RBAC.
- A trusted Flutter client installation is provisioned out-of-band with
  `owner == true`.
- The Master/controller identity uses `controller == true` for
  machine-to-machine / backend authorization.
- Missing, `false`, malformed, or unauthenticated identities fail closed.

## 4. How the three household users obtain equal rights

```text
Household user
    ↓
Flutter app installation
    ↓
Firebase anonymous identity (invisible)
    ↓
out-of-band trusted provisioning (Admin SDK / Firebase Auth console)
    ↓
owner == true
    ↓
same monitoring/control capability
```

Each trusted installation carries the same `owner == true` capability, so the
three users are equal because there is no human-role mapping:

```text
Trusted Flutter installation A -> owner == true
Trusted Flutter installation B -> owner == true
Trusted Flutter installation C -> owner == true
```

The security identity belongs to the client installation, not to a human
account. If an anonymous identity changes (application data/auth state lost or
the app is reinstalled), the new UID must be provisioned again before it
receives trusted access.

## 5. Interpretation of PRD terms

| PRD term | Refined meaning |
|----------|-----------------|
| `tidak menerapkan login` | No user-facing login: no credential entry, no login page, no account selection, no role selection in normal product UX. |
| `tidak menerapkan autentikasi pengguna` | No human-user account authentication system; Firebase infrastructure authentication still exists internally and transparently. |
| `tidak menerapkan role` | No household-user roles / no human RBAC; `owner`/`controller` remain security-principal claims. |
| `tidak menerapkan perbedaan hak akses` | The three household users have equal monitoring and control rights. |
| future development: `pengembangan sistem autentikasi apabila jumlah pengguna bertambah` | Future **human-user** account authentication / account management / household-user RBAC, if product requirements expand. Backend/client infrastructure authentication is not forbidden today. |

## 6. Security invariant

Reconciliation is:

```text
no human-facing authentication != no backend authentication
```

The PRD wording is refined, not enforced by removing security:

- No public Firebase reads or writes.
- No `.read: true` / `.write: true`.
- No removal of `auth != null`.
- No weakening of `owner` / `controller` strict-boolean checks.
- No removal of Firebase Authentication, custom claims, or Firestore/RTDB
  authorization.

See `contracts/firebase-authorization.md` for the authoritative technical
contract and the current implementation status.

## 7. Implementation status

The model above is the authoritative target. Issue #17
(<https://github.com/elfromsky/esh-smart-home/issues/17>) wires the
Flutter anonymous-sign-in + owner-claim bootstrap into the Flutter runtime:
`apps/flutter/lib/main.dart` runs an authorization gate (`AuthGateController`
+ `FirebaseClaims`) before constructing the operational app. Issue #18
documents the model; the runtime bootstrap is implemented by Issue #17.
