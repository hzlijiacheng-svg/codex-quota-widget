#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$script_dir/Info.plist")"
dist_dir="$script_dir/dist"
package_basename="Codex-Weekly-Quota-Menubar-v$version-macOS-universal"
source_basename="Codex-Weekly-Quota-Menubar-v$version-source"
staging_dir="$(mktemp -d /tmp/codex-quota-package.XXXXXX)"

cleanup() {
  case "$staging_dir" in
    /tmp/codex-quota-package.*) /bin/rm -rf -- "$staging_dir" ;;
  esac
}
trap cleanup EXIT

built_app="$(CODEX_QUOTA_BUILD_UNIVERSAL=1 "$script_dir/build.command")"
package_root="$staging_dir/$package_basename"
source_root="$staging_dir/$source_basename"

mkdir -p "$package_root" "$source_root" "$dist_dir"
/usr/bin/ditto "$built_app" "$package_root/CodexQuotaWidget.app"
cp "$script_dir/share/安装.command" "$package_root/安装.command"
cp "$script_dir/share/卸载.command" "$package_root/卸载.command"
cp "$script_dir/share/使用说明.txt" "$package_root/使用说明.txt"
cp "$script_dir/share/群内分享文案.txt" "$package_root/群内分享文案.txt"
chmod +x "$package_root/安装.command" "$package_root/卸载.command"

cp -R "$script_dir/Sources" "$source_root/Sources"
cp -R "$script_dir/Tests" "$source_root/Tests"
cp "$script_dir/test.command" "$source_root/test.command"
cp "$script_dir/Info.plist" "$source_root/Info.plist"
cp "$script_dir/LaunchAgent.plist.template" "$source_root/LaunchAgent.plist.template"
cp "$script_dir/build.command" "$source_root/build.command"
cp "$script_dir/run.command" "$source_root/run.command"
cp "$script_dir/install.command" "$source_root/install.command"
cp "$script_dir/package.command" "$source_root/package.command"
cp "$script_dir/README.md" "$source_root/README.md"
mkdir -p "$source_root/share"
cp "$script_dir/share/安装.command" "$source_root/share/安装.command"
cp "$script_dir/share/卸载.command" "$source_root/share/卸载.command"
cp "$script_dir/share/使用说明.txt" "$source_root/share/使用说明.txt"
cp "$script_dir/share/群内分享文案.txt" "$source_root/share/群内分享文案.txt"
chmod +x "$source_root"/*.command "$source_root/share"/*.command

package_zip="$dist_dir/$package_basename.zip"
source_zip="$dist_dir/$source_basename.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$package_root" "$package_zip.tmp"
/bin/mv -f "$package_zip.tmp" "$package_zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$source_root" "$source_zip.tmp"
/bin/mv -f "$source_zip.tmp" "$source_zip"

/usr/bin/shasum -a 256 "$package_zip" > "$package_zip.sha256"
/usr/bin/shasum -a 256 "$source_zip" > "$source_zip.sha256"

echo "$package_zip"
echo "$source_zip"
