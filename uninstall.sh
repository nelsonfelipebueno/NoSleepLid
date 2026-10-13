#!/bin/bash
# Removes NoSleepLid, its sudoers rule and its logs, and makes sure sleep is back on.
set -uo pipefail
pkill -x NoSleepLid 2>/dev/null && sleep 1
rm -rf "$HOME/Applications/NoSleepLid.app"
rm -f "$HOME/Library/Logs/NoSleepLid.log" "$HOME/Library/Logs/NoSleepLid.log.1"
sudo pmset -a disablesleep 0
sudo rm -f /etc/sudoers.d/nosleeplid
echo "NoSleepLid removed. Sleep is enabled again."
