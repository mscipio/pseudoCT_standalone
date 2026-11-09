#!/bin/sh
# Run the shared compiled pipeline (pseudoct_pipeline) with the MATLAB Runtime recorded for it.
#   Installed distribution: this file is shipped as runtimes/<LABEL>/run_pseudoct_pipeline.sh
#   beside the compiled pseudoct_pipeline. Arguments:
#   <mcr_root> <job_manifest> [<resource_manifest>]. The resource manifest is
#   omitted in direct mode (the pipeline verifies the packaged resources itself). The Runtime
#   library path is set from mcr_root, and the pipeline runs from its own directory.
#   A source checkout has no pseudoct_pipeline beside this file and exits with a
#   development-only message; it never falls back to a legacy compiled tree.
set -eu

# Resolve symlinks of this script first, so the layout is detected at its real
# location. POSIX sh, bounded, set -u safe.
self=$0
case "$self" in
    */*) ;;
    *) self=$(command -v "$self") || { echo "Cannot locate the pipeline runner." >&2; exit 1; } ;;
esac
hops=0
while [ -h "$self" ]; do
    hops=$((hops + 1))
    if [ "$hops" -gt 40 ]; then
        echo "The pipeline runner symlink chain is too deep." >&2
        exit 1
    fi
    target=$(readlink "$self")
    case "$target" in
        /*) self=$target ;;
        *) self=$(dirname -- "$self")/$target ;;
    esac
done
script_dir=$(CDPATH= cd -- "$(dirname -- "$self")" && pwd -P)

if [ -x "$script_dir/pseudoct_pipeline" ]; then
    # Installed layout (runtimes/<LABEL>/): the compiled pipeline of the selected Runtime.
    if [ "$#" -ne 2 ] && [ "$#" -ne 3 ]; then
        echo "Usage: $0 <mcr_root> <job_manifest> [<resource_manifest>]" >&2
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
    exec "$script_dir/pseudoct_pipeline" "$@"
fi

# No installed pipeline beside this runner: a source checkout. It is development-only
# and never resolves a legacy compiled tree (compiled/current is obsolete).
echo "pseudoct: this source checkout is development-only; install the pseudoCT distribution to run the compiled pipeline." >&2
exit 1
