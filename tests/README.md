# Tests and manual verification

Run automated checks from the repository root. They use local fixtures and do
not submit Slurm jobs or run pseudoCT processing:

```sh
python3 tests/test_dependency_lock.py
matlab -nosplash -nodesktop -r "addpath('tests'); test_dependency_paths; exit"
matlab -nosplash -nodesktop -r "addpath('tests'); test_headless_result_validator; exit"
matlab -nosplash -nodesktop -r "addpath('tests'); run_mlsc_tests; exit"
matlab -nosplash -nodesktop -r "addpath('tests'); run_smoke_tests; exit"
```

`tests/` contains automated MATLAB/Python tests and their aggregate runners.
Maintainer build, release, comparison, and validation utilities remain in
`scripts/`.

`manual/` contains interactive or scientific verification harnesses, not
automated tests. In particular, `manual/run_tests.m` invokes real pseudoCT
processing against configured data paths, and
`manual/pseudoct_manual_headless_test_v3.py` can authenticate and optionally
submit a live MLSC job when explicitly given `--run` and confirmed interactively.
Neither is part of the automated commands above; do not run them without a
separately authorized, safe dataset and live-operation approval.

The supported application entrypoints remain the root `run_pseudo_CT.m` MATLAB
function and `bin/pseudoct-headless` command-line launcher.
