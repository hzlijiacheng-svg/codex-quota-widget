#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
test_binary="$script_dir/.build/QuotaCoreTests"

mkdir -p "$script_dir/.build"
/usr/bin/swiftc \
  "$script_dir"/Sources/QuotaCore/*.swift \
  "$script_dir/Tests/main.swift" \
  -o "$test_binary"
"$test_binary"
