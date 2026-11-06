#!/usr/bin/env bash
# Install drive-sync for the current user:
#   - installs (or upgrades) rclone into ~/.local/bin if missing or older than 1.66,
#     verifying the download against the official SHA256SUMS
#   - links bin/drive-sync into ~/.local/bin
#   - copies default filters into ~/.config/drive-sync/ (never overwrites)
# No sudo needed.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/drive-sync"
MIN_RCLONE="1.66.0"

version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

need_rclone=1
if command -v rclone >/dev/null 2>&1; then
  have="$(rclone version | awk 'NR==1{sub(/^v/,"",$2); print $2}')"
  if version_ge "${have%%-*}" "$MIN_RCLONE"; then
    need_rclone=0
    echo "rclone $have already installed"
  fi
fi

if [ "$need_rclone" -eq 1 ]; then
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    armv7l) arch=arm-v7 ;;
    *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
  esac
  ver="$(curl -fsSL https://downloads.rclone.org/version.txt | awk '{print $2}')"   # e.g. v1.71.0
  [ -n "$ver" ] || { echo "could not read rclone version" >&2; exit 1; }
  zip="rclone-$ver-linux-$arch.zip"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "downloading rclone $ver ($arch)"
  curl -fsSL -o "$tmp/$zip"       "https://downloads.rclone.org/$ver/$zip"
  curl -fsSL -o "$tmp/SHA256SUMS" "https://downloads.rclone.org/$ver/SHA256SUMS"
  (cd "$tmp" && grep " $zip\$" SHA256SUMS | sha256sum -c -)
  unzip -q "$tmp/$zip" -d "$tmp/x"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$tmp/x/rclone-$ver-linux-$arch/rclone" "$BIN_DIR/rclone"
  echo "installed $("$BIN_DIR/rclone" version | head -1) to $BIN_DIR"
fi

mkdir -p "$BIN_DIR" "$CONF_DIR"
ln -sf "$REPO_DIR/bin/drive-sync" "$BIN_DIR/drive-sync"
[ -f "$CONF_DIR/default.filters" ] || cp "$REPO_DIR/share/default.filters" "$CONF_DIR/default.filters"
touch "$CONF_DIR/pairs.conf"
echo "drive-sync linked to $BIN_DIR/drive-sync"

if ! rclone listremotes 2>/dev/null | grep -q .; then
  cat <<'EOF'

Next: create your own Google OAuth client (rclone's shared client_id is
being retired in 2026): https://rclone.org/drive/#making-your-own-client-id
Then, in a normal terminal (sign-in opens a browser):
  rclone config create gdrive drive scope=drive client_id=YOUR_ID client_secret=YOUR_SECRET
Then add a pair, for example:
  drive-sync add role-deep-dives ~/role-deep-dives gdrive:role-deep-dives
  drive-sync install-timer 5min
EOF
fi
