# TODO

## Feature Requests from Collaborators

### 1. PET-MR Data Unpacking and Local DICOM Sequence Sorting

**What they had:** The old Aether workflow combined two distinct stages. `unpack_mr_data.m` uses remote `findsession` and `mrpet_unpack_MASAMUNE` to unpack BrainPET/raw PET-MR data on Launchpad/Bourget. The separate `organize_MR_files_David.m` stage is a local sorter: it reads the MR log and DICOM headers (`SeriesDescription`) and moves already-unpacked DICOMs into named folders (MPRAGE, UTE, FLASH, etc.). Unrecognized sequences get saved with the DICOM `SeriesDescription` as the folder name instead of `Unknown`.

**What they need:** A standalone local sorter that takes already-unpacked DICOMs (for example, organized into `Unknown*` folders by scanner or network transfer), reads DICOM headers, and sorts them into named sequence folders. This does NOT require the SSH/Launchpad/Bourget path. It is not equivalent to BrainPET/Aether raw-data unpacking: the local sorter cannot currently unpack raw BrainPET/PET-MR exports or replace `findsession`/`mrpet_unpack_MASAMUNE`.

**Source files found in backup:**
- `/Aether-bkp-05062026/david-matlab/mMR_GUI/unpack_mr_data.m` — SSH-based unpacking from Bourget (Launchpad)
- `/Aether-bkp-05062026/david-matlab/mMR_GUI/organize_MR_files_David.m` — Local DICOM sorting by SeriesDescription + log file
- `/Aether-bkp-05062026/dan-matlab/Masamune/Masamune.m` — GUI wrapper

**Important boundary:** The legacy backup contains related workflows, not one proven end-to-end seven-step pipeline. Do not present the remote unpacker and local sorter as a single independently validated replacement.

**Dependencies and limitation:** `organize_MR_files_David.m` depends on `Load_MR_log`, `gen_MR_folder_name`, and `ckdir_mkdirn`. Its no-log `dicoms` fallback is weak/undefined, so the function is not fully self-contained as currently written.

**Design question:** Should the local sorter be a new entry in `run_pseudo_CT` (pre-processing step), or a standalone script? The sorting logic is a candidate for extraction, but its dependencies and no-log behavior must be resolved first.

**Action:** Extract organize_MR_files_David.m logic into a standalone function in src/. Remove the SSH/Bourget dependency. Add the Unknown-folder-rename logic from Zeynab's script (the dicominfo-based SeriesDescription rename loop).

### 2. MPRAGE Denoising Tool — david-matlab/denoise_MPRAGE_smoothed_Nicole.m

