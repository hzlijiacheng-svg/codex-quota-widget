#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
built_app="$("$script_dir/build.command")"
applications_dir="$HOME/Applications"
installed_app="$applications_dir/CodexQuotaWidget.app"
launch_agents_dir="$HOME/Library/LaunchAgents"
agent_plist="$launch_agents_dir/local.codex.quota-widget.plist"
agent_template="$script_dir/LaunchAgent.plist.template"
user_id="$(id -u)"

mkdir -p "$applications_dir" "$launch_agents_dir"
/usr/bin/ditto "$built_app" "$installed_app"

executable_path="$installed_app/Contents/MacOS/CodexQuotaWidget"
escaped_path="$(printf '%s' "$executable_path" | /usr/bin/sed 's/[&|]/\\&/g')"
/usr/bin/sed "s|__EXECUTABLE_PATH__|$escaped_path|g" "$agent_template" > "$agent_plist.tmp"
/bin/mv "$agent_plist.tmp" "$agent_plist"

/bin/launchctl bootout "gui/$user_id" "$agent_plist" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$user_id" "$agent_plist"
/bin/launchctl kickstart -k "gui/$user_id/local.codex.quota-widget"

echo "已安装并启动：$installed_app"
echo "以后登录 macOS 时会自动显示。"

