#!/usr/bin/env bash
set -euo pipefail

# ── Fix volume ownership (volumes created as root by Docker) ────────────────────
# CARGO_TARGET_DIR points to a named volume — must be writable by node.
if [ -d "${CARGO_TARGET_DIR:-/cargo-target}" ]; then
  sudo chown -R node:node "${CARGO_TARGET_DIR:-/cargo-target}"
fi

# /workspaces itself is created by Docker as the parent of the workspaceMount
# target and comes out root:root — only `roots` (the bind-mounted
# workspaceFolder) inherits node ownership from the mount. Every sibling repo
# below is cloned fresh inside the container, so without this chown `node`
# gets "Permission denied" creating /workspaces/<repo> for all of them.
sudo chown node:node /workspaces

# ── Git commit signing (SSH format) ─────────────────────────────────────────────
# dotfiles-sync no longer bind-mounts ~/.ssh from the host (see devcontainer.json),
# so the public-key file that user.signingkey points at never lands in the
# container — even though VS Code/Codespaces still forward the host's ssh-agent
# (SSH_AUTH_SOCK) for the actual signing operation. Recover just that one public
# key — it isn't sensitive — from whatever the forwarded agent already has
# loaded, matched to git's configured user.email. Generic across teammates:
# nothing here is hardcoded to a specific key filename.
if [ "$(git config --get gpg.format 2>/dev/null || true)" = "ssh" ]; then
  signingkey_path="$(git config --get user.signingkey 2>/dev/null || true)"
  signingkey_path="${signingkey_path/#\~/$HOME}"
  user_email="$(git config --get user.email 2>/dev/null || true)"
  if [ -n "$signingkey_path" ] && [ ! -f "$signingkey_path" ] && [ -n "$user_email" ] \
    && command -v ssh-add >/dev/null 2>&1; then
    if pubkey="$(ssh-add -L 2>/dev/null | grep " ${user_email}\$")" && [ -n "$pubkey" ]; then
      mkdir -p "$(dirname "$signingkey_path")"
      echo "$pubkey" > "$signingkey_path"
      chmod 644 "$signingkey_path"
      echo "✓ Recovered SSH signing public key for commit signing ($signingkey_path)."
    else
      echo "! Commit signing key missing ($signingkey_path) and no matching key in ssh-agent — commits will fail to sign."
    fi
  fi
fi

ORG="${BRIG_ID_ORG:-brig-id}"
REPOS="${BRIG_ID_REPOS:-.github}"

# ── Clone sibling repositories ──────────────────────────────────────────────────
# This is the *only* way sibling repos are provisioned — there is no bind mount
# fallback. That's deliberate: bind-mounting `../<repo>` from the host only works
# for a local Docker Desktop/WSL2 checkout where all repos were pre-cloned side by
# side; it silently breaks GitHub Codespaces, which only ever checks out the one
# repo you launched the codespace from. Cloning here, in postCreateCommand, works
# identically in both environments.
echo "Setting up ${ORG} workspace..."

for repo in $REPOS; do
  target="/workspaces/${repo}"

  if [ -d "${target}/.git" ] || [ -n "$(ls -A "${target}" 2>/dev/null || true)" ]; then
    echo "✓ ${repo}: already available"
    continue
  fi

  echo "→ ${repo}: cloning sibling repository"
  if command -v gh >/dev/null 2>&1; then
    gh repo clone "${ORG}/${repo}" "${target}" || echo "! ${repo}: clone failed"
  else
    git clone "https://github.com/${ORG}/${repo}.git" "${target}" || echo "! ${repo}: clone failed"
  fi
done

echo "✓ Workspace repos ready."

