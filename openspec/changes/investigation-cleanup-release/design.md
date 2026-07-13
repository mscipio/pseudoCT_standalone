# Design: Investigation Cleanup Release

## Technical Approach

Cleanup-first release preparation across three domains: (1) classify and handle untracked investigation artifacts via a three-way scheme (Keep/Remove/Ignore), (2) document the coregistration-parity finding and deferred-validation warning in CHANGELOG.md and source headers, (3) produce reviewable work-unit commits under a 800-line changed-line budget with approved `size:exception` for smoke-test expansion.

## Architecture Decisions

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Single commit vs. work-unit slices | Single commit ~1295 lines exceeds review budget | **Two work-unit commits**: (1) cleanup + classification + gitignore, (2) documentation + headers + CHANGELOG + smoke-test expansion |
| Track spm8-dan/ vs. gitignore | 1.1 GB parity-testing SPM variant; not production code; reproducible from reference | **Gitignore** — add `spm8-dan/` to `.gitignore`. Tree stays on disk. Operator deletes manually later. No physical deletion (`rm -rf`) in implementation. |
| Delete run_tests.m vs. keep | Contains hardcoded paths but documents the exact PCA investigation procedure | **Keep** — reusable diagnostic reference, not transient cookbook waste |
| package-lock.json action | Clearly accidental (6-line bare lockfile in MATLAB-only repo) | **Delete** — no Node.js toolchain in project |
| archive-report.md action | Stray SDD archive output from `extract-version-changelog`, not tracked | **Delete** — transient, duplicative of existing OpenSpec artifacts |
| Diagnostic header format | Minimal one-liner vs. full block | **One-line banner** at top of each script: `% Investigation tool — investigation-cleanup-release.` |
| Smoke-test expansion budget | 1038-line smoke-test diff exceeds 800-line review budget | **size:exception approved** — smoke-test expansion is budget-exempt. Reviewer-risk acknowledged: expansion rides with documentation commit for atomic CHANGELOG-verification pairing. CI gate (`run_smoke_tests.m`) must pass cleanly before landing. |

## File Changes

### Commit 1: Cleanup + Classification (Add untracked + gitignore)

| File | Action | Description |
|------|--------|-------------|
| `TODO.md` | Add | Operator investigation notes — must be preserved per spec |
| `scripts/diff_entrypoint_runs.m` | Add | Reusable entrypoint comparison diagnostic |
| `scripts/compare_nifti_data.m` | Add | Reusable NIfTI comparison utility |
| `scripts/compare_hash_strings.m` | Add | Reusable hash-equivalence judge |
| `scripts/restart_from_repos_checkpoint.m` | Add | Reusable restart-from-checkpoint diagnostic |
| `scripts/sweep_smoothing_fwhm.m` | Add | Reusable FWHM sweep diagnostic |
| `scripts/run_tests.m` | Add | PCA investigation test procedure (reference) |
| `src/config/pseudo_CT_keep_temp_enabled.m` | Add | Reusable keep-temp compatibility helper |
| `src/config/pseudo_CT_resolve_spm_root.m` | Add | Reusable SPM-root resolver |
| `src/core/normalized_2_att_map.m` | Add | Reusable downstream diagnostic pipeline |
| `src/core/pseudo_ct_princomp_legacy.m` | Add | Legacy PCA shim (R2010b-compatible) |
| `openspec/specs/entrypoint-divergence-diagnostics/spec.md` | Add | Delta spec promoted from change |
| `openspec/changes/entrypoint-divergence-diagnosis/*` | Add | Archived SDD change artifacts |
| `openspec/changes/investigation-cleanup-release/*` | Add | Active SDD change (proposal, specs, design) |
| `.gitignore` | Modify | Add `spm8-dan/` entry — tree stays on disk, operator deletes manually later |
| `package-lock.json` | Delete | Accidental generation — no Node.js toolchain |
| `openspec/changes/extract-version-changelog/archive-report.md` | Delete | Stray archive artifact |

