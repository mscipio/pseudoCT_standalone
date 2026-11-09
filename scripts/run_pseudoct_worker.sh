#!/bin/sh
# Run the shared compiled worker (pseudoct_worker) with the MATLAB Runtime recorded for it.
#   Installed distribution: this file is shipped as runtimes/<LABEL>/run_pseudoct_worker.sh
#   beside the compiled pseudoct_worker. Arguments:
#   <mcr_root> <phase> <job_manifest> [<resource_manifest>]. The resource manifest is
#   omitted in direct mode (the worker verifies the packaged resources itself). The Runtime
#   library path is set from mcr_root, and the worker runs from its own directory.
#   A source checkout has no pseudoct_worker beside this file and exits with a
#   development-only message; it never falls back to a legacy compiled tree.
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

if [ -x "$script_dir/pseudoct_worker" ]; then
    # Installed layout (runtimes/<LABEL>/): the compiled worker of the selected Runtime.
    if [ "$#" -ne 3 ] && [ "$#" -ne 4 ]; then
        echo "Usage: $0 <mcr_root> <phase> <job_manifest> [<resource_manifest>]" >&2
        exit 2
    fi
    mcr_root=$1
    shift
    if [ ! -d "$mcr_root/runtime/glnxa64" ] || [ ! -d "$mcr_root/bin/glnxa64" ] || [ ! -d "$mcr_root/sys/os/glnxa64" ]; then
        echo "The MATLAB Runtime is incomplete or incompatible: $mcr_root" >&2
        exit 1
    fi
    ld_path=$mcr_root/runtime/glnxa64:$mcr_root/bin/glnxa64:$mcr_root/sys/os/glnxa64
    # MCR 7.14 libjvm.so lives under sys/java/.../amd64/server: add the Java directories
    # only when present (no -nojvm).
    for jre_dir in "$mcr_root/sys/java/jre/glnxa64/jre/lib/amd64" "$mcr_root/sys/java/jre/glnxa64/jre/lib/amd64/server"; do
        if [ -d "$jre_dir" ]; then ld_path=$ld_path:$jre_dir; fi
    done
    LD_LIBRARY_PATH=$ld_path
    export LD_LIBRARY_PATH
    exec "$script_dir/pseudoct_worker" "$@"
fi

# No installed worker beside this runner: a source checkout. It is development-only
# and never resolves a legacy compiled tree (compiled/current is obsolete).
echo "pseudoct: this source checkout is development-only; install the pseudoCT distribution to run the compiled worker." >&2
exit 1
