# brig·id — `roots`

Central orchestration workspace for the **brig·id** organization.

This repository is the bootstrap entry point for development across the organization. It hosts:

- the shared [VS Code multi-root workspace](./brig-id.code-workspace)
- the shared [devcontainer](./.devcontainer/devcontainer.json)
- the workspace-level AI guidance shared across the org

It does **not** contain product runtime code, and does not contain a CLI — it is
configuration and documentation only.

## Current layout

```text
brig-id/
├── roots/          # this repo — workspace, devcontainer, AI guidance
├── .github/        # org-wide GitHub defaults and reusable workflows
├── cli/            # brigid dev orchestrator CLI
├── crypto/         # cryptographic primitives
├── core/           # business logic crates
├── server-leaf/    # single-server deployment binary
├── server-grove/   # multi-server orchestration (future)
├── server-forest/  # global federation layer (future)
├── spec/           # technical specs for audit
├── app/            # Qwik UI
└── site/           # public marketing/landing site
```

## Quick start — GitHub Codespaces (recommended)

Open a Codespace on `brig-id/roots` directly from GitHub. the `org-workspace`
feature clones the org's repos (see `.devcontainer/devcontainer.json`)
into `/workspaces/<repo>` automatically — there's nothing to
pre-clone. This is the only devcontainer path this repo supports without any
manual setup.

Secrets (`GH_TOKEN`, …) come from OpenBao — `kv/orgs/brig-id`, plus `kv/shared/*` — through the
[`openbao-env`](https://github.com/helpers4/devcontainer/tree/main/src/openbao-env) feature, into
every process of the container (VS Code included). On fajro, `devc up brig-id` hands the
container its credentials. In GitHub Codespaces, set the Codespaces secrets `BAO_ROLE_ID` and
`BAO_SECRET_ID` (AppRole `brig-id`) and give the codespace Tailscale access: OpenBao is only
reachable on the tailnet.

## Quick start — local (Docker Desktop / WSL2)

### 1. Clone this repo

```bash
gh repo clone brig-id/roots
```

### 2. Open the shared workspace

```bash
code roots/brig-id.code-workspace
```

### 3. Reopen in the devcontainer

Same as Codespaces: sibling repos are cloned automatically by
`postCreateCommand`, nothing needs to be pre-cloned side by side on the host.
The secrets come from OpenBao (see above).

## Verifying the environment

After the container starts, run:

```bash
bash .devcontainer/test-container.sh
```

It checks the Rust toolchain, cargo tools, `gh` auth, and that every sibling
expected repo was cloned successfully.

When a new repository is added to the organization, update the `org-workspace` options in
`.devcontainer/devcontainer.json` and `brig-id.code-workspace` together.
