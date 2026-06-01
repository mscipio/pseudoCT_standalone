# Tasks: Pipeline Quality Fixes

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~100 (30 add + 70 modify) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR (all 3 fixes in one pass) |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | All 3 fixes (A+B+C) in one PR | PR 1 | ~100 lines, well under 400-line budget |

## Phase 1: Fix A — Path Setup Extraction

- [x] 1.1 Create `src/config/setup_pseudo_CT_paths.m` — extract `addpath`+`genpath`+`clear`+`rehash` logic from entry scripts. Signature: `function setup_pseudo_CT_paths(root_dir)`. Handle `src/`, `spm8-r6313/`, `imgaussian/`, `ssh2_v2_m1_r5/`, `vers/`.
- [x] 1.2 Modify `run_pseudo_CT_local.m` — replace L64-82 with 3-line bootstrap: `[pathp,~,~]=fileparts(mfilename('fullpath')); addpath(fullfile(pathp,'src','config'),'-begin'); setup_pseudo_CT_paths(pathp);`. Remove now-unused `dir_batch_templates` computation comment (L84-88) — keep the `fullfile(pathp, 'Batch_atlas')` logic inline.
- [x] 1.3 Modify `run_pseudo_CT_launchpad.m` — replace L66-84 with same 3-line bootstrap pattern.

## Phase 2: Fix B — Operator Modernization

- [x] 2.1 Modify `run_pseudo_CT_local.m` — L149: `isstr`→`ischar`, `|`→`||` (3 operands).
- [x] 2.2 Modify `run_pseudo_CT_launchpad.m` — L213: `isstr`→`ischar`, `|`→`||` (3 operands).
- [x] 2.3 Modify `src/core/atlas_based_attenuation_map.m` — L105: `|`→`||`. L149: `isstr`→`ischar`. L173: `|`→`||`.
- [x] 2.4 Modify `src/core/move_image_2_MNI.m` — L15: `isstr`→`ischar`.
- [x] 2.5 Modify `src/io/convert_dicom_i_2_nii.m` — L11: `isstr`→`ischar`, `|`→`||`. L12, L86, L107, L112: `&`→`&&`. L37, L61: `|`→`||`. L63c (commented): `isstr`→`ischar`, `|`→`||`.

## Phase 3: Fix C — mkdir/rmdir Guard Cleanup

- [x] 3.1 Modify `run_pseudo_CT_local.m` — L197: `mkdir_success == 0`→`~mkdir_success`. L259: `remove_success == 0`→`~remove_success`.
- [x] 3.2 Modify `run_pseudo_CT_launchpad.m` — L104: `success == 0`→`~success`. L158: `remove_success == 0`→`~remove_success`.
- [x] 3.3 Modify `src/io/convert_dicom_i_2_nii.m` — L16, L88, L114: `success == 0`→`~success`.

## Phase 4: Verification

- [ ] 4.1 Run `mlint` on all 5 modified files + new file — verify zero warnings for deprecated `isstr` or element-wise `|`/`&` in scalar context.
- [ ] 4.2 Run `run_pseudo_CT_local('batch')` with a test MPRAGE — verify no `undefined function` errors from path setup.
- [ ] 4.3 `git diff` to confirm ONLY targeted patterns changed — no whitespace, no logic, no drift.
