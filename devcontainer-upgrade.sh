#!/usr/bin/env bash
# devcontainer-upgrade.sh — Refreshes .devcontainer/devcontainer-lock.json to the
# latest feature versions/digests allowed by devcontainer.json's version ranges
# (e.g. "...mistral-dev:1" stays pinned to major version 1 in devcontainer.json;
# only the lock's resolved version and sha256 digest move, e.g. 1.0.3 -> 1.0.4).
# Usage: ./devcontainer-upgrade.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

npx -y @devcontainers/cli upgrade --workspace-folder .
