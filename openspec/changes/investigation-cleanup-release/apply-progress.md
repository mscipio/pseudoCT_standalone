# Apply Progress: Investigation Cleanup Release

**Date:** 2026-07-13 (Batch 1 + Batch 2 + Batch 3 Full Investigation)
**Artifact store:** both (openspec + Engram)
**Delivery strategy:** exception-ok
**Workload decision:** size:exception approved for smoke-test expansion

## Implementation Summary

All code-level tasks complete. **240 passed, 0 failed, 3 skipped** (3 pre-existing Batch_atlas skips). 10 of 10 review-ledger BLOCKER/CRITICAL findings resolved. Only task 4.4 (operator R2026a E2E confirmation) remains as a no-tag gate.

### Completed Tasks

| Phase | Task | Status |
|-------|------|--------|
| 1 | 1.1 Stage Keep files | [x] 10 files git-added (run_tests.m removed from staging per R1-003) |
| 1 | 1.2 Delete transient artifacts | [x] package-lock.json + archive-report.md removed |
| 1 | 1.3 Add spm8-dan/ to .gitignore | [x] tree stays on disk |
| 1 | 1.4 Stage SDD artifacts | [x] entrypoint-divergence-diagnosis + investigation-cleanup-release |
| 1 | 1.5 Verify cleanup | [x] all assertions pass; run_tests.m now untracked (on disk, not staged) |
| 2 | 2.1 run_pseudo_CT_launchpad.m header | [x] R2010b min version + divergence warning |
| 2 | 2.2 defaults_pseudo_CT_launchpad.m | [x] divergence caveat added |
| 2 | 2.3 Investigation-tool banners | [x] 7 files: 5 scripts + 2 src/core |
| 2 | 2.4 CHANGELOG v2.6.2 entry | [x] 6 boundary items per design |
| 2 | 2.5 Manual CHANGELOG review | [x] all spec scenarios verified |
| 3 | 3.1 Smoke-test expansion | [x] sections 16-22 (90 tests total) |
| 3 | 3.2 Run lint | [x] 44 files, 777 pre-existing issues, 0 new |
| 3 | 3.3 Run smoke tests | [x] **240 passed, 0 failed, 3 skipped** |
| 4 | 4.1 Full lint + smoke suite | [x] run and results recorded |
| 4 | 4.2 spm8-dan/ gitignored + on disk | [x] confirmed |
| 4 | 4.3 No tracked file removal beyond spec | [x] confirmed |
| 4 | 4.4 Operator E2E deferral | [ ] open question — operator action required |
| 5 | 5.1 R1-001 full fix | [x] All 3 shell inputs validated |
| 5 | 5.2 R1-002 full fix | [x] fns_seg_batch validated |
| 5 | 5.3 R1-004/R2-006 evidence | [x] Verifiable command output captured |
| 5 | 5.4 R3-002 behavioral | [x] Runtime defaults evaluation |
| 5 | 5.5 R3-003 structural | [x] FS cmd construction patterns |
| 5 | 5.6 R3-004 behavioral | [x] PCA geometry with controlled inputs |
| 5 | 5.7 R3-005 full fix | [x] Sign convention + coeff contract |
| 5 | 5.8 R3-006 coverage | [x] Behavioral + structural (E2E deferred) |
| 5 | 5.9 R4-002 preparation | [x] Output acceptance assertions |
| 5 | 5.10 Verification | [x] 240/0/3 |

## Review Ledger Remediation (All Batches)

### Batch 2 (Scoped Remediation)

| Finding | Severity | Fix | File(s) |
|---------|----------|-----|---------|
| R1-001 | BLOCKER | Shell metacharacter validation for PSEUDOCT_FS_LIBSTDCPP_ROOT | run_normalization_cmd.m |
| R1-002 | BLOCKER | Shell metacharacter validation for run_spm8_sh, mcr_root | normalized_2_att_map.m |
| R1-003 | CRITICAL | run_tests.m un-staged (git rm --cached) | scripts/run_tests.m, run_smoke_tests.m |
| R3-001 | BLOCKER | Removed continue-on-error from CI | .github/workflows/ci.yml |
| R3-002 | BLOCKER | Reverted recenter default to 'Yes' | defaults_pseudo_CT.m, run_smoke_tests.m |
| R3-005 | CRITICAL | U(:,1:n-1) instead of full U | pseudo_ct_princomp_legacy.m |
| R4-001 | BLOCKER | Fixed section 14 smoke failures + CI hard-gate | run_smoke_tests.m, ci.yml |

