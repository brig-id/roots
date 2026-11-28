#!/usr/bin/env bash
# Keeps the shared Cargo target directory (the `brigid-cargo-target` volume) from
# growing without end.
#
# Every repository and every git worktree builds into it. A worktree at a new
# path compiles the project's own crates again under a new name, and nothing
# ever removes the previous ones: three weeks of work left 123 GB there.
#
# What it removes is only ever a cache: Cargo builds again what is missing.
#
#   1. what a build has not read for DAYS days (default 7): each unit of a
#      profile (`debug/build/<package>/<hash>`), each file of the older layout
#      (`deps`, `.fingerprint`, `incremental`), each executable left in a
#      profile, and the side directories a session made for itself
#      (`CARGO_TARGET_DIR=/cargo-target/<name>`), whole;
#   2. everything, if the directory is still above MAX_GB (default 40).
#
# It does nothing while a build is running, unless --force.
#
#   clean-cargo-target.sh [--days N] [--max-gb N] [--dry-run] [--force]
#
# Run at each start of the container (devcontainer.json, postStartCommand)
# and by hand at any time.
set -euo pipefail

TARGET="${CARGO_TARGET_DIR:-/cargo-target}"
DAYS=7
MAX_GB=40
DRY_RUN=false
FORCE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --max-gb) MAX_GB="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    -h | --help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$DAYS$MAX_GB" in
  *[!0-9]* | "") echo "--days and --max-gb take whole numbers" >&2; exit 2 ;;
esac

# Never anything but a directory of its own: not /, not a home, not a checkout.
case "$TARGET" in
  "" | / | /home | /home/* | /root | /workspaces | /workspaces/*)
    echo "refusing to clean $TARGET" >&2; exit 2 ;;
esac
[ -d "$TARGET" ] || { echo "$TARGET does not exist: nothing to clean"; exit 0; }

if ! $FORCE && pgrep -x cargo >/dev/null 2>&1; then
  echo "a build is running: $TARGET left as it is (--force to clean anyway)"
  exit 0
fi

size_kb() { du -sk "$TARGET" 2>/dev/null | cut -f1; }
human() { awk -v kb="$1" 'BEGIN { printf "%.1f GB", kb / 1048576 }'; }

# Whether a file under "$1" was read or written in the last DAYS days. Files
# only: listing a directory, as this script does, changes its access time.
used_lately() {
  [ -n "$(find "$1" -type f \( -atime "-$DAYS" -o -mtime "-$DAYS" \) -print -quit 2>/dev/null)" ]
}

remove() {
  if $DRY_RUN; then
    echo "would remove $1"
  else
    rm -rf -- "$1"
  fi
}

# A profile directory: debug, release, or a custom profile; of the host or of
# a target (`x86_64-unknown-linux-musl/release`).
clean_profile() {
  local profile="$1" unit package file
  if [ -d "$profile/build" ]; then
    for package in "$profile"/build/*/; do
      [ -d "$package" ] || continue
      if ! used_lately "$package"; then
        remove "${package%/}"
        continue
      fi
      for unit in "$package"*/; do
        [ -d "$unit" ] || continue
        used_lately "$unit" || remove "${unit%/}"
      done
    done
  fi
  # The layout before `build/<package>/<hash>`: one file per artefact.
  for old in deps .fingerprint incremental examples; do
    [ -d "$profile/$old" ] || continue
    if ! used_lately "$profile/$old"; then
      remove "$profile/$old"
    elif ! $DRY_RUN; then
      find "$profile/$old" -mindepth 1 -type f -atime "+$DAYS" -mtime "+$DAYS" \
        -delete 2>/dev/null || true
    fi
  done
  # Executables and libraries left at the top of the profile.
  while IFS= read -r file; do
    remove "$file"
  done < <(find "$profile" -mindepth 1 -maxdepth 1 -type f ! -name '.cargo-*' \
    -atime "+$DAYS" -mtime "+$DAYS" 2>/dev/null)
}

is_profile() { [ -d "$1/build" ] || [ -d "$1/deps" ] || [ -d "$1/.fingerprint" ]; }

before="$(size_kb)"

for entry in "$TARGET"/*/; do
  [ -d "$entry" ] || continue
  entry="${entry%/}"
  if is_profile "$entry"; then
    clean_profile "$entry"
    continue
  fi
  # A target triple holds profiles; anything else is a side directory.
  profiles=false
  for sub in "$entry"/*/; do
    [ -d "$sub" ] || continue
    if is_profile "${sub%/}"; then
      profiles=true
      clean_profile "${sub%/}"
    fi
  done
  if ! $profiles || ! used_lately "$entry"; then
    used_lately "$entry" || remove "$entry"
  fi
done

after="$(size_kb)"
if ! $DRY_RUN && [ "$after" -gt $((MAX_GB * 1048576)) ]; then
  echo "$TARGET is still $(human "$after"), above ${MAX_GB} GB: emptied, the next build starts over"
  find "$TARGET" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  after="$(size_kb)"
fi

if $DRY_RUN; then
  echo "$TARGET: $(human "$before") (dry run, nothing removed)"
else
  echo "$TARGET: $(human "$before") → $(human "$after")"
fi
