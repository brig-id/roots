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

# ── diff-so-fancy (git pager) ────────────────────────────────────────────────
# Global ~/.gitconfig sets core.pager = "diff-so-fancy | less ..." (from a
# devcontainer feature) but never installs the binary itself, so every
# `git log`/`git diff` in an interactive terminal fails outright. Not an
# issue for non-TTY tool invocations (git auto-disables the pager there),
# which is why this went unnoticed for a while.
if ! command -v diff-so-fancy >/dev/null 2>&1; then
  npm install -g diff-so-fancy >/dev/null 2>&1
  echo "✓ diff-so-fancy installed (fixes the git pager)."
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

# ── Bitwarden Secrets Manager — fetch the "Credentials" project ────────────────
# Third-party API credentials (Unsplash, Font Awesome, Web Awesome) live in BWS
# instead of a committed or host-copied .env file. BWS_ACCESS_TOKEN itself must
# still come from the host (containerEnv) — bootstrapping secrets access from
# secrets access is circular — but everything downstream of it is fetched here.
if [ -n "${BWS_ACCESS_TOKEN:-}" ] && [ -n "${BITWARDEN_PROJECT_CREDENTIALS_ID:-}" ] && command -v bws >/dev/null 2>&1; then
  echo ""
  echo "Fetching secrets from Bitwarden (Credentials project)..."
  bws_env_file="$HOME/.bws-credentials.env"
  bws secret list "${BITWARDEN_PROJECT_CREDENTIALS_ID}" --output json \
    | jq -r '.[] | "export \(.key)=\(.value | @sh)"' > "${bws_env_file}"
  chmod 600 "${bws_env_file}"
  # shellcheck disable=SC1090
  source "${bws_env_file}"
  if ! grep -qF "${bws_env_file}" ~/.bashrc 2>/dev/null; then
    echo "[ -f ${bws_env_file} ] && source ${bws_env_file}" >> ~/.bashrc
  fi
  echo "✓ Bitwarden secrets loaded into $(basename "${bws_env_file}") ($(wc -l < "${bws_env_file}") vars)."
else
  echo "! Skipping Bitwarden secret fetch (BWS_ACCESS_TOKEN or BITWARDEN_PROJECT_CREDENTIALS_ID not set)."
fi

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
# Pinned to a specific release and verified against cargo-binstall's own
# minisign signature, instead of piping the unpinned `main`-branch install
# script into bash: that script has no integrity check of its own, so a
# compromised branch would execute arbitrary code on every container build.
# Bump CARGO_BINSTALL_VERSION deliberately when upgrading.
CARGO_BINSTALL_VERSION="1.21.1"
if ! command -v cargo-binstall >/dev/null 2>&1; then
  echo ""
  echo "Installing cargo-binstall v${CARGO_BINSTALL_VERSION} (minisign-verified)..."
  sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends minisign
  binstall_tmp="$(mktemp -d)"
  binstall_base_url="https://github.com/cargo-bins/cargo-binstall/releases/download/v${CARGO_BINSTALL_VERSION}"
  binstall_asset="cargo-binstall-x86_64-unknown-linux-gnu.tgz"
  curl -L --proto '=https' --tlsv1.2 -sSf -o "${binstall_tmp}/asset.tgz" \
    "${binstall_base_url}/${binstall_asset}"
  curl -L --proto '=https' --tlsv1.2 -sSf -o "${binstall_tmp}/asset.tgz.sig" \
    "${binstall_base_url}/${binstall_asset}.sig"
  curl -L --proto '=https' --tlsv1.2 -sSf -o "${binstall_tmp}/minisign.pub" \
    "${binstall_base_url}/minisign.pub"
  minisign -Vm "${binstall_tmp}/asset.tgz" -p "${binstall_tmp}/minisign.pub" \
    -x "${binstall_tmp}/asset.tgz.sig"
  tar -xzf "${binstall_tmp}/asset.tgz" -C "${binstall_tmp}"
  mkdir -p "${CARGO_HOME:-$HOME/.cargo}/bin"
  install -m 755 "${binstall_tmp}/cargo-binstall" "${CARGO_HOME:-$HOME/.cargo}/bin/cargo-binstall"
  rm -rf "${binstall_tmp}"
  echo "✓ cargo-binstall v${CARGO_BINSTALL_VERSION} installed and signature-verified."
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