### Commit 2: Documentation + Headers + CHANGELOG + Smoke Tests

| File | Action | Description |
|------|--------|-------------|
| `CHANGELOG.md` | Modify | Add v2.6.2 entry: investigation finding, deferred-validation warning, cleanup exclusions |
| `run_pseudo_CT_launchpad.m` | Modify | Add divergence warning to header: "Modern MATLAB (R2013b+) MAY produce divergent optimizer results" |
| `defaults_pseudo_CT_launchpad.m` | Modify | Add divergence warning caveat to minimum-version line |
| `scripts/run_smoke_tests.m` | Modify | **size:exception** — expand CHANGELOG structural checks, add-divergence-warning assertions, classification verification. 1038-line diff accepted under approved exception. |
| `scripts/diff_entrypoint_runs.m` | Modify | Add investigation-tool header banner |
| `scripts/compare_nifti_data.m` | Modify | Add investigation-tool header banner |
| `scripts/compare_hash_strings.m` | Modify | Add investigation-tool header banner |
| `scripts/restart_from_repos_checkpoint.m` | Modify | Add investigation-tool header banner |
| `scripts/sweep_smoothing_fwhm.m` | Modify | Add investigation-tool header banner |
| `src/core/normalized_2_att_map.m` | Modify | Add investigation-tool header banner |
| `src/core/pseudo_ct_princomp_legacy.m` | Modify | Add investigation-tool header banner |

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Smoke | All tracked `.m` files parse; CHANGELOG structure; header warnings present | `run_smoke_tests.m` — expanded under approved size:exception (1038-line diff). CI must pass cleanly. |
| Lint | No new mlint violations | `run_lint.m` over `src/`, `vers/`, entry scripts, `scripts/` |
| Manual | CHANGELOG wording matches spec scenarios | Human review of divergence-warning language — no numeric deltas |
| Manual | `spm8-dan/` still present on disk but gitignored | `git ls-files --others` after commit 1; `spm8-dan/` MUST appear as untracked |

## Migration / Rollout

No data migration. Release warning is passive documentation — no runtime behavior change. Rollback: revert commits before tagging. `spm8-dan/` is never touched by implementation; operator deletes manually when ready.

## CHANGELOG Entry Boundary (v2.6.2)

The CHANGELOG entry SHALL contain:
1. Coregistration finding (qualitative, no deltas): "R2010b/MCR 7.11 matches compiled Launchpad at coregistration"
2. Divergence caveat: "Modern MATLAB (R2013b+) may produce divergent optimizer results"
3. Deferred-validation warning: "R2026a local E2E validation is deferred pending operator run; the compiled Launchpad v2.0 binary is unchanged"
4. Cleanup exclusions list with removal reason per artifact
5. `spm8-dan/` noted as "gitignored parity-testing SPM reference tree (stays on disk; operator-managed removal)"
6. Diagnostic tools listed as "reusable investigation diagnostics"

## Review Workload Forecast

| Metric | Value |
|--------|-------|
| Total changed lines (estimated) | ~1295 |
| Commit 1 (cleanup + classification) | ~420 lines |
| Commit 2 (docs + headers + CHANGELOG + smoke) | ~875 lines |
| Smoke-test expansion (carved from commit 2) | ~1038 lines — **size:exception approved** |
| 800-line budget risk | **High** (mitigated: exception accepted) |
| Chained PRs recommended | No — two-commit linear history sufficient |
| Decision needed before apply | No — exception already approved by operator |

**Reviewer-risk acknowledgement**: The smoke-test expansion substantially exceeds the 800-line review budget. Risk is accepted because (a) smoke tests are structural assertions, not business logic, (b) they ride with documentation commit for atomic CHANGELOG-verification pairing, and (c) CI gate (`run_smoke_tests.m`) blocks landing on failure. Reviewers should focus on CHANGELOG wording accuracy and header warning language; smoke-test assertions are mechanical structural checks.

## Open Questions

- [ ] Operator must confirm R2026a E2E validation deferral before tagging release
