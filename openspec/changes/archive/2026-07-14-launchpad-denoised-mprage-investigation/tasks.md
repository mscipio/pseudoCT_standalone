# Tasks: Launchpad Denoised MPRAGE Staging Fix

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~15-25 |
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

- [x] 1.1 Modify `.nii` branch in `src/io/convert_dicom_i_2_nii.m` (lines 132-135) to `copyfile` input into `fullfile(dir_final, 'mprage.nii')`, guarded by `has_dir_final`; retain original input
- [x] 1.2 Verify DICOM and `.i` conversion branches are completely unaffected

## Phase 2: Verification

- [x] 2.1 Prepare a denoised NIfTI input and run `run_pseudo_CT_launchpad` for one subject
- [x] 2.2 Confirm `att_map.nii` lands in `MR_PET/tmp/` and DICOM populates `pseudo_muMAP/` without path-mismatch errors
