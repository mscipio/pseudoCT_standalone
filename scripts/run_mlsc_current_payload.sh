#!/bin/sh
# Run the MLSC current compiled payload with the MATLAB Runtime recorded for it.
#   Installed distribution: this file is shipped as runtimes/<LABEL>/payload/
#   run_mlsc_current_payload.sh beside the compiled mlsc_current_payload. Arguments:
#   <mcr_root> <phase> <job_manifest> <resource_manifest>; the Runtime library path is
#   set from mcr_root and the compiled payload runs from its own directory.
#   Repository layout (scripts/): compiled/current/payload_build and its legacy
#   build manifest, with the recorded MATLAB root and MCR release check.
set -eu

# Resolve symlinks of this script first, so the layout is detected at its real
# location. POSIX sh, bounded, set -u safe.
self=$0
case "$self" in
    */*) ;;
    *) self=$(command -v "$self") || { echo "Cannot locate the payload runner." >&2; exit 1; } ;;
esac
hops=0
while [ -h "$self" ]; do
    hops=$((hops + 1))
    if [ "$hops" -gt 40 ]; then
        echo "The payload runner symlink chain is too deep." >&2
        exit 1
    fi
    target=$(readlink "$self")
    case "$target" in
        /*) self=$target ;;
        *) self=$(dirname -- "$self")/$target ;;
    esac
done
script_dir=$(CDPATH= cd -- "$(dirname -- "$self")" && pwd -P)

if [ -x "$script_dir/mlsc_current_payload" ]; then
    # Installed payload directory: the compiled payload of the selected Runtime.
    if [ "$#" -ne 4 ]; then
        echo "Usage: $0 <mcr_root> <phase> <job_manifest> <resource_manifest>" >&2
        exit 2
    fi
    mcr_root=$1
    shift
    if [ ! -d "$mcr_root/runtime/glnxa64" ] || [ ! -d "$mcr_root/bin/glnxa64" ] || [ ! -d "$mcr_root/sys/os/glnxa64" ]; then
        echo "The MATLAB Runtime is incomplete or incompatible: $mcr_root" >&2
        exit 1
    fi
    LD_LIBRARY_PATH=$mcr_root/runtime/glnxa64:$mcr_root/bin/glnxa64:$mcr_root/sys/os/glnxa64
    export LD_LIBRARY_PATH
    exec "$script_dir/mlsc_current_payload" "$@"
fi

layout=repository
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
artifact="$repo_root/compiled/current/payload_build"
manifest="$repo_root/compiled/current/mlsc_current_build.txt"

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
    # The Runtime root is the one recorded for the artifact (checked above for
    # existence and layout); the deployed MCR release must be 7.14 (R2010b).
    if [ -z "$mcr_version" ] || [ "$mcr_version" != "7.14" ]; then
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
