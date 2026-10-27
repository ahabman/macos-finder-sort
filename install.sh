#!/bin/bash
# Build bin/finder-sort and add two global BetterTouchTool keyboard shortcuts:
#   Control-Option-Command-M  sort by Date Modified, newest first
#   Control-Option-Command-N  sort by Name, A to Z
# BTTPredefinedActionType 195 is "Run Apple Script (async in background)" in BTT 3.579;
# the script runs inside BTT, so BTT's Accessibility permission covers finder-sort.
# Run once. Running again adds duplicate triggers; delete the old ones in BTT first.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$here/bin"
swiftc -O "$here/Sources/finder-sort.swift" -o "$here/bin/finder-sort"

# Control (262144) + Option (524288) + Command (1048576)
modifiers=1835008

add_trigger() {  # $1 key code, $2 finder-sort mode, $3 name
  local json
  json=$(cat <<JSON
{
  "BTTTriggerType": 0,
  "BTTTriggerClass": "BTTTriggerTypeKeyboardShortcut",
  "BTTTriggerName": "$3",
  "BTTPredefinedActionType": 195,
  "BTTPredefinedActionName": "Run Apple Script (async in background)",
  "BTTInlineAppleScript": "do shell script \\"'$here/bin/finder-sort' $2\\"",
  "BTTShortcutKeyCode": $1,
  "BTTShortcutModifierKeys": $modifiers,
  "BTTEnabled": 1,
  "BTTEnabled2": 1
}
JSON
)
  osascript - "$json" <<'APPLESCRIPT'
on run argv
  tell application "BetterTouchTool" to add_new_trigger (item 1 of argv)
end run
APPLESCRIPT
}

add_trigger 46 modified "Finder sort: Date Modified (newest first)"  # M
add_trigger 45 name "Finder sort: Name (A to Z)"                     # N
# BTT 3.579 keeps triggers added over AppleScript in memory and writes them to its
# data store on quit; without this, the next BTT restart drops them.
osascript -e 'quit app "BetterTouchTool"'
while pgrep -qf 'MacOS/BetterTouchTool$'; do sleep 0.5; done
open -a BetterTouchTool

echo "Added BTT triggers. Grant BetterTouchTool Accessibility if not already granted."
