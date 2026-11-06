#!/bin/sh
# Run the MLSC current compiled payload with the MATLAB Runtime recorded for it.
#   Packaged layout: this launcher is <package>/bin/run_mlsc_current_payload.sh
#   beside <package>/payload/ and <package>/application_manifest.txt. The MCR
#   root is read from that manifest; no release pin is applied.
#   Repository layout (scripts/): compiled/current/payload_build and its legacy
#   build manifest, with the recorded MATLAB root and MCR release check.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -r "$script_dir/../application_manifest.txt" ]; then
    layout=package
    package_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
    artifact="$package_root/payload"
    manifest="$package_root/application_manifest.txt"
else
    layout=repository
    repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
    artifact="$repo_root/compiled/current/payload_build"
    manifest="$repo_root/compiled/current/mlsc_current_build.txt"
fi

if [ ! -x "$artifact/mlsc_current_payload" ] || [ ! -x "$artifact/run_mlsc_current_payload.sh" ] || [ ! -r "$manifest" ]; then
    echo "Current compiled MLSC artifact is missing or incomplete: $artifact" >&2
    exit 1
fi

mcr_root=$(sed -n 's/^mcr_root //p' "$manifest")
if [ -z "$mcr_root" ] || [ ! -d "$mcr_root" ]; then
    echo "The Runtime required by the current artifact is missing or not recorded." >&2
    exit 1
fi

if [ "$layout" = repository ]; then
    mcr_version=$(sed -n 's/^mcr_version \[\([0-9][0-9]*\) \([0-9][0-9]*\)\]$/\1.\2/p' "$manifest")
    # MATLAB R2010b/compiler root and deployed MCR release are distinct.
    expected_root="/usr/pubsw/common/matlab/7.11"
    if [ -z "$mcr_version" ] || [ "$mcr_root" != "$expected_root" ] || [ "$mcr_version" != "7.14" ]; then
        echo "Recorded MATLAB root/MCR release does not match the supported contract: $mcr_root (MCR $mcr_version)" >&2
        exit 1
    fi
fi
if [ ! -d "$mcr_root/runtime/glnxa64" ] || [ ! -d "$mcr_root/bin/glnxa64" ] || [ ! -d "$mcr_root/sys/os/glnxa64" ]; then
    echo "The recorded MATLAB Runtime is incomplete or incompatible: $mcr_root" >&2
    exit 1
fi
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <phase> <job_manifest> <resource_manifest>" >&2
    exit 2
fi

exec "$artifact/run_mlsc_current_payload.sh" "$mcr_root" "$@"
