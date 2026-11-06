# Focused tests

The retained automated checks are offline and do not run pseudoCT science,
submit Slurm jobs, or contact MLSC. Run them from the repository root with
MATLAB R2010b. Put temporary files, MATLAB preferences, and caches in scratch:

```sh
scratch="$PWD/.aria/scratch/unplanned/$(date +%Y%m%d-%H%M%S)-pseudoct-tests"
mkdir -p "$scratch/tmp" "$scratch/matlab-pref"
export TMPDIR="$scratch/tmp"
export MATLAB_PREFDIR="$scratch/matlab-pref"
export PSEUDOCT_TEST_SCRATCH="$scratch"

PYTHONDONTWRITEBYTECODE=1 python3 -B tests/test_dependency_lock.py
PYTHONDONTWRITEBYTECODE=1 python3 -B tests/test_pseudoct_stdout_filter.py
/usr/pubsw/bin/matlab7.11 -nodesktop -nosplash -r \
  "try, addpath('tests'); run_smoke_tests; exit(0); catch ME, disp(ME.message); exit(1); end"
```

The MATLAB runner covers four-profile/entrypoint and input/output policies,
missing-input rejection before dispatch on the CLI and headless paths with
Local/MLSC backend selection by profile,
installation dependency paths, the headless result contract, progress output,
semantic comparison capability, build preflight and package integrity (dry run
only; never calls mcc), and current MLSC submission/monitoring with
verified success, missing-output failure, scheduler failure, cancellation, and
transport rejection. Its MLSC fixtures use the installed artifact and tiny
synthetic outputs only. Python checks cover the dependency-lock integrity and
CLI JSONL stdout transport.

The `manual/` directory retains interactive and scientific comparison tools;
they are not automated checks and are not run by the commands above. In
particular, manual pseudoCT processing or live MLSC submission requires
separate authorization and suitable data.
