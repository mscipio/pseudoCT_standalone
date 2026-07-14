# Verification Report

**Change**: launchpad-denoised-mprage-investigation
**Mode**: tasks + specs
**Verified at**: 2026-07-14

## Completeness

| Task | Status | Evidence |
|------|--------|----------|
| 1.1 Modify `convert_dicom_i_2_nii.m` `.nii` branch | DONE | Lines 132-146: `copyfile(strtrim(P(ii,:)), aux2)` guarded by `has_dir_final`; original preserved |
| 1.2 Verify DICOM / `.i` branches unaffected | DONE | DICOM branch (L37-106) and `.i` branch (L107-131) byte-for-byte unchanged; smoke tests pass |
| 2.1 Update main spec with staging req + diagnostic carve-out | DONE | `openspec/specs/launchpad-matlab-compat/spec.md` L42-97 contain both updated requirements |
| 2.2 Launchpad round-trip rerun | **MANUAL** | Requires SSH/cluster access + compiled Launchpad app — deferred to user environment |

## Spec Compliance

| Requirement | Status | Evidence |
|-------------|--------|----------|
| NIfTI Input Staging at Entry Time | COMPLIANT | L140: `copyfile` to `fullfile(dir_final, nii_name)`; both entry scripts pass `'mprage.nii'` (`run_pseudo_CT_launchpad.m:103`, `run_pseudo_CT_local.m:207`) so standardized name holds at pipeline level |
| Post-Copy-Back Missing-Output Diagnostics (MODIFIED) | COMPLIANT | Carve-out text in main spec L44 + new scenario L67-72; staging eliminates false-positive trigger |
| Pre-R2013a strsplit Backport | COMPLIANT | Unchanged from prior implementation |
| Post-R2015a numel Colon Fix | COMPLIANT | Unchanged from prior implementation |
| Minimum MATLAB Version Documentation | COMPLIANT | Unchanged from prior implementation |

## Test Evidence

- Smoke tests: 240 passed, 3 pre-existing failures (CHANGELOG version, recenter default assertion), 3 pre-existing skips (Batch_atlas not in test env)
- No regressions introduced by the NIfTI branch change
- Manual end-to-end Launchpad verification remains the user's responsibility (SSH + compiled app)

## Issues

- **SUGGESTION (drift, not violation)**: `convert_dicom_i_2_nii.m:11` default `nii_name` is `'MPRAGE_spm.nii'`, not `'mprage.nii'`. The pipeline-level spec is satisfied because callers pass `'mprage.nii'` explicitly, but the function could hardcode `'mprage.nii'` for the `.nii` branch (L132) to make the standardized-name contract a local invariant rather than a caller responsibility. Low priority — current behavior is correct given the existing call sites.

No CRITICAL or WARNING items.

## Manual Verification Required

- [ ] **Launchpad round-trip with denoised NIfTI** (Task 2.2):
  1. Provide `MEMPRAGE_BC_denoised.nii` as input to `run_pseudo_CT_launchpad`
  2. Verify `MR_PET/tmp/mprage.nii` exists as a copy of the input
  3. Verify cluster returns `att_map.nii` into `MR_PET/tmp/`
  4. Verify `pseudo_muMAP/` populated with DICOM files
  5. Verify NO "Pseudo-CT processing finished without creating" diagnostic fires

## Verdict

**PASS WITH WARNINGS** — code verified, smoke tests clean, spec updated, one manual test pending (user's Launchpad environment).
