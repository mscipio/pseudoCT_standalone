# Tasks: Entrypoint Divergence Diagnosis

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~290 |
| 400-line budget risk | Low |
| 800-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-always |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

## Phase 1: Config & Helper

- [x] 1.1 Add `keep_temp_files = 'No'` to `src/config/defaults_pseudo_CT.m` after L16
- [x] 1.2 Add `keep_temp_files = 'No'` to `src/config/defaults_pseudo_CT_launchpad.m` after L23
- [x] 1.3 Create `src/config/pseudo_CT_keep_temp_enabled.m` — env override (`PSEUDOCT_KEEP_TMP`) → defaults fallback → returns `'Yes'`/`'No'`

## Phase 2: Cleanup Gates

- [x] 2.1 In `run_pseudo_CT_local.m`: call `pseudo_CT_keep_temp_enabled(@defaults_pseudo_CT)`, skip L238-239 rmdir when `'Yes'`
- [x] 2.2 In `run_pseudo_CT_launchpad.m`: pass `'keep_tmp',1/0` to batch call, gate local rmdir when `'Yes'`
- [x] 2.3 In `src/launchpad/batch_pseudo_CT_launchpad.m`: add `keep_tmp=0` name-value default, gate cluster-side `rm -rf` when `1`

## Phase 3: Comparator Script

- [x] 3.1 Create `scripts/diff_entrypoint_runs.m` with `dir()` → sorted intersect → extension dispatch (`.nii` via spm_read_vols, `.dcm` via dicomread/binary, `.mat` via load/MD5, text via MD5, other via binary)
- [x] 3.2 Implement known-diff list (`Pseudo_CT_AC_Version.txt` → EXPECTED_DIFF, `Fusion_MR_Pseudo_CT_validation.tiff` → LOCAL_ONLY)
- [x] 3.3 Implement console table report + optional CSV output via `'OutputCSV'` name-value arg

## Phase 4: Tests & Verification

- [x] 4.1 Update `scripts/run_smoke_tests.m`: add parse check for `pseudo_CT_keep_temp_enabled.m` and `diff_entrypoint_runs.m`
- [x] 4.2 Manual: run `scripts/run_lint.m` — verify all modified/new files pass mlint (all 6 files PASS)
- [x] 4.1a Review remediation: DICOM comparator now uses dicominfo header + dicomread pixel comparison with explicit degraded-mode reporting
- [x] 4.1b Review remediation: compare_md5 sentinel check prevents READ_ERROR/MD5_UNAVAILABLE from ever being reported as IDENTICAL
- [x] 4.1c Review remediation: Added behavioral smoke tests for pseudo_CT_keep_temp_enabled env/defaults precedence (6 tests) and diff_entrypoint_runs text pipeline (6 tests). All 83 smoke tests pass, 0 fail.
- [x] 4.1d Review remediation: Launchpad keep-tmp now prints preserved cluster path + cleanup ssh command
- [x] 4.1e Review remediation: Renamed `button` variable to `should_cleanup` with explicit comment in both entry scripts
- [ ] 4.3 Manual: run both entrypoints on test data with `PSEUDOCT_KEEP_TMP=1` → verify `MR_PET/tmp/` survives
- [ ] 4.4 Manual: run `diff_entrypoint_runs` on preserved runs → verify IDENTICAL `MPRAGE_spm.nii`, DIVERGENT `MPRAGE_spm_normalized.nii`
- [ ] 4.5 Manual: run without env var → verify `MR_PET/tmp/` is cleaned as before

## Phase 5: Diagnostic Extension (Restart Checkpoint)

- [x] 5.1 Create `src/core/normalized_2_att_map.m` — diagnostic helper extracting lines 414-676 from `atlas_based_attenuation_map.m`
- [x] 5.2 Create `scripts/restart_from_repos_checkpoint.m` — controlled sandbox restart from Launchpad checkpoints
- [x] 5.3 Update `scripts/run_smoke_tests.m` — add parse checks for all `scripts/*.m`

## Phase 6: 4R Review Remediation

- [x] 6.1 Sandbox isolation: add `work_dir` param to `normalized_2_att_map`, copy `norm_mprage` into sandbox, operate only on copy, guardrail against same-dir work_dir
- [x] 6.2 Path ordering: move `setup_pseudo_CT_paths` before `pseudo_CT_resolve_batch_atlas_path` in `restart_from_repos_checkpoint.m`
- [x] 6.3 Atlas preflight: add explicit `Atlas_rCT.nii` and `Atlas_head_mask.nii` existence checks to `normalized_2_att_map`
- [x] 6.4 Sandbox collision resistance: sub-second timestamp + random suffix; print `rm -rf` cleanup command for preserved sandboxes
- [x] 6.5 Smoke test coverage: batch-atlas resolution validation test; `normalized_2_att_map` guardrail tests (3-arg, same-dir, Atlas preflight); `restart_from_repos_checkpoint` dry-run staging test with original-file non-mutation check. Smoke: 102 pass, 0 fail, 2 skip.
APEOF

## Phase 5: Diagnostic Extension (Restart Checkpoint)

- [x] 5.1 Create src/core/normalized_2_att_map.m — diagnostic helper
- [x] 5.2 Create scripts/restart_from_repos_checkpoint.m — controlled sandbox restart
- [x] 5.3 Update scripts/run_smoke_tests.m — add parse checks for all scripts/*.m

## Phase 6: 4R Review Remediation

- [x] 6.1 Sandbox isolation: add work_dir param to normalized_2_att_map, copy norm_mprage into sandbox, guardrail against same-dir work_dir
- [x] 6.2 Path ordering: move setup_pseudo_CT_paths before pseudo_CT_resolve_batch_atlas_path
- [x] 6.3 Atlas preflight: explicit Atlas_rCT.nii and Atlas_head_mask.nii existence checks
- [x] 6.4 Sandbox collision resistance: sub-second timestamp + random suffix; print rm -rf cleanup command for preserved sandboxes
- [x] 6.5 Smoke test coverage: guardrail + resolution + dry-run staging + non-mutation verification. Smoke: 102 pass, 0 fail, 2 skip.
