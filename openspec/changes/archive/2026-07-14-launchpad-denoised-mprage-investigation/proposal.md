# Proposal: Launchpad Denoised MPRAGE Staging Fix

## Intent

NIfTI MPRAGE inputs (e.g., `MEMPRAGE_BC_denoised.nii`) cause the Launchpad pipeline to fail with `"Pseudo-CT processing finished without creating: .../MR_PET/tmp/att_map.nii"` because `convert_dicom_i_2_nii.m` does not stage the NIfTI into `MR_PET/tmp/`, while all downstream lookups assume it lives there. The file is actually created in the input's parent directory, but the path mismatch triggers an error and skips final promotion.

## Scope

### In Scope
- Modify `convert_dicom_i_2_nii.m` to copy and rename NIfTI inputs into `temp_dir` as `mprage.nii`
- Ensure all downstream paths (launchpad entry, batch, promotion, DICOM write) see `att_map.nii` in `temp_dir`
- Standardize artifact filenames for NIfTI inputs to match DICOM behavior
- Add regression test for NIfTI launchpad round-trip

### Out of Scope
- Modifying the compiled Launchpad binary (opaque MCR 7.11 ELF)
- Changing `pseudo_CT_promote_final_outputs` or `pseudo_CT_write_mu_map_dicom` lookup logic (Option A makes their `temp_dir` assumption correct)
- `keep_tmp` passthrough (already implemented)

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `launchpad-matlab-compat`: The "Post-Copy-Back Missing-Output Diagnostics" requirement may need adjustment because the error condition (missing att_map.nii in temp_dir) will no longer occur for NIfTI inputs. However, the diagnostic remains valuable for other failure modes; no spec change required.

## Approach

Option A: stage NIfTI into `MR_PET/tmp/mprage.nii` at entry time.

1. In `src/io/convert_dicom_i_2_nii.m`, add a `copyfile` + `delete` (or `movefile`) for `.nii` inputs to `dir_final` (which is `temp_dir`) with the standardized name `mprage.nii`.
2. The existing `dir_final` parameter already points to `temp_dir`; the change ensures the NIfTI is staged there, matching the DICOM branch behavior.
3. All downstream code (batch, scp_get, finalize, promotion) already expects `mprage.nii` in `temp_dir` — no further changes needed.
4. Add a regression test that creates a temporary NIfTI, runs the modified staging, and asserts the file exists in `temp_dir` with the correct name.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `src/io/convert_dicom_i_2_nii.m` | Modified | Add copy/rename for `.nii` branch to stage into `dir_final` as `mprage.nii` |
| `scripts/test_nifii_staging.m` | New | Regression test for NIfTI staging behavior |
| `openspec/specs/launchpad-matlab-compat/spec.md` | Potentially modified | May need to update diagnostic requirement if error condition changes |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Overwrites existing `MR_PET/tmp/mprage.nii` from a previous run | Low | Pipeline always creates fresh `temp_dir` per subject; existing file would be from same subject's prior run (safe to overwrite) |
| Original NIfTI filename lost for traceability | Low | Original path is logged; standardized name improves predictability across users |
| Regression test may not cover all edge cases | Medium | Add tests for both local and launchpad paths; manual verification still required |

## Rollback Plan

Revert the changes to `src/io/convert_dicom_i_2_nii.m` and delete the new test file. No other files are modified.

## Dependencies

- None.

## Success Criteria

- [ ] NIfTI inputs produce same artifact tree as DICOM inputs
- [ ] All downstream filenames standardized to `mprage_*` pattern
- [ ] Both local and launchpad pipelines work with NIfTI inputs
- [ ] Regression test passes for NIfTI staging
- [ ] No change in behavior for DICOM inputs

## Proposal question round

### Assumptions needing user review

1. **Standardized name**: We assume renaming the input NIfTI to `mprage.nii` is acceptable. The original filename is lost from the artifact tree but logged. Does this meet your traceability requirements?

2. **Overwrite policy**: If `MR_PET/tmp/mprage.nii` already exists (from a previous run on the same subject), we overwrite it. This is safe because the pipeline creates fresh `temp_dir` per subject, but we want to confirm.

3. **Test scope**: We plan to add a single regression test for NIfTI staging. Should we also test the full launchpad round-trip (requires SSH and cluster access), or is the staging test sufficient?

4. **Spec update**: The `launchpad-matlab-compat` spec's diagnostic requirement may become less triggered for NIfTI inputs. Should we update the spec to reflect the changed error condition, or leave it as-is since the diagnostic remains useful for other failures?

5. **Edge case**: NIfTI inputs located deeper than `MR/` (e.g., `MR/MEMPRAGE/MEMPRAGE_BC_denoised.nii`) — the staging will copy to `MR_PET/tmp/mprage.nii` regardless, which is correct. No additional logic needed.

### Questions for the user

1. Is the standardized `mprage.nii` name acceptable, or would you prefer to preserve the original basename (e.g., `MEMPRAGE_BC_denoised.nii`) in the staged copy?
2. Should we also rename the `_normalized.nii` outputs to standardize them, or leave that to the remote process?
3. Do you want the regression test to be TDD-style (red-green-refactor) or just a verification script?