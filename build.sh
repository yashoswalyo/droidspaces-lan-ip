#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
module_id=$(sed -n 's/^id=//p' "$root/module.prop" | head -n 1)
version=$(sed -n 's/^version=//p' "$root/module.prop" | head -n 1)
case "$module_id" in
    ''|*[!a-zA-Z0-9._-]*) echo 'Invalid module id in module.prop' >&2; exit 1 ;;
esac
case "$version" in
    ''|*[!a-zA-Z0-9._-]*) echo 'Invalid version in module.prop' >&2; exit 1 ;;
esac
mkdir -p "$root/dist"
out=$root/dist/$module_id-$version.zip
tmp=$root/dist/.$module_id-$version.$$.zip
trap 'rm -f "$tmp"' EXIT HUP INT TERM
(
    cd "$root"
    zip -q -X -r "$tmp" module.prop boot-completed.sh uninstall.sh scripts webroot
)
mv -f "$tmp" "$out"
trap - EXIT HUP INT TERM
printf '%s\n' "$out"