### Batch 3 (Full Investigation)

| Finding | Severity | Fix | File(s) |
|---------|----------|-----|---------|
| R1-001 | BLOCKER | Full: validate source_command AND cmd in addition to fs_lib | run_normalization_cmd.m |
| R1-002 | BLOCKER | Full: validate fns_seg_batch in addition to run_spm8_sh, mcr_root | normalized_2_att_map.m |
| R1-004 | BLOCKER | Verifiable smoke test evidence captured (240/0/3) | tasks.md, apply-progress.md |
| R2-006 | WARNING | Linked command evidence in apply-progress | apply-progress.md |
| R3-002 | BLOCKER | Behavioral test: runtime defaults_pseudo_CT('recenter_before_normalization') | run_smoke_tests.m §20a |
| R3-003 | BLOCKER | Structural: tcsh/sh pattern checks, all-3-input validation | run_smoke_tests.m §20b-20c |
| R3-004 | BLOCKER | Behavioral: PCA geometry with tall/wide/square/single/empty inputs (16 tests) | run_smoke_tests.m §21 |
| R3-005 | CRITICAL | Full: sign-convention score(:,1:d) + full-SVD coeff P×P + latent(n:p)=0 | pseudo_ct_princomp_legacy.m |
| R3-006 | CRITICAL | Behavioral coverage §7a (6 tests) + structural §22 (7 tests). E2E deferred. | run_smoke_tests.m |
| R4-002 | BLOCKER | Section 22: no-parity claims, output path contracts, deferred-warning documented | run_smoke_tests.m §22 |

## Remaining Release Gates

| Gate | Finding | Why Not Fixable Now |
|------|---------|---------------------|
| G1: R2026a E2E | R4-002, task 4.4 | Operator must run local pipeline end-to-end on R2026a MATLAB and compare against compiled Launchpad output. Design explicitly defers this. |

R3-003, R3-004, R3-005, R3-006 are all now covered by behavioral/structural tests at the code level. Full E2E validation (operator pipeline run) remains the single deferred gate.

## Files Changed

### Phase 1 (Commit 1 — Cleanup)
| File | Action |
|------|--------|
| `.gitignore` | Modified — added `spm8-dan/` |
| `package-lock.json` | Deleted |
| `openspec/changes/extract-version-changelog/archive-report.md` | Deleted |
| `TODO.md` | Added (staged) |
| `scripts/diff_entrypoint_runs.m` | Added (staged) |
| `scripts/compare_nifti_data.m` | Added (staged) |
| `scripts/compare_hash_strings.m` | Added (staged) |
| `scripts/restart_from_repos_checkpoint.m` | Added (staged) |
| `scripts/sweep_smoothing_fwhm.m` | Added (staged) |
| `src/config/pseudo_CT_keep_temp_enabled.m` | Added (staged) |
| `src/config/pseudo_CT_resolve_spm_root.m` | Added (staged) |
| `src/core/normalized_2_att_map.m` | Added (staged) |
| `src/core/pseudo_ct_princomp_legacy.m` | Added (staged) |
| `openspec/specs/entrypoint-divergence-diagnostics/spec.md` | Added (staged) |
| `openspec/changes/entrypoint-divergence-diagnosis/*` | Added (staged — 5 files) |
| `openspec/changes/investigation-cleanup-release/*` | Added (staged — 8 files) |

