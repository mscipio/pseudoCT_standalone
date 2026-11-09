# Focused tests

This page owns the offline checks. They do not run pseudoCT science, submit Slurm
jobs or contact MLSC. Run them from the repository root. Put temporary files,
MATLAB preferences and caches under scratch, not in HOME or global configuration.

## Setup

```sh
scratch="$PWD/.aria/scratch/unplanned/$(date +%Y%m%d-%H%M%S)-pseudoct-tests"
mkdir -p "$scratch/tmp" "$scratch/matlab-pref"
export TMPDIR="$scratch/tmp"
export MATLAB_PREFDIR="$scratch/matlab-pref"
export PSEUDOCT_TEST_SCRATCH="$scratch"
```

## Python checks

`python3 -I` ignores `PYTHON*` environment variables, so `-B` is the setting that
keeps bytecode out of the tree.

```sh
python3 -I -B tests/test_dependency_lock.py
python3 -I -B tests/test_pseudoct_stdout_filter.py
python3 -I -B tests/test_pseudoct_outcome.py
python3 -I -B -m unittest discover -s tests -p test_release_application.py -t tests
python3 -I -B -m unittest discover -s tests -p test_standalone_release.py -t tests
```

These cover the dependency-lock integrity, the CLI JSONL stdout transport, the
launcher outcome block (`test_pseudoct_outcome.py`), the release driver (catalog and
selection, the frontend allowlist against `frontend/`, `--verify` of a synthetic
package and the dry-run plan) and the single installed launcher `bin/pseudoct` (run,
headless, resolve, `--list-releases`, precedence and mismatch rejection; `gui` and
`run --orchestrate` refused) with fake compiled executables and fake MATLAB Runtime
evidence. They also include the installed worker runner (`run_pseudoct_worker.sh`), which needs
no MATLAB, mcc or jobs. Run the two release and launcher suites with `-p test_release_application.py`
and `-p test_standalone_release.py` as shown.

The unittest commands above and the equivalent pytest run execute the same tests, so
either can be used. Run pytest after the Setup exports, so its temporary files go under
scratch:

```sh
python3 -I -B -m pytest -p no:cacheprovider tests/test_release_application.py tests/test_standalone_release.py
```

Earlier, stale `frontend/__pycache__/*.pyc` files in the working tree made the release
inventory report extra frontend files. That gave 21 passed and 2 failed in the v3.2.0
audit's working tree, and 23 passed in a copy without `__pycache__/`. The inventory now
skips only Python bytecode (`*.pyc`/`*.pyo`, including those in `__pycache__/`), so the
working tree passes as it is and no clean copy is needed. Any other file under `frontend/`,
even one inside `__pycache__/`, still fails. The stale gitignored `frontend/__pycache__/*.pyc`
file is excluded by that bytecode skip; it was not deleted.

## MATLAB checks

Run the suite with MATLAB R2010b, using `-r`; newer `-batch` is not available there:

```sh
/usr/pubsw/bin/matlab7.11 -nodesktop -nosplash -r \
  "try, addpath('tests'); run_smoke_tests; exit(0); catch ME, disp(ME.message); exit(1); end"
```

The runner covers the four-profile and entrypoint policies; missing-input rejection
before dispatch on the CLI and headless paths, with Local or MLSC backend selection by
profile; installation dependency paths; the headless result contract; progress output;
semantic comparison capability; the build preflight and package integrity (dry run
only, never calls `mcc`); and current MLSC submission and monitoring, covering verified
success, missing-output failure, scheduler failure, cancellation and transport
rejection. Its MLSC fixtures use the installed artifact and tiny synthetic outputs only.

Run each suite below in a fresh R2010b session, from the repository root:
`test_profile_authority`, `test_frontend_launch` (launcher bridge, GUI state, shared
argument builder, UMAP discovery parity, optional real distribution check),
`test_mlsc_slurm_lifecycle`, `test_mlsc_installed_direct` (installed-direct generation
and staging with both manifests empty, plus the manifest-mode control),
`test_headless_result_validator`, `test_runtime_selection`, `test_build_application`,
`test_cli_progress_output`, `test_dependency_paths`, `test_exact_comparators`,
`test_lifecycle_arguments`, `test_setup_spm_dictionary` and `test_pseudoct_helper_names`
(resolution of the renamed internal helpers and the worker and launcher names).

### Source checkouts are development-only

A source checkout resolves no compiled artifact tree. The obsolete `compiled/current/`
tree is never used. An application validation or run from a checkout is refused with
`pseudo_CT:SourceCheckoutDevelopmentOnly` ("install the pseudoCT distribution"), unless
an explicit development artifact root is supplied for an MLSC profile. The suites
`test_runtime_selection` and `test_headless_result_validator` assert this refusal.
`test_mlsc_slurm_lifecycle` runs the MLSC lifecycle against a synthetic installed-direct
package built under the scratch directory, not against any source artifact.

`test_build_application` once failed with `pseudo_CT:BuildCompileInputMissing` for
`external/spm8-r6313/spm_bsplinc.mexa64` when an earlier test had left the SPM8 folder on
the MATLAB path. `scripts/build_application.m` checked its inputs with
`exist(..., 'file') ~= 2`, and MATLAB returns 3 for a MEX file once its folder is on the
path. That was a defect in the build preflight, not a rename regression. The MEX type 2/3
fix and its regression case cover it. The suite now passes alone, after
`test_headless_result_validator` in one session, and in the full runner.

## Manual tools

The `manual/` directory keeps interactive and scientific comparison tools. They are
not automated checks and are not run by the commands above. Manual pseudoCT
processing or live MLSC submission requires separate authorization and suitable data.
