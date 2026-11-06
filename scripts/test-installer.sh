#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
test_home="$(mktemp -d "${TMPDIR:-/tmp}/nvim-initmd-installer.XXXXXX")"
trap 'rm -rf -- "$test_home"' EXIT

HOME="$test_home/clean" "$root/setup-init-md.sh" >/dev/null
[[ -f "$test_home/clean/.config/nvim/init.lua" ]]
[[ -f "$test_home/clean/.config/nvim/init.md" ]]
cmp -s "$root/nvim-config-template.md" "$test_home/clean/.config/nvim/init.md"
mkdir -p "$test_home/clean/.cache/nvim/init-md-gen"
printf 'stale-cache\n' > "$test_home/clean/.cache/nvim/init-md-gen/manifest.txt"
HOME="$test_home/clean" "$root/setup-init-md.sh" >/dev/null
[[ ! -e "$test_home/clean/.cache/nvim/init-md-gen/manifest.txt" ]]

mkdir -p "$test_home/existing/.config/nvim"
printf '%s\n' 'user-owned init' > "$test_home/existing/.config/nvim/init.lua"
if HOME="$test_home/existing" "$root/setup-init-md.sh" >"$test_home/installer.log" 2>&1; then
    echo "installer unexpectedly replaced an existing init.lua" >&2
    exit 1
fi
grep -q 'user-owned init' "$test_home/existing/.config/nvim/init.lua"

echo "installer acceptance: passed"