### Phase 2 (Commit 2 — Documentation + Smoke)
| File | Action |
|------|--------|
| `CHANGELOG.md` | Modified — v2.6.2 entry |
| `run_pseudo_CT_launchpad.m` | Modified — divergence warning header |
| `defaults_pseudo_CT_launchpad.m` | Modified — divergence caveat |
| `scripts/run_smoke_tests.m` | Modified — sections 7-22 |
| `scripts/diff_entrypoint_runs.m` | Modified — investigation-tool banner |
| `scripts/compare_nifti_data.m` | Modified — investigation-tool banner |
| `scripts/compare_hash_strings.m` | Modified — investigation-tool banner |
| `scripts/restart_from_repos_checkpoint.m` | Modified — investigation-tool banner |
| `scripts/sweep_smoothing_fwhm.m` | Modified — investigation-tool banner |
| `src/core/normalized_2_att_map.m` | Modified — investigation-tool banner + R1-002 validation |
| `src/core/pseudo_ct_princomp_legacy.m` | Modified — investigation-tool banner + R3-005 fixes |
| `src/remote/run_normalization_cmd.m` | Modified — R1-001 full validation |
| `src/config/defaults_pseudo_CT.m` | Modified — R3-002 recenter default revert |
| `.github/workflows/ci.yml` | Modified — R3-001, R4-001 |

### Unstaged
| File | Action | Reason |
|------|--------|--------|
| `scripts/run_tests.m` | git rm --cached | R1-003, R2-001 |

## Verification Results

### Lint
- 44 files checked, 777 pre-existing mlint issues
- **0 new violations** across all 3 batches

### Smoke Tests (Batch 3 — Final)
- **240 passed, 0 failed, 3 skipped**
- 3 pre-existing Batch_atlas skips (unchanged — not in test env)
- New Batch 3 tests (sections 19-22): **34 passed, 0 failed**
- R3-005 wide-matrix PCA: verified correct dimensions for coeff (P×P), score (N×P), latent (P×1) after full fix

### Command
```
/usr/pubsw/common/matlab/current/bin/matlab -nosplash -nodesktop -r "run('scripts/run_smoke_tests.m'); exit"
```
```
/usr/pubsw/common/matlab/current/bin/matlab -nosplash -nodesktop -r "run('scripts/run_lint.m'); exit"
```

### Cleanup Verification
- `spm8-dan/` gitignored ✓, present on disk ✓
- No untracked files remain outside `spm8-dan/`
- No Keep files were deleted
- Only `package-lock.json` and `archive-report.md` removed
- `scripts/run_tests.m` unstaged per approved removal classification (stays on disk)

## Deviations from Design
1. **run_tests.m removal**: Design originally classified it as Keep. Review-ledger R1-003 found hardcoded local paths and improper MATLAB syntax (R2-001). Un-staged per operator instruction. File remains on disk.
2. **recenter default preservation**: Design implied no runtime behavior changes. Review-ledger R3-002 identified the default change as unverified. Reverted to legacy `'Yes'`. Added behavioral smoke test.
3. **R3-005 multi-level fix**: Original Batch 2 fix (`U(:,1:n-1)`) addressed score dimensions only. Batch 3 full investigation discovered two additional latent bugs: (a) sign convention `bsxfun` dimension mismatch for wide matrices, (b) econ-SVD `coeff` contract violation (P×n instead of P×P). All three levels now fixed and tested.

## Issues Found
1. **Smoke test `diff-cmp` requires JVM**: `file_md5` uses Java MessageDigest; running with `-nojvm` causes `MD5_UNAVAILABLE`. With JVM: all tests pass. CI runners have JVM by default.
2. **R3-005 sign convention bug**: The `colsign` application at line 88 used `score` (N×P) with `colsign` (1×min(N,P)), causing dimension mismatch for wide matrices. Fixed to `score(:,1:d)`.
3. **R3-005 coeff contract bug**: Econ SVD returns V as P×min(N,P). Old princomp default (econFlag=0) returns P×P. Fixed by using full SVD for wide matrices.

## Remaining
- [ ] 4.4: Operator confirms R2026a E2E validation deferral before release tagging
- [ ] G1: R2026a E2E validation (single remaining gate — all code-level findings resolved)
- No commit, push, tag, or release performed — working tree prepared only (Batch 1 + 2 + 3)
