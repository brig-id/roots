# Claude Code — brig·id workspace

Full canonical rules (commit format, restrictions, language) live in
[AGENTS.md](AGENTS.md). This file adds Claude Code-specific context.

## Workspace layout

All repos are cloned as siblings at `/workspaces/<name>` by
`.devcontainer/setup-container.sh`'s `postCreateCommand` (not bind-mounted —
this is what makes the devcontainer work on GitHub Codespaces as well as
local Docker Desktop/WSL2), and open together in `brig-id.code-workspace`:

| Path | Repo | Role |
| ---- | ---- | ---- |
| `/workspaces/roots` | `roots` | Orchestration — canonical AGENTS.md, devcontainer |
| `/workspaces/.github` | `.github` | Org-level GitHub config + reusable workflows |
| `/workspaces/crypto` | `crypto` | Cryptographic primitives |
| `/workspaces/core` | `core` | Business logic crates |
| `/workspaces/server-leaf` | `server-leaf` | Single-server deployment binary |
| `/workspaces/server-grove` | `server-grove` | Multi-server orchestration (future) |
| `/workspaces/server-forest` | `server-forest` | Global federation layer (future) |
| `/workspaces/spec` | `spec` | Technical specs for audit |
| `/workspaces/app` | `app` | Qwik UI |

## Common commands (run from any product repo)

```bash
cargo test --workspace
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt --all --check
cargo audit
cargo deny check
cargo llvm-cov --workspace --summary-only

# fuzzing (nightly required)
cargo +nightly fuzz run fuzz_decrypt -- -max_total_time=60
```

## Common gotchas

**Commit scopes**: always read `scopes.json` at the active repo root before choosing a scope.
Never invent a scope that isn't listed. Full type→emoji mapping: `/workspaces/roots/commit-convention.json`.
Use `/commit` (Claude Code slash command) to auto-generate a message from staged changes.

**Cargo target/volumes**: `CARGO_TARGET_DIR=/cargo-target` and the cargo registry/git caches are
Docker named volumes (`brigid-cargo-*`), never on the host — don't assume a `target/` dir exists
inside a repo checkout.

**Toolchain**: stable Rust is the devcontainer base; nightly is installed separately (rust-src +
llvm-tools-preview) only for `cargo-fuzz`. See `.devcontainer/setup-container.sh` for the full
list of installed cargo tools.

**Environment self-check**: run `.devcontainer/test-container.sh` after a container rebuild to
verify the Rust toolchain, cargo tools, GH auth, and cloned sibling repos are all in the
expected state.

**Roadmap tracking**: check [Project 1](https://github.com/orgs/brig-id/projects/1) before
starting product work — TODOs, backlog ideas, and release/phase status live there as cards,
not in local files, per AGENTS.md's Rules section.

**Git workflow**: `main` and `dev/*` are protected — never push directly. Branch from `dev/*`
(`feat/*`/`bug/*`) or from `main` for an urgent prod fix (`hotfix/*`). Every merge is rebase +
fast-forward only — rebase onto the target's tip before merging, no merge commits, no squash.
See AGENTS.md's Git Workflow section.

## AI persistence

`~/.claude` is bind-mounted from the host and symlinked at every container start by
`claude-dev`. Memory, credentials, and settings survive all rebuilds.
