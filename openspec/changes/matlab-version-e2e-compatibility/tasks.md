# Tasks: MATLAB Version E2E Compatibility

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~300 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

## Phase 1: Mapping & Validation Foundation

- [ ] 1.1 RED: verify 32 RELEASE_TO_VERSION entries present; verify R2023b+ year-based (≥23.x)
- [ ] 1.2 Add 32-entry `RELEASE_TO_VERSION` associative array and `SWEEP_VERSIONS` default in `scripts/run_matlab_version_e2e.sh`
- [ ] 1.3 RED: nonexistent `INPUT_DATA_DIR` → exit 1 with message; write above `OUT_ROOT` → rejected
- [ ] 1.4 Add `INPUT_DATA_DIR` validation (must exist, must contain `MR/MEMPRAGE/` and `MR/UMAP/`); `OUT_ROOT` creation guard (reject non-empty without `--force`)
- [ ] 1.5 RED: missing `/usr/pubsw/bin/matlab*` binary → SKIP with logged path; non-allowlist version → SKIP, never substitute
- [ ] 1.6 Add binary discovery via `[ -x /usr/pubsw/bin/matlab${ver} ]` + skip logic
- [ ] 1.7 Add `.e2e_state` JSON-lines state file: init, read, per-run write (VERSION MODE STATUS TIMESTAMP [reason])

## Phase 2: Core Runner — Sweep Loop

- [ ] 2.1 RED: `cp -a` copy integrity via `diff -rq` on source vs copied tree; both PCA modes produce `matlab_<V>_<M>` tagged trees
- [ ] 2.2 Add safe per-version×mode input copy: `cp -a $INPUT_DATA_DIR` → `OUT_ROOT/matlab_<V>_<M>/data/`; `rm -rf` only inside versioned subdir
- [ ] 2.3 Add per-run MATLAB: `PSEUDOCT_KEEP_TMP=1`, `PSEUDOCT_USE_PRINCOMP=0|1`, `PSEUDOCT_FS_LIBSTDCPP_ROOT`; invoke via `matlab${ver} -nosplash -nodisplay -r "run_pseudo_CT_local(...)"`
- [ ] 2.4 RED: MATLAB crash on one version → script continues; `--resume` skips DONE runs, only executes incomplete
- [ ] 2.5 Add per-run log to `OUT_ROOT/log/matlab_<V>_<M>.log`, capture exit code, update state (DONE|FAILED|SKIP), never abort sweep loop
- [ ] 2.6 Add `--resume` (skip DONE state lines) and `--force` (clear state, re-run all) flags
- [ ] 2.7 Add post-sweep invocation of `run_matlab_version_e2e_report.m` with state-only run discovery; write sweep summary to stdout and `OUT_ROOT/sweep_summary.txt`

## Phase 3: Report Aggregator

- [ ] 3.1 RED: byte-identical NIfTI at tol 1e-6 → IDENTICAL; divergent voxels → VOXEL_DIVERGENT with max_abs_diff; QC TIFF → LOCAL_ONLY without coverage failure; version text → EXPECTED_DIFF not DIVERGENT
- [ ] 3.2 Create `scripts/run_matlab_version_e2e_report.m`: walk `OUT_ROOT/matlab_*/MR_PET/tmp/`, skip non-DONE state lines, handle mixed DONE/SKIP/FAILED
- [ ] 3.3 Wire `diff_entrypoint_runs(out_root/matlab_<V>_<M>/MR_PET/tmp, launchpad_ref)` per V×M; classify every artifact as IDENTICAL/VOXEL_DIVERGENT/HEADER_ONLY/SKIP/EXPECTED_DIFF/LOCAL_ONLY/LAUNCHPAD_ONLY/UNCOMPARABLE
- [ ] 3.4 Emit `compatibility.md`: 2 PCA-mode tables × 15 pipeline-stage rows (pipeline order) × 5 MATLAB-version columns; per cell: status, max_abs_diff, mismatch count

## Phase 4: Procedure Document

- [ ] 4.1 Create `docs/matlab-version-compat-E2E.md`: prerequisites, input-data layout contract, env-var matrix (PCA, keep-tmp, FS libstdc++), per-version invocation, output tree layout, the three difference classes, report format, rollback instructions

## Phase 5: Manual E2E Verification

- [ ] 5.1 [Manual] Full sweep on test subject: verify `compatibility.md` has 2 tables × ≥15 stage rows × 5 version columns, all cells filled; `git diff --name-only` shows ONLY `scripts/` and `docs/` additions, no `src/`, `CHANGELOG.md`, `.github/` modifications
- [ ] 5.2 [Manual] Interrupt mid-sweep (Ctrl-C), re-run `--resume`: only incomplete runs execute, DONE runs skip
- [ ] 5.3 [Manual] Failure isolation: crash MATLAB on one version (e.g. set invalid env); confirm other versions complete, sweep not aborted
- [ ] 5.4 [Manual] Missing-binary SKIP: set `SWEEP_VERSIONS` to include version not on disk; confirm logged SKIP with binary path, no abort
