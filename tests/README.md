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
PYTHONDONTWRITEBYTECODE=1 python3 -I -B -m unittest discover -s tests -p test_release_application.py -t tests
PYTHONDONTWRITEBYTECODE=1 python3 -I -B -m unittest discover -s tests -p test_standalone_release.py -t tests
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
synthetic outputs only. Python checks cover the dependency-lock integrity, the
CLI JSONL stdout transport, the release driver (catalog and selection, the frontend
allowlist against `frontend/`, `--verify` of a synthetic package, the dry-run plan), the
launcher outcome block (`test_pseudoct_outcome.py`), and the single installed launcher
`bin/pseudoct` (run, headless, resolve, --list-releases, precedence and mismatch
rejection; `gui` and `run --orchestrate` refused) with fake compiled executables and
fake MATLAB Runtime evidence, plus the installed payload runner (no MATLAB, mcc or jobs).
Run the two release/launcher suites with `-p test_release_application.py` and
`-p test_standalone_release.py` as shown above.

MATLAB suites (run each in a fresh R2010b session, `test_profile_authority` from
the repository root): `test_profile_authority`, `test_frontend_launch` (launcher
bridge, GUI state, shared argument builder, UMAP discovery parity, optional real
distribution check), `test_mlsc_slurm_lifecycle`, `test_headless_result_validator`,
`test_runtime_selection`, `test_build_application`, `test_cli_progress_output` and
`test_dependency_paths`.

The `manual/` directory retains interactive and scientific comparison tools;
they are not automated checks and are not run by the commands above. In
particular, manual pseudoCT processing or live MLSC submission requires
separate authorization and suitable data.
