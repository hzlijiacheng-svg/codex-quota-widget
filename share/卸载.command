#!/bin/bash
set -euo pipefail

installed_app="$HOME/Applications/CodexQuotaWidget.app"
agent_plist="$HOME/Library/LaunchAgents/local.codex.quota-widget.plist"
trash_dir="$HOME/.Trash"
user_id="$(id -u)"
timestamp="$(date '+%Y%m%d-%H%M%S')"
original_touchbar_mode="$(defaults read local.codex.quota-widget TouchBarOriginalPresentationMode 2>/dev/null || true)"

/bin/launchctl bootout "gui/$user_id" "$agent_plist" 2>/dev/null || true
/usr/bin/pkill -x CodexQuotaWidget 2>/dev/null || true

mkdir -p "$trash_dir"
if [[ -e "$installed_app" ]]; then
  /bin/mv "$installed_app" "$trash_dir/CodexQuotaWidget-$timestamp.app"
fi
if [[ -e "$agent_plist" ]]; then
  /bin/mv "$agent_plist" "$trash_dir/local.codex.quota-widget-$timestamp.plist"
fi

if [[ -n "$original_touchbar_mode" ]]; then
  defaults write com.apple.touchbar.agent PresentationModeGlobal "$original_touchbar_mode"
  defaults delete local.codex.quota-widget TouchBarOriginalPresentationMode 2>/dev/null || true
  /usr/bin/killall ControlStrip 2>/dev/null || true
fi

echo "已卸载。应用和启动项已移到废纸篓，可在清空废纸篓前恢复。"
