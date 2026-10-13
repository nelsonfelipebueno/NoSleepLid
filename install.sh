#!/bin/bash
# Builds NoSleepLid, installs it to ~/Applications and adds a sudoers rule that lets
# the current user run ONLY `pmset -a disablesleep 0|1` without a password.
set -euo pipefail
cd "$(dirname "$0")"
USER_NAME="$(id -un)"
RULE="/etc/sudoers.d/nosleeplid"
APP_DEST="$HOME/Applications/NoSleepLid.app"

./build.sh

pkill -x NoSleepLid 2>/dev/null && sleep 1 || true
mkdir -p "$HOME/Applications"
rm -rf "$APP_DEST"
cp -R build/NoSleepLid.app "$APP_DEST"
echo "installed: $APP_DEST"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<RULE_EOF
# NoSleepLid: lets $USER_NAME toggle "never sleep" without a password. Nothing else.
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
RULE_EOF
visudo -cf "$TMP" >/dev/null
echo "sudoers rule ($RULE) — your password is needed once:"
sudo install -m 0440 -o root -g wheel "$TMP" "$RULE"

open "$APP_DEST"
echo "done. Look for the moon icon in the menu bar."
