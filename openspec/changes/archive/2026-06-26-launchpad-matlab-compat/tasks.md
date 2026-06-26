# Tasks: Launchpad MATLAB Compatibility

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~30–60 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | All 4 requirements (R1–R4) + verification | PR 1 | Single PR, ~30–60 lines total. Base = main. |

## Phase 1: Foundation

No infrastructure changes needed. This change touches 5 existing files with one-liner fixes, ~15–30 lines of diagnostics, and ~5 lines of doc updates. No new types, interfaces, or dependencies.

## Phase 2: Core Fixes

- [x] 2.1 `src/launchpad/run_launchpad_cmd_return.m:44` — replace `strsplit(jobnumline, '.')` with `regexp(jobnumline, '\.', 'split')`. Verifies spec scenarios A1 (R2010b parsing) and A2 (no-dot line).
- [x] 2.2 `src/io/nii2dcm_header_copy_vb20_david.m:82` — replace `for m=1:size(dicom_ref_all)` with `for m=1:numel(dicom_ref_all)`. Verifies scenarios B1 (multi-slice R2026a) and B2 (single-slice).

## Phase 3: Diagnostics

- [x] 3.1 `src/launchpad/batch_pseudo_CT_launchpad.m` — after line 89 `scp_get`, add `ls`-based check for `att_map.nii` in copied-back files. If absent, `scp_get` PBS `.o*`/`.e*` from `/pbs/<ssh_user>/` and `fprintf(1, ...)` their head lines to stdout. Wrap PBS fetch in try/catch so unreachable logs degrade silently. Verifies C1 (reachable PBS) and C2 (unreachable PBS).
- [x] 3.2 `run_pseudo_CT_launchpad.m:131` — in the `catch ME` block after `pseudo_CT_write_mu_map_dicom`, add `fprintf(1, ...)` printing `jobs(jj).temp_dir` contents and subject path before `disp(ME.message)`. Use `fprintf` to stdout (survives `warning('off','all')`). Verifies C1 richer diagnostics.

## Phase 4: Documentation

- [x] 4.1 `run_pseudo_CT_launchpad.m` header — add line `% Minimum supported MATLAB: R2010b (7.11)` with a note matching cluster MCR runtime. Verifies D1.
- [x] 4.2 `src/config/defaults_pseudo_CT_launchpad.m` help text — add `% Minimum supported MATLAB: R2010b` to function header comment. Verifies D2.

## Phase 5: Verification

- [x] 5.1 Lint — mlint skipped (MATLAB not on PATH; user will run `scripts/run_lint.m` on their MATLAB machine).
- [x] 5.2 Smoke tests — skipped (MATLAB not on PATH; user will run `scripts/run_smoke_tests.m` on their MATLAB machine).
- [x] 5.3 A/B reproducibility — deferred to user (requires R2013b + R2026a MATLAB machines + same subject data).
- [x] 5.4 Visual diff inspection — `git diff` confirms changes limited to the 5 target sites; no whitespace drift or unintended modifications.
