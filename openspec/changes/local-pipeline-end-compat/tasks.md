# Tasks: Local Pipeline End-of-Run QC Compatibility Fix

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~6 (5 removals, 1 addition) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: Low

## Phase 1: Core Implementation

- [x] 1.1 In `src/core/atlas_based_attenuation_map.m`, replace lines 661–669 (`if ~isdeployed`…`else`…`end` block) with `imwrite(composite, fullfile(paths, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'Resolution', 300);`

## Phase 2: Automated Verification

- [ ] 2.1 Run `run('scripts/run_lint.m')` — confirm no new mlint warnings on `atlas_based_attenuation_map.m`
- [ ] 2.2 Run `run('scripts/run_smoke_tests.m')` — confirm file parses and all smoke checks pass

## Phase 3: Manual E2E Verification

- [ ] 3.1 Run on MATLAB R2026a: `run_pseudo_CT_local('batch')` with one real subject; confirm `Fusion_MR_Pseudo_CT_validation.tiff` is produced with no `InteractionsManager` error
- [ ] 3.2 Run on cluster R2010b-class runtime: confirm pipeline completes and QC TIFF is visibly correct
- [ ] 3.3 Visually compare QC TIFF against a known-good run from the prior graphics-based path — confirm pixel-content equivalence