**What they had:** denoise_MPRAGE_smoothed_Nicole(MPRAGE_filename, threshold) which: (1) smooths MPRAGE with 4mm Gaussian via spm_run_smooth, (2) creates a head mask from the smoothed image using head_mask_mprage.m (thresholding + imfill hole-filling + erosion), (3) sets voxels outside the mask to NaN, writes _denoised.nii. The threshold (default 20, user's script used 55) is per-subject tunable.

**Source files found in backup:**
- `/Aether-bkp-05062026/david-matlab/att_map/denoise_MPRAGE_smoothed_Nicole.m` — 67 lines, the denoising function
- `/Aether-bkp-05062026/david-matlab/att_map/atlas_method/head_mask_mprage.m` — 80 lines, the mask generation dependency

**Dependencies:** SPM (spm_vol, spm_read_vols, spm_run_smooth, spm_write_vol), MATLAB Image Processing Toolbox (imdilate, imfill, imerode).

**Design question:** Users want this to work on NIfTI inputs independently (not coupled to pseudo-CT). 40-80% of subjects need it. Should it be: (a) a standalone script in src/ called before run_pseudo_CT, (b) an optional pre-processing flag in run_pseudo_CT, or (c) both? Users prefer standalone with NIfTI I/O.

**Action:** Port denoise_MPRAGE_smoothed_Nicole.m + head_mask_mprage.m into src/. Make it accept NIfTI input path + threshold, write _denoised.nii. Consider: the smoothing step may be unnecessary with modern bias-correction tools (N4ITK etc.) — confirm with users whether the 4mm Gaussian smoothing is still desired or if they want an improved method.

### 3. DICOM-to-NIfTI Conversion Tools

**What they had:** The user's script calls `convert_dicom_i_2_nii` (for MPRAGE, MUMAP, and fat/water MUMAPs) and `convert_4D_PET_dicom_2nii` (for `PET_60-90`). The current package contains `src/io/convert_dicom_i_2_nii.m`, but `convert_4D_PET_dicom_2nii.m` is missing from `src/`; `src/io/convert_dicom_i_2_nii.m` calls it, so this is an unresolved dependency rather than complete coverage. The user needs these to work standalone for pre-processing steps (bias correction, denoising, and coregistration) before pseudo-CT generation.

**Source files found in backup:**
- `/Aether-bkp-05062026/david-matlab/Nifti/convert_dicom_i_2_nii.m` — 124 lines, multi-format DICOM/NIfTI converter using spm_dicom_convert
- `/Aether-bkp-05062026/david-matlab/Nifti/convert_4D_PET_dicom_2nii.m` — 304 lines, 4D PET DICOM to NIfTI with PMOD-style extended header

**Note:** Only the `.i`/DICOM conversion path is currently represented in `src/io/`; the required 4D PET converter still needs to be recovered or implemented. A simpler CLI wrapper may also be needed after the dependency gap is closed.

**Action:** Resolve the missing `convert_4D_PET_dicom_2nii` dependency and verify that both conversion paths cover the same use cases. Then consider standalone CLI wrappers.

### 4. NIfTI-to-DICOM Conversion (pCT output)

**What they had:** nii2dcm_header_copy_vb20_david.m by Spencer Bowen / David Izquierdo — copies DICOM metadata from a reference DICOM series and writes a new DICOM series using NIfTI image data. Used to convert corrected pseudo-CT back to DICOM.

**Source file found:**
- `/Aether-bkp-05062026/david-matlab/from_Spencer/mmr_dicom/nii2dcm_header_copy_vb20_david.m` — 167 lines, handles DataSetTrailingPadding and InstanceNumber offset

**Note:** `src/io/nii2dcm_header_copy_vb20_david.m` exists, and the current NIfTI input staging is implemented. The user's script shows an exact manual corrected-pCT workflow (`pCT_corrected.nii` -> DICOM) that bypasses the standard pipeline; that workflow still needs validation.

**Action:** Validate that the existing `nii2dcm` path handles the exact corrected-pCT manual case. If not, adapt the existing path or extract the required behavior.

---

## Summary of Priority

| Request | Complexity | Status in pseudoCT_standalone |
|---|---|---|
| DICOM auto-sorting (organize) | Low-Medium | NOT present — needs dependency review and extraction |
| MPRAGE denoising (NIfTI I/O) | Low | NOT present — needs extraction + dependency |
| DICOM-to-NIfTI conversion | Low | Partial — `convert_dicom_i_2_nii` exists, but its 4D PET dependency is missing |
| NIfTI-to-DICOM conversion | Low | Input staging is implemented and `nii2dcm_header_copy_vb20_david.m` exists; validate the manual-correction path |

## Recommended Next Steps

1. **Quick win:** Port organize_MR_files_David.m + the Unknown-folder rename loop into a standalone function (src/preprocessing/sort_dicom_sequences.m or similar). This directly solves the biggest pain point.
2. **Medium effort:** Port denoise_MPRAGE_smoothed_Nicole.m + head_mask_mprage.m into src/preprocessing/denoise_mprage.m. NIfTI in, NIfTI out. Threshold as parameter.
3. **Low effort:** Confirm the existing dicom-to-nifti and nifti-to-dicom paths cover the user's pre-processing workflow. If not, extract the standalone versions from the backup.
