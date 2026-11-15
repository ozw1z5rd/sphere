#!/bin/sh
# Package a module folder into a single-file .spheremodule archive.
# Usage: scripts/package-module.sh <module-dir> [output.spheremodule]
set -eu

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <module-dir> [output.spheremodule]" >&2
    exit 1
fi

module_dir="$1"
module_name=$(basename "$module_dir")
output="${2:-${module_dir%/}.spheremodule}"

if [ ! -f "$module_dir/module.json" ]; then
    echo "error: $module_dir/module.json not found" >&2
    exit 1
fi

rm -f "$output"
ditto -c -k --keepParent "$module_dir" "$output"
echo "wrote $output"
