#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$("$script_dir/build.command")"

/usr/bin/open "$app_dir"

