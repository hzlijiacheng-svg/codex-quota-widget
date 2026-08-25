#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "$0")" && pwd)"
source_app="$package_dir/CodexQuotaWidget.app"
applications_dir="$HOME/Applications"
installed_app="$applications_dir/CodexQuotaWidget.app"
launch_agents_dir="$HOME/Library/LaunchAgents"
agent_plist="$launch_agents_dir/local.codex.quota-widget.plist"
user_id="$(id -u)"

if [[ ! -d "$source_app" ]]; then
  echo "安装包不完整：没有找到 CodexQuotaWidget.app"
  exit 1
fi

mkdir -p "$applications_dir" "$launch_agents_dir"
/usr/bin/ditto "$source_app" "$installed_app"

agent_tmp="$(mktemp "$launch_agents_dir/local.codex.quota-widget.XXXXXX.plist")"
/usr/bin/plutil -create xml1 "$agent_tmp"
/usr/bin/plutil -insert Label -string "local.codex.quota-widget" "$agent_tmp"
/usr/bin/plutil -insert ProgramArguments -json '["/usr/bin/open","-a","CodexQuotaWidget"]' "$agent_tmp"
/usr/bin/plutil -insert RunAtLoad -bool true "$agent_tmp"
/usr/bin/plutil -insert ProcessType -string "Interactive" "$agent_tmp"
/usr/bin/plutil -insert StandardOutPath -string "/tmp/local.codex.quota-widget.log" "$agent_tmp"
/usr/bin/plutil -insert StandardErrorPath -string "/tmp/local.codex.quota-widget.error.log" "$agent_tmp"
/bin/mv "$agent_tmp" "$agent_plist"

/bin/launchctl bootout "gui/$user_id" "$agent_plist" 2>/dev/null || true
/usr/bin/pkill -x CodexQuotaWidget 2>/dev/null || true
/bin/launchctl bootstrap "gui/$user_id" "$agent_plist"
/bin/launchctl kickstart -k "gui/$user_id/local.codex.quota-widget"

echo
echo "安装完成：顶部菜单栏会显示 Codex 周额度。"
echo "以后登录 macOS 时会自动启动。"
echo
echo "如果图标被其他菜单栏项目挤掉，请先切换到 Finder，再按住 Command 拖动额度图标到右侧。"

