# AGENTS.md — brig·id `roots`

This repository is the **shared workspace** for the brig·id organization.

## Language

**All content in all brig·id repositories must be in English** — code, comments,
doc-comments, commit messages, issues, pull requests, specs, and configuration.
This rule applies to every sibling repository. No exceptions.

## Scope

- VS Code multi-root workspace (`brig-id.code-workspace`)
- devcontainer setup (`.devcontainer/`)
- shared AI / agent guidance

This repository contains **no product runtime code and no CLI** — it is
configuration and documentation only. (The org previously kept a `brigid` dev
orchestrator CLI here; it does not live in this repo.)

## Workspace structure

All repositories are cloned as siblings under `/workspaces/` by
`.devcontainer/setup-container.sh`'s `postCreateCommand` step — nothing is
bind-mounted from the host. This is what makes the devcontainer work
identically on a local checkout (Docker Desktop/WSL2) and on GitHub
Codespaces, which only ever checks out the one repo you launch the
codespace from.

| Path | Repo | Purpose |
| --- | --- | --- |
| `/workspaces/roots` | `brig-id/roots` | This repo — orchestration |
| `/workspaces/.github` | `brig-id/.github` | Org-level GitHub config + reusable workflows |
| `/workspaces/cli` | `brig-id/cli` | `brigid` dev orchestrator CLI |
| `/workspaces/crypto` | `brig-id/crypto` | Cryptographic primitives |
| `/workspaces/core` | `brig-id/core` | Business logic crates |
| `/workspaces/server-leaf` | `brig-id/server-leaf` | Single-server deployment binary |
| `/workspaces/server-grove` | `brig-id/server-grove` | Multi-server orchestration (future) |
| `/workspaces/server-forest` | `brig-id/server-forest` | Global federation layer (future) |
| `/workspaces/spec` | `brig-id/spec` | Technical specs for audit |
| `/workspaces/app` | `brig-id/app` | Qwik UI |
| `/workspaces/site` | `brig-id/site` | Public marketing/landing site |

## Devcontainer — available tools

The container is self-contained; no host Rust installation is needed.

- **Rust stable** (via devcontainer feature) + **nightly** (for `cargo-fuzz`)
- **wasm32-unknown-unknown** target (preinstalled; not currently required by
  any brig·id crate)
- **mold** linker (faster incremental builds)
- `cargo-binstall`, `cargo-audit`, `cargo-deny`, `cargo-vet`
- `cargo-nextest`, `cargo-llvm-cov`, `cargo-fuzz`
- `cargo-edit`, `cargo-watch`, `cargo-cyclonedx`
- `just`, `wasm-pack`, `mprocs` (split-pane process runner)
- `mkcert` (local HTTPS, used when running `server-leaf`/`app` outside Docker)
- `gh` CLI, `docker` CLI

Cargo volumes are Docker named volumes (`brigid-cargo-*`) — nothing written to the host.
`CARGO_TARGET_DIR=/cargo-target` (named volume, not inside any repo).

## Roadmap & planning

