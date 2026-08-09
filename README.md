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

Open a Codespace on `brig-id/roots` directly from GitHub. `postCreateCommand`
clones every sibling repo listed in `.devcontainer/devcontainer.json`'s
`BRIG_ID_REPOS` into `/workspaces/<repo>` automatically — there's nothing to
pre-clone. This is the only devcontainer path this repo supports without any
manual setup.

If you want `gh` to stay authenticated inside the container (needed to clone
private/rate-limited resources and for `test-container.sh`'s checks), set a
Codespaces secret or export a token on the host **named `GH_TOKEN_FOR_BRIG_ID`**
before creating/reopening the codespace — not `GH_TOKEN` (that name is
deliberately different so it doesn't collide with a token you may already have
exported globally for other, unrelated projects):

```bash
export GH_TOKEN_FOR_BRIG_ID="$(gh auth token)"
```

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
Export `GH_TOKEN_FOR_BRIG_ID` first (see above) so `gh`/`git` can clone them.

## Verifying the environment

After the container starts, run:

```bash
bash .devcontainer/test-container.sh
```

It checks the Rust toolchain, cargo tools, `gh` auth, and that every sibling
repo in `BRIG_ID_REPOS` was cloned successfully.

When a new repository is added to the organization, update `.devcontainer/devcontainer.json`
(`BRIG_ID_REPOS`) and `brig-id.code-workspace` together.
