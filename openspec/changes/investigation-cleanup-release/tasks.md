# Tasks: Investigation Cleanup Release

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~1295 (Commit 1: ~420, Commit 2: ~875) |
| 400-line budget risk | High (mitigated: size:exception approved for smoke-test) |
| Chained PRs recommended | No |
| Suggested split | Two-commit linear history (Commit 1 cleanup, Commit 2 docs+smoke) |
| Delivery strategy | exception-ok |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Cleanup + classification + gitignore | Commit 1 | Stage untracked keepers; delete transient artifacts; add `spm8-dan/` to `.gitignore`. Tree stays on disk. |
| 2 | Documentation + headers + CHANGELOG + smoke tests | Commit 2 | Add divergence warnings, tool banners, v2.6.2 entry. Smoke-test expansion (1038-line approved size:exception). CI must pass. |

## Phase 1: Cleanup & Classification (Commit 1)

- [x] 1.1 Stage all Keep-classified files: `TODO.md`, `scripts/` diagnostics, `src/config/` helpers, `src/core/` PCA/downstream pipeline — `git add` each as tracked. (Note: `scripts/run_tests.m` removed from staging per review-ledger R1-003 removal classification — file stays on disk.)
- [x] 1.2 Delete `package-lock.json` and `openspec/changes/extract-version-changelog/archive-report.md` — transient/accidental artifacts
- [x] 1.3 Add `spm8-dan/` entry to `.gitignore` — tree stays on disk, operator deletes manually later; never `rm -rf`
- [x] 1.4 Stage SDD artifacts: `openspec/specs/entrypoint-divergence-diagnostics/spec.md` and full `openspec/changes/investigation-cleanup-release/` directory
- [x] 1.5 Verify: `spm8-dan/` appears in `git ls-files --others --ignored`; `package-lock.json` and archive-report.md are gone; no Keep files are deleted

## Phase 2: Documentation & Headers (Commit 2)

- [x] 2.1 Edit `run_pseudo_CT_launchpad.m` header — add "Minimum supported MATLAB: R2010b (7.11)" and divergence warning: "Modern MATLAB (R2013b+) MAY produce divergent optimizer results"
- [x] 2.2 Edit `defaults_pseudo_CT_launchpad.m` — add divergence caveat to the minimum-version documentation line
- [x] 2.3 Add investigation-tool banner (`% Investigation tool — investigation-cleanup-release.`) to all 7 diagnostic scripts and `src/core/` files per design table
- [x] 2.4 Write CHANGELOG v2.6.2 entry: coregistration finding (qualitative, no deltas), divergence caveat, deferred-validation warning, cleanup exclusions, `spm8-dan/` gitignore note, diagnostic tools list
- [x] 2.5 Manual review: CHANGELOG wording matches spec scenarios — no max-affine-delta values, no R2026a parity claim

## Phase 3: Smoke-Test Expansion (Commit 2, size:exception)

- [x] 3.1 Expand `scripts/run_smoke_tests.m` — add CHANGELOG structural checks, divergence-warning assertions, classification verification assertions (1038-line diff, approved size:exception)
- [x] 3.2 Run `scripts/run_lint.m` — verify no new mlint violations in `src/`, `vers/`, entry scripts, `scripts/`
- [x] 3.3 Run `scripts/run_smoke_tests.m` — CI gate must pass cleanly before landing. **206 passed, 0 failed, 3 skipped** (Batch 2 remediation fixed all 3 pre-existing section 14 failures; CI continue-on-error removed).

## Phase 4: Verification & Release Readiness

- [x] 4.1 Run full lint + smoke suite: `run('scripts/run_lint.m')` then `run('scripts/run_smoke_tests.m')`
- [x] 4.2 Confirm `spm8-dan/` present on disk but gitignored: `git ls-files --others --ignored spm8-dan/`
- [x] 4.3 Confirm no tracked file removal beyond `package-lock.json` and `archive-report.md`
- [ ] 4.4 Operator confirms R2026a E2E validation deferral before release tagging (open question from design)

## Phase 5: Full Investigation Remediation (Batch 3)

- [x] 5.1 **R1-001 full fix**: Add shell metacharacter validation for `source_command` and `cmd` in `run_normalization_cmd.m` (previously only `fs_lib` was validated). All 3 interpolated inputs now pass through `shell_meta` regex guard before shell command construction.
- [x] 5.2 **R1-002 full fix**: Add shell metacharacter validation for `fns_seg_batch` in `normalized_2_att_map.m` (previously only `run_spm8_sh` and `mcr_root` were validated). All 3 interpolated inputs now pass through `shell_meta` regex guard before `system()` call.
- [x] 5.3 **R1-004/R2-006 evidence**: Captured verifiable execution evidence — `240 passed, 0 failed, 3 skipped` with full command output recorded in apply-progress.
- [x] 5.4 **R3-002 behavioral**: Added runtime `defaults_pseudo_CT('recenter_before_normalization')` behavioral test (section 20a) going beyond source-text assertion.
- [x] 5.5 **R3-003 structural**: Added FreeSurfer command construction pattern tests (section 20b-20c) verifying tcsh/sh env-setup paths and all-3-input validation.
- [x] 5.6 **R3-004 behavioral**: Added PCA geometry behavioral tests (section 21) with controlled inputs: tall, wide, square, single-observation, empty matrices. 16 tests total.
- [x] 5.7 **R3-005 full fix**: (a) Sign-convention fix: `score(:,1:d)` instead of `score` (`bsxfun` dimension mismatch for wide matrices). (b) Coeff contract fix: full SVD instead of econ for wide matrices to return P×P coeff with correct zero-padded latent(n:p). Verified via smoke tests 21a-21e.
- [x] 5.8 **R3-006 coverage**: Existing section 7a behavioral tests (6 tests for `pseudo_CT_keep_temp_enabled` env/defaults precedence). Full E2E requires operator pipeline run.
- [x] 5.9 **R4-002 preparation**: Added section 22 (7 tests): no parity claims in 3 source files, output path contracts verified, deferred-validation warning documented.
- [x] 5.10 Lint + smoke verification: 777 pre-existing mlint issues, 0 new. **240 passed, 0 failed, 3 skipped** (3 pre-existing Batch_atlas skips).

### Files Changed (Batch 3)

| File | Action | Findings |
|------|--------|----------|
| `src/remote/run_normalization_cmd.m` | Modified | R1-001 full: validate all 3 shell inputs |
| `src/core/normalized_2_att_map.m` | Modified | R1-002 full: validate fns_seg_batch |
| `src/core/pseudo_ct_princomp_legacy.m` | Modified | R3-005: sign-convention + coeff contract fixes |
| `scripts/run_smoke_tests.m` | Modified | Sections 19-22: 34 new tests (shell-safe, recenter behavioral, PCA geometry, R2026a prep) |
