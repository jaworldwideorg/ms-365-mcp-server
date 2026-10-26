# JA Worldwide fork deployment

`JA build and deploy` runs on every push (all branches), or manual dispatch. It
checks the exact commit, generates Graph clients, runs lint/format/typecheck/tests,
builds, checks the 250,000-byte hybrid schema budget, pushes a commit-tagged image
to `jaworldwide.azurecr.io/librechat/mcp/microsoft-softeria`, then deploys its digest
to ACA `mcp-microsoft-softeria`. Deployments are serialized. Branch pushes affect
this test app; production approval gates are not configured.

`JA daily upstream sync` checks Softeria `main` daily at 04:17 UTC. It merges into
the fork's `main` without force-pushing, runs the same checks, and only pushes a
successful merge. Conflicts/check failures stop the merge and deployment. A
successful merge explicitly dispatches build/deploy because pushes made with
`GITHUB_TOKEN` do not trigger ordinary push workflows. Manual dispatch tests sync
immediately; its optional `target_branch` allows an isolated branch to test the
actual merge-and-deploy path without changing main. If upstream is already included, it exits without rebuilding.

The upstream npm/release workflows are disabled in this fork; the JA workflows
own CI and deployment. GitHub scheduled workflows require Actions to remain
enabled and can be delayed or suspended by GitHub's schedule policies.

Authentication:

- ACR token `github-mcp-microsoft-softeria` can read/write content and metadata in
  this image repository only. Its credentials are GitHub secrets `ACR_USERNAME`
  and `ACR_PASSWORD`; content/delete is not granted.
- ACR token `aca-mcp-microsoft-softeria` can only read that image repository. Its
  password is an ACA registry secret; no admin-account credential is used.
- Azure user-assigned identity `ja-softeria-deployer` trusts only the GitHub
  `aca-test` environment in this repository via OIDC. Contributor is scoped to
  the single container app, not the resource group or subscription.
- Token passwords expire after 365 days and must be rotated before expiry.

Repository variables: `ACR_LOGIN_SERVER`, `ACR_IMAGE_NAME`, `AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ACA_RESOURCE_GROUP`, `ACA_APP_NAME`.

`ci/eager-tools.json` is deployment-specific: 33 direct mail/calendar/shared-access
operations plus complete discovery. It does not narrow the discovery catalogue or
permissions. Editing the list triggers CI/deployment and must satisfy the budget.
No Entra credentials are checked into Git; updates preserve existing ACA settings.

Evidence is uploaded for every deployment run, including the current/previous image
and ready revision. To roll back, update the app to the previous image digest and
restore its prior args (official images do not support `--eager-tools`).