TODOs, backlog ideas, and phase/release tracking live in the org's GitHub Project,
not in local files: **[brig-id Project 1](https://github.com/orgs/brig-id/projects/1)**
(cross-repo — items belong to whichever `brig-id/*` repo they concern). Check it
before starting product work. Open a card there for new work instead of adding a
local TODO/roadmap file.

## Common commands

```bash
# Run from any product repo
cargo test --workspace
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt --all --check
cargo audit
cargo deny check
cargo llvm-cov --workspace --summary-only

# Run fuzzing (nightly required)
cargo +nightly fuzz run fuzz_decrypt -- -max_total_time=60
```

## Rules

- Treat this repository as configuration/documentation only — no product
  runtime code and no CLI tooling here.
- Add future repositories as siblings of `roots/`, not nested inside it.
- Update **all four** of these together when a new sibling repository is added — each keeps its
  own hardcoded repo list and none of them read from another:
  - `.devcontainer/devcontainer.json` (`mounts`, `BRIG_ID_REPOS`)
  - `brig-id.code-workspace` (the `folders` list)
  - `.devcontainer/test-container.sh` (the `for repo in ...` loop)
  - `cli/repos.json`
- Do not implement the product plan here unless the task is explicitly about shared tooling.
- Track TODOs, backlog ideas, and release/phase status as cards in
  [Project 1](https://github.com/orgs/brig-id/projects/1), not as local
  Markdown files (`TODO.md`, `phases/*.md`, etc.).

## Commit conventions

Format: `type(scope): <emoji> description`

| Type | Emoji | When |
| --- | --- | --- |
| `feat` | ✨ | New feature or file |
| `fix` | 🐛 | Correction |
| `docs` | 📝 | Documentation only |
| `chore` | 🔧 | Maintenance, config |
| `ci` | 👷 | CI/CD |
| `revert` | ⏪ | Reverts a previous commit |

### Allowed scopes

Scopes live in `scopes.json` at this repo's root (machine-readable source of truth,
also read by the `/commit` slash command):

| Scope | Maps to |
| --- | --- |
| `memory` | `memory/` — persistent agent memory files |
| `workspace` | `brig-id.code-workspace`, root-level config |
| `devcontainer` | `.devcontainer/` |
| `ai` | Agent guidance, prompt files |
| `ci` | `.github/workflows/` (if any) |

**Do not use a scope outside this list.** If a new top-level concern is added,
update `scopes.json` (and this table) and `.vscode/settings.json` together.

```text
docs(ai): 📝 point AGENTS.md at the GitHub Project instead of phases/
chore(devcontainer): 🔧 add pnpm to devcontainer features
ci(ci): 👷 add conventional commit check
```

## Git Workflow

brig·id ships to production, so branches go through an intermediate stage before `main`.
Every merge is **rebase + fast-forward only** — no merge commits, no squash merges, anywhere.

**Branches:**

| Branch | Purpose | Lifetime |
| --- | --- | --- |
| `main` | Production | Permanent |
| `dev/*` (e.g. `dev/2026-08`) | Internal/staging release train | One per cycle — deleted after merging into `main` |
| `hotfix/*` | Urgent production fix, bypasses `dev/*` | One per fix — deleted after merging into `main` |
| `feat/*`, `fix/*` | Regular work | One per change — deleted after merging into the current `dev/*` |

**Merging (always via PR, never a direct push to `main` or `dev/*`):**

- `feat/*` / `bug/*` → rebase onto the current `dev/*` tip, then fast-forward merge into `dev/*`.
- `dev/*` → rebase onto `main`'s tip, then fast-forward merge into `main`.
- `hotfix/*` → branched from `main`, rebase onto `main`'s tip, then fast-forward merge into `main`.
- If a `hotfix/*` lands on `main` while a `dev/*` is still in flight, rebase that `dev/*` onto the
  new `main` before its own merge — fast-forward tolerates no divergence.
- Releases are tracked with **tags on `main`** (there's no merge commit to mark them, since every
  merge is a fast-forward).

**Release checklist** — the tag, `CHANGELOG.md`, and `Cargo.toml`'s `version` must always tell the
same story. Skipping the version bump has happened more than once (a tagged release shipped with
the *previous* version still in `Cargo.toml`) — always do these in order, in the same PR that
lands on `main`:

1. Bump `version` in `Cargo.toml` (workspace-level for a cargo workspace).
2. Add the release's entry to `CHANGELOG.md`.
3. Merge to `main`, then tag `vX.Y.Z` on the resulting commit.

Never pin another repo's git dependency to a bare commit `rev` that isn't reachable from a tag —
this workflow's rebase+fast-forward merges rewrite SHAs, so an unreached commit can become
permanently unfetchable once the source repo garbage-collects it. Pin `tag = "vX.Y.Z"` instead
(or, if no tag exists yet for the content you need, treat that as a signal to cut one).

## Inheritance

This repo's *shape* (`CLAUDE.md`, `scopes.json`, `commit-convention.json`,
`.claude/commands/commit.md`) is ported from
[helpers4/.dev](https://github.com/helpers4/.dev)'s canonical setup. Deltas from that shape:
- **Stack: Rust/cargo**, not TypeScript — `core`/`crypto`/`server-*` are cargo crates; only `app`
  is a pnpm/Qwik project.
- **License: LGPL-3.0-or-later**, same as helpers4.
- `test-container.sh` (environment self-check) and the cargo-volume-heavy, nightly/wasm/mold
  install logic in `setup-container.sh` are brig·id-specific and intentionally not shared with
  the TypeScript-only orgs.
- Roadmap/phase tracking uses a GitHub Project (org-level, cross-repo) instead of
  local Markdown files — a brig·id-specific choice, not part of helpers4's template.
- Sibling repos are cloned in `postCreateCommand`, never bind-mounted from the host — a
  deliberate change from an earlier revision of this repo (then named `.dev`) so the
  devcontainer works on GitHub Codespaces, not just local Docker Desktop/WSL2.
