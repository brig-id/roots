#!/usr/bin/env bash
# test-container.sh — Verifies that the devcontainer environment is complete.
# Run INSIDE the container after `postCreateCommand`.
# Usage: bash .devcontainer/test-container.sh
set -uo pipefail

PASS=0
FAIL=0
WARN=0

ok()   { echo "  ✓ $1"; ((PASS++)); }
fail() { echo "  ✗ $1"; ((FAIL++)); }
warn() { echo "  ⚠ $1"; ((WARN++)); }

check_cmd() {
  local cmd=$1 label=${2:-$1}
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$label — $(command -v "$cmd")"
  else
    fail "$label — not found"
  fi
}

check_version() {
  local cmd=$1 args=${2:---version} label=${3:-$1}
  if out=$("$cmd" $args 2>&1 | head -1); then
    ok "$label — $out"
  else
    fail "$label — failed ($out)"
  fi
}

echo ""
echo "═══════════════════════════════════════════════════"
echo "  brig·id devcontainer — environment test"
echo "═══════════════════════════════════════════════════"

# ── GitHub / git ───────────────────────────────────────────────────────────────
echo ""
echo "── GitHub & git ──"

if gh auth status >/dev/null 2>&1; then
  account=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
  ok "gh CLI authenticated — account: $account"
else
  fail "gh CLI not authenticated (GH_TOKEN missing or invalid)"
fi

if git ls-remote "https://github.com/brig-id/.github.git" HEAD >/dev/null 2>&1; then
  ok "git — read access to brig-id/.github"
else
  warn "git — HTTPS access failed (SSH may still work)"
fi

check_cmd git "git"

# ── Rust toolchain ─────────────────────────────────────────────────────────────
echo ""
echo "── Rust toolchain ──"

check_version rustup "show active-toolchain" "rustup stable"

if rustup toolchain list | grep -q nightly; then
  ok "rustup nightly — installed"
else
  fail "rustup nightly — missing (required by cargo-fuzz)"
fi

if rustup target list --installed | grep -q "wasm32-unknown-unknown"; then
  ok "target wasm32-unknown-unknown — installed"
else
  warn "target wasm32-unknown-unknown — missing (not currently required by any crate)"
fi

if rustup component list --installed | grep -q "llvm-tools"; then
  ok "llvm-tools component — installed (required by cargo-llvm-cov)"
else
  warn "llvm-tools component — missing (cargo llvm-cov may fail)"
fi

# ── Cargo tools ──────────────────────────────────────────────────────────────
echo ""
echo "── Cargo tools ──"

check_cmd cargo-audit    "cargo-audit"
check_cmd cargo-deny     "cargo-deny"
check_cmd cargo-vet      "cargo-vet"
check_cmd cargo-nextest  "cargo-nextest"
check_cmd cargo-llvm-cov "cargo-llvm-cov"
check_cmd cargo-watch    "cargo-watch"
check_cmd wasm-pack      "wasm-pack"
check_cmd just           "just (task runner)"
check_cmd cargo-fuzz     "cargo-fuzz (nightly)"
check_cmd mprocs         "mprocs (split-pane process runner)"

# ── Critical environment variables ────────────────────────────────────────────
echo ""
echo "── Environment ──"

if [ -n "${CARGO_TARGET_DIR:-}" ]; then
  ok "CARGO_TARGET_DIR=$CARGO_TARGET_DIR"
else
  warn "CARGO_TARGET_DIR not set (target/ dirs will land inside repo checkouts)"
fi

if [ -n "${GH_TOKEN:-}" ]; then
  ok "GH_TOKEN — present"
else
  fail "GH_TOKEN — missing (export GH_TOKEN_FOR_BRIG_ID on the host before reopening)"
fi

if [ -n "${WEBAWESOME_NPM_TOKEN:-}" ]; then
  if grep -q "npm.cloudsmith.io/fortawesome/webawesome-pro" "${HOME}/.npmrc" 2>/dev/null; then
    ok "WEBAWESOME_NPM_TOKEN — present and wired into ~/.npmrc"
  else
    fail "WEBAWESOME_NPM_TOKEN — present but missing from ~/.npmrc (re-run setup-container.sh)"
  fi
else
  warn "WEBAWESOME_NPM_TOKEN — missing (pnpm install will fail on @web.awesome.me)"
fi

# ── Cargo volumes ─────────────────────────────────────────────────────────────
echo ""
echo "── Cargo volumes ──"

if [ -d "${HOME}/.cargo/registry" ]; then
  ok "~/.cargo/registry — accessible"
else
  warn "~/.cargo/registry — missing (will be created on first cargo build)"
fi

if [ -d "${CARGO_TARGET_DIR:-/cargo-target}" ]; then
  ok "${CARGO_TARGET_DIR:-/cargo-target} — target volume accessible"
else
  warn "${CARGO_TARGET_DIR:-/cargo-target} — missing (will be created on first build)"
fi

# ── System tools ──────────────────────────────────────────────────────────────
echo ""
echo "── System tools ──"

check_cmd mold   "mold linker"
check_cmd docker "docker (docker-outside-of-docker)"
check_cmd node   "node"
check_cmd mkcert "mkcert (local HTTPS for server-leaf / app dev)"

# ── Workspace repos ───────────────────────────────────────────────────────────
echo ""
echo "── Workspace repos ──"

if [ -w /workspaces ]; then
  ok "/workspaces — writable by $(whoami) (sibling repos can be cloned)"
else
  fail "/workspaces — not writable by $(whoami) (sibling clones will fail with 'Permission denied'; re-run setup-container.sh)"
fi

for repo in roots .github cli crypto core server-leaf server-grove server-forest spec app site; do
  if [ -d "/workspaces/$repo" ]; then
    ok "/workspaces/$repo"
  else
    warn "/workspaces/$repo — not present (normal if not cloned yet)"
  fi
done

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
printf "  Result: %d ✓  %d ⚠  %d ✗\n" "$PASS" "$WARN" "$FAIL"
echo "═══════════════════════════════════════════════════"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "  Critical items are missing."
  echo "  Rebuild the container or re-run setup-container.sh"
  exit 1
fi
exit 0
