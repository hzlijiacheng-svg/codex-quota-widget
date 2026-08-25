#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$script_dir/.build"
app_dir="$build_dir/CodexQuotaWidget.app"
contents_dir="$app_dir/Contents"
arch_build_dir="$build_dir/arch"
executable_path="$contents_dir/MacOS/CodexQuotaWidget"
core_sources=("$script_dir"/Sources/QuotaCore/*.swift)
app_sources=("$script_dir"/Sources/CodexQuotaWidget/*.swift)

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$arch_build_dir"
cp "$script_dir/Info.plist" "$contents_dir/Info.plist"

if [[ "${CODEX_QUOTA_BUILD_UNIVERSAL:-0}" == "1" ]]; then
  /usr/bin/swiftc \
    -target x86_64-apple-macosx12.0 \
    -O \
    -framework AppKit -framework Security -framework CFNetwork \
    "${core_sources[@]}" "${app_sources[@]}" \
    -o "$arch_build_dir/CodexQuotaWidget-x86_64"

  /usr/bin/swiftc \
    -target arm64-apple-macosx12.0 \
    -O \
    -framework AppKit -framework Security -framework CFNetwork \
    "${core_sources[@]}" "${app_sources[@]}" \
    -o "$arch_build_dir/CodexQuotaWidget-arm64"

  /usr/bin/lipo -create \
    "$arch_build_dir/CodexQuotaWidget-x86_64" \
    "$arch_build_dir/CodexQuotaWidget-arm64" \
    -output "$executable_path"
else
  /usr/bin/swiftc \
    -O \
    -framework AppKit -framework Security -framework CFNetwork \
    "${core_sources[@]}" "${app_sources[@]}" \
    -o "$executable_path"
fi

touch "$app_dir"
/usr/bin/codesign --force --deep --sign - "$app_dir" >/dev/null
echo "$app_dir"
