#!/bin/sh
# Copy the accepted compiled artifact into scratch without rebuilding or altering it.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
source="$repo_root/compiled"
output=${1:-"$repo_root/scratch/mlsc_current_package"}

case "$output" in
    "$repo_root"/scratch/*) ;;
    *) echo "Package output must be under $repo_root/scratch/: $output" >&2; exit 1 ;;
esac
if [ ! -x "$source/payload_build/mlsc_current_payload" ] || [ ! -x "$source/payload_build/run_mlsc_current_payload.sh" ] || [ ! -r "$source/mlsc_current_build.txt" ]; then
    echo "Current compiled artifact is missing or incomplete: $source" >&2
    exit 1
fi
if [ -e "$output" ]; then
    echo "Package output already exists; refusing to overwrite: $output" >&2
    exit 1
fi

mkdir -p "$(dirname -- "$output")"
mkdir "$output"
cp -R "$source/." "$output/"

# Compare every regular packaged file directly with its compiled source.
evidence="$output/../$(basename -- "$output").byte-identity.txt"
: > "$evidence"
find "$source" -type f -print | LC_ALL=C sort | while IFS= read -r source_file; do
    relative=${source_file#"$source"/}
    packaged_file="$output/$relative"
    if [ ! -f "$packaged_file" ] || ! cmp -s "$source_file" "$packaged_file"; then
        echo "Package differs from compiled artifact: $relative" >&2
        exit 1
    fi
    source_hash=$(sha256sum "$source_file" | awk '{print $1}')
    packaged_hash=$(sha256sum "$packaged_file" | awk '{print $1}')
    [ "$source_hash" = "$packaged_hash" ] || exit 1
    printf '%s  %s\n' "$source_hash" "$relative"
done > "$evidence"
echo "PACKAGE_BYTE_IDENTITY_PASS source=$source output=$output evidence=$evidence"