# ── Web Awesome Pro npm registry auth ───────────────────────────────────────────
# `app/.npmrc` (committed) points `@web.awesome.me` at the private Cloudsmith
# registry but deliberately omits the auth token — pnpm won't expand env vars
# from a project-tracked .npmrc, and committing a literal token is out of the
# question. The token itself reaches the container fine via devcontainer.json's
# containerEnv, but nothing ever wrote it into ~/.npmrc, so `pnpm install` for
# `app` 401s on that package until this runs.
if [ -n "${WEBAWESOME_NPM_TOKEN:-}" ] && ! grep -q "npm.cloudsmith.io/fortawesome/webawesome-pro" ~/.npmrc 2>/dev/null; then
  echo ""
  echo "Configuring Web Awesome Pro registry auth..."
  echo "//npm.cloudsmith.io/fortawesome/webawesome-pro/:_authToken=${WEBAWESOME_NPM_TOKEN}" >> ~/.npmrc
  echo "✓ Web Awesome Pro auth configured."
fi

# ── Rust toolchain ─────────────────────────────────────────────────────────────
echo ""
echo "Setting up Rust toolchain..."

# llvm-tools-preview on stable — required by cargo-llvm-cov
rustup component add llvm-tools-preview

# Nightly (required by cargo-fuzz) + same components for consistency
rustup toolchain install nightly \
  --component rust-src,llvm-tools-preview \
  --no-self-update

# wasm32-unknown-unknown: not currently required by any brig·id crate (no crate
# in the org targets wasm32 today) — kept for wasm-pack and as a low-cost
# preinstall in case a future crate needs it. Not tied to any specific framework.
rustup target add wasm32-unknown-unknown

echo "✓ Rust toolchain ready (stable + nightly, wasm32)."

# ── cargo-binstall ─────────────────────────────────────────────────────────────
if ! command -v cargo-binstall >/dev/null 2>&1; then
  echo ""
  echo "Installing cargo-binstall (fast pre-compiled binaries)..."
  curl -L --proto '=https' --tlsv1.2 -sSf \
    https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh \
    | bash
  echo "✓ cargo-binstall ready."
fi

# ── Rust tools via pre-compiled binaries ──────────────────────────────────────
echo ""
echo "Installing Rust tools (cargo-binstall)..."

cargo binstall --no-confirm --quiet \
  cargo-audit \
  cargo-deny \
  cargo-vet \
  cargo-nextest \
  cargo-llvm-cov \
  cargo-edit \
  cargo-watch \
  cargo-cyclonedx \
  just \
  wasm-pack \
  mprocs

echo "✓ Rust tools installed."

# ── cargo-fuzz (nightly only, no pre-compiled binary available) ────────────────
if ! command -v cargo-fuzz >/dev/null 2>&1; then
  echo ""
  echo "Installing cargo-fuzz (nightly)..."
  cargo +nightly install cargo-fuzz --quiet
  echo "✓ cargo-fuzz ready."
fi

# ── mold linker (2-5× faster than lld for incremental builds) ──────────────────
if ! command -v mold >/dev/null 2>&1; then
  echo ""
  echo "Installing mold linker..."
  MOLD_VERSION="2.35.1"
  MOLD_ARCHIVE="mold-${MOLD_VERSION}-x86_64-linux.tar.gz"
  curl -L --proto '=https' --tlsv1.2 -sSf \
    "https://github.com/rui314/mold/releases/download/v${MOLD_VERSION}/${MOLD_ARCHIVE}" \
    -o "/tmp/${MOLD_ARCHIVE}"
  sudo tar -xzf "/tmp/${MOLD_ARCHIVE}" -C /usr/local --strip-components=1 \
    --wildcards "*/bin/mold" "*/bin/ld.mold" "*/lib/mold/"
  rm -f "/tmp/${MOLD_ARCHIVE}"
  echo "✓ mold ready."
fi

# ── mkcert (local HTTPS for `server-leaf` / `app` dev) ───────────────────────────
if ! command -v mkcert >/dev/null 2>&1; then
  echo ""
  echo "Installing mkcert..."
  MKCERT_VERSION="1.4.4"
  curl -L --proto '=https' --tlsv1.2 -sSf \
    "https://github.com/FiloSottile/mkcert/releases/download/v${MKCERT_VERSION}/mkcert-v${MKCERT_VERSION}-linux-amd64" \
    -o /tmp/mkcert
  sudo install -m 755 /tmp/mkcert /usr/local/bin/mkcert
  rm -f /tmp/mkcert
  echo "✓ mkcert ready."
fi

echo ""
echo "✓ brig·id workspace ready."
