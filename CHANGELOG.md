2.7.3

## 2.7.3 — Profile-Configurable dicom2nifti Path

### Configuration
- Moved `dicom2nifti_standalone` path from hardcoded sibling-relative convention
  to a profile-configurable `d2n_root` field, consistent with `spm_root` and
  `atlas_root`.
- Added `d2n_root` to the required fields in `pseudo_CT_load_profile.m`.
- `setup_pseudo_CT_paths.m` now validates `d2n_root` in preflight and errors
  with `D2NRootMissing` if the directory is not found.
- Updated `scripts/test_compressed_nifti_input.m` to load the profile instead
  of hardcoding the sibling path.
- Installed path: `/usr/pubsw/packages/mrpet/standalone_apps/dcm2nii/dicom2nifti_standalone-latest`.

2.7.2

## 2.7.2 — Standalone DICOM/NIfTI Converter Integration

### Converter integration
- Replaced legacy `convert_dicom_i_2_nii` calls with direct `dcm2nii` from the
  standalone `dicom2nifti_standalone` converter at all three active call sites
  (`run_pseudo_CT.m` launchpad and local paths, `mMR_nii2mu_dicom_blur_david.m`).
- The standalone converter handles DICOM import, `.nii.gz` decompression, and
  plain `.nii` pass-through with explicit output selection and path/cwd restoration.
- Retired `src/io/convert_dicom_i_2_nii.m` to `deprecated/convert_dicom_i_2_nii.m`;
  preserved unchanged for historical reference.
- Added `dicom2nifti_standalone` to the pipeline path in `setup_pseudo_CT_paths.m`.
- Updated Stage 1 pipeline diagrams in `docs/pipeline-local.md` and
  `docs/pipeline-launchpad.md` to reflect the new converter.
- Updated compressed NIfTI regression coverage to exercise the direct `dcm2nii` path.

2.7.1

## 2.7.1 — Profile UX, MPRAGE-Only Workflows, and Compressed NIfTI Input

### Profile Selection and Policies
- Added a grouped, R2010b-compatible profile selector with Recommended and Specialized sections.
- Profile display names and descriptions are now independent from stable canonical CLI keys.
- Added explicit profile presentation metadata and deterministic selector ordering.
- Added `local-mprage-only` and `launchpad-mprage-only` profiles for workflows without UMAP references.
- Added validated I/O policies for reference discovery, output format, and GUI mode, including compatibility-baseline drift checks.

### Input and Output Safety
- Added case-insensitive `.nii.gz` MPRAGE input support with destination-local decompression staging.
- Compressed input archives are preserved byte-for-byte and temporary staging artifacts are cleaned up on success or failure.
- Output promotion now stages files before promotion to reduce the risk of partially written final outputs.
- MPRAGE-only workflows skip UTE/UMAP discovery and DICOM generation according to profile policy.

### Verification
- Added regression coverage for compressed NIfTI input, profile authority, MPRAGE-only collection, policy validation, and deterministic ordering.
- MATLAB R2010b and R2026a focused checks passed.
- Full smoke suite: 92 passed, 0 failed.

2.7.0

## 2.7.0 — Unified Entrypoint Migration and Profile Architecture (BREAKING)

### Unified Entrypoint
- **New primary entrypoint:** `run_pseudo_CT.m` replaces the two old entrypoints with a unified interface supporting 3 profiles, named arguments, and GUI integration.
- **Three execution profiles:** `local-current` (default), `local-near-parity-r2010b`, and `launchpad`. Profiles are selected via named argument or the GUI profile selector.
- **Named-argument CLI:** `run_pseudo_CT('profile', 'local-current', 'subjects', subject_list, 'correct_aliasing', 0)` replaces the old positional-argument calling convention.
- **GUI profile selector:** `run_pseudo_CT()` with no arguments opens a profile selection dialog before the subject selection dialog, enabling GUI-based profile choice.
- **R2010b warning:** Selecting `local-near-parity-r2010b` on a MATLAB release other than R2010b shows a warning that results may differ from expected near-parity output, and the runtime guard is bypassed.
- **Old entrypoints deprecated:** `run_pseudo_CT_local.m` and `run_pseudo_CT_launchpad.m` have been moved to `deprecated/` and are preserved unmodified for backward compatibility.
- **Shared job collection:** Added `collect_jobs.m` and `build_jobs_from_subject_list.m` as shared helpers used by the new entrypoint.

### Profile Authority Architecture
- **External SPM packages:** All canonical profiles now use deployment-provided SPM packages. The repository no longer ships a tracked SPM tree. The deployer is responsible for linking the correct SPM package to each profile via `src/config/spm_profiles/`.
- **Profile registry and templates:** Added `pseudo_CT_profile_registry.m`, `pseudo_CT_load_spm_profile_config.m`, and deployer-owned profile templates under `src/config/spm_profiles/`.
- **SPM revision validation:** Preflight validates the observed SPM revision from the deployment package's `Contents.m` before any path mutation. R2010b-compatible parsing recognizes `Version 6313 (SPM8)` and `Version 4667 (SPM8)`.
- **Fail-before-mutation contract:** `setup_pseudo_CT_paths.m` calls `pseudo_CT_preflight.m` before any `addpath`, `genpath`, `rehash`, or `which` calls. All resource checks complete before workflow mutation.
- **Environment resistance:** Profiles are the sole authority for behavior-changing settings. The 7-variable/3-profile prohibited-variable matrix is enforced by `test_profile_env_resistance.m` (32/32).
- **Removed tracked SPM tree:** Deleted `spm8-r6313/` (4022 files) and `pseudo_CT_provenance_record.m` (338 lines).

### Console Output and Logging
- **Timestamped run logs:** Per-subject timestamped run logs with standardized `[run]` level tags.
- **Profile summary:** Full profile summary printout saved to `MR_PET/`, including active PCA backend and resolution.

### NIfTI Input Workflow
- **NIfTI input staging:** `convert_dicom_i_2_nii.m` now copies `.nii` inputs into `MR_PET/tmp/mprage.nii` at entry time.
- **Output directory resolution:** `pseudo_CT_resolve_output_dirs.m` now checks for `MR/` as a sibling directory when the up-walk fails.
- **R2018b+ princomp fallback:** try-catch guard in `move_image_2_MNI.m` for removed-function error stubs.
- **Configurable PBS queue:** added `queue_name` to `defaults_pseudo_CT_launchpad.m`.

### Background Policy
- **Configurable background:** Added `zero_background` to both defaults files. Default is `'No'` (preserves historical values); `'Yes'` opts into final subject-mask multiplication.
- **Recenter compatibility:** Corrected to `'No'` — Launchpad runs `mri_normalize` first and passes `_normalized.nii`, bypassing recentering.

### Verification and Testing
- **Test suite:** 110 passed, 0 failed, 1 skipped. Includes SPM preflight threat tests (14/14), SPM external config tests (21/21), and profile environment resistance tests (32/32).
- **Reusable verification tools:** `diff_entrypoint_runs.m`, `compare_nifti_data.m`, `compare_hash_strings.m`, `pseudo_ct_princomp_legacy.m`.
- **Coregistration-parity finding:** MATLAB R2010b (7.11) / MCR 7.11 matches compiled Launchpad v2.0 at `spm_run_coreg_estimate` for byte-identical input. Modern MATLAB may diverge.

### BREAKING
- Scripts calling `run_pseudo_CT_local(...)` or `run_pseudo_CT_launchpad(...)` must be updated to `run_pseudo_CT('profile', ...)` with the appropriate profile. Old files remain under `deprecated/`.
- `spm8-r6313/` is no longer tracked. Deployers must link the correct SPM package via `src/config/spm_profiles/`.

2.6.6

## 2.6.6 — Profile Resource Authority (external SPM)
- **External SPM packages:** All canonical profiles now use deployment-provided SPM packages. The repository no longer ships a tracked SPM tree. The deployer is responsible for linking the correct SPM package to each profile via `src/config/spm_profiles/`.
- **Profile registry and templates:** Added `pseudo_CT_profile_registry.m`, `pseudo_CT_load_spm_profile_config.m`, and deployer-owned profile templates under `src/config/spm_profiles/` for `local-current` (r6313), `local-near-parity-r2010b` (r4667), and `launchpad` (r6313).
- **SPM revision validation:** Preflight validates the observed SPM revision from the deployment package's `Contents.m` before any path mutation. R2010b-compatible parsing recognizes `Version 6313 (SPM8)` and `Version 4667 (SPM8)`. Mismatches raise `SPM_ROOT:RevisionMismatch`.
- **Fail-before-mutation contract:** `setup_pseudo_CT_paths.m` calls `pseudo_CT_preflight.m` before any `addpath`, `genpath`, `rehash`, or `which` calls. All resource checks (SPM root, vers, atlas, normalization, PCA, provenance) complete before workflow mutation.
- **Environment resistance:** Profiles are the sole authority for behavior-changing settings. The 7-variable/3-profile prohibited-variable matrix is enforced by `test_profile_env_resistance.m` (32/32).
- **Removed tracked SPM tree:** Deleted `spm8-r6313/` (4022 files) and `pseudo_CT_provenance_record.m` (338 lines). SPM packages are provided at deployment time, analogous to `Batch_atlas`.
- **Test coverage:** Added `test_spm_preflight.m` (14/14 threat tests), `test_spm_external_config.m` (21/21 config tests). Full suite: 110 passed, 0 failed, 1 skipped.

## 2.6.5 - Configurable Background Policy and Bounded Launchpad Parity
- Added `zero_background` to `defaults_pseudo_CT.m` and `defaults_pseudo_CT_launchpad.m`. The default is `'No'`, which preserves historical background values; `'Yes'` opts into the final subject-mask multiplication and may alter PET attenuation-correction results.
- `pseudo_CT_zero_background_enabled` resolves through the supplied defaults function and safely returns `'No'` for older deployed defaults that do not define the key. `PSEUDOCT_ZERO_BACKGROUND=1|true|yes` remains an explicit opt-in.
- The local pipeline gates only the final subject-mask multiplication. Bone-segmentation reduction remains enabled and unchanged.
- The Launchpad entry point can apply the same optional mask after fetching `att_map.nii` and before DICOM conversion and output promotion. If `mprage_normalized.nii` is unavailable, it warns and preserves the fetched map.
- Corrected the recenter compatibility setting to `'No'`: actual Launchpad orchestration runs `mri_normalize` first and passes `_normalized.nii`, which bypasses recentering.
- A controlled one-subject comparison found New Segment to be host-environment sensitive. The legacy PBS E5472/RHEL7/glibc 2.17 environment matched the historical result exactly; celer R2010 compiled and interpreted runs matched each other but followed a slightly different iterative numerical path. CPU dispatch and system-math effects were not independently isolated.
- From exact cleaned `rc*` inputs, celer R2010 DARTEL, inverse warp, reslice, and final attenuation-map outputs were byte-identical. Final SHA-256: `dc7f0e49016c6cf034b12df04eba78dd346b816f9976da63b8dfd792fdf255cb`.
- Removed superseded parity-investigation runners while retaining the reusable entrypoint/NIfTI/hash comparators and two generic exact semantic comparators.
- The compiled Launchpad binary is unchanged. The finding is bounded to one controlled subject; manual end-to-end execution and QC review remain required.

## 2.6.4 — NIfTI MPRAGE Input Workflow
- **NIfTI input staging:** `convert_dicom_i_2_nii.m` now copies `.nii` inputs into `MR_PET/tmp/mprage.nii` at entry time, matching the DICOM branch behavior. Downstream `temp_dir` lookups (att_map.nii, DICOM write, promotion) now work correctly for NIfTI inputs.
- **Output directory resolution:** `pseudo_CT_resolve_output_dirs.m` now checks for `MR/` as a sibling directory when the up-walk fails, fixing `pseudo_muMAP` location for NIfTI inputs in `MR_PET/`.
- **R2018b+ princomp fallback:** added try-catch guard in `move_image_2_MNI.m` for MATLAB versions where `princomp` exists as a removed-function error stub.
- **Configurable PBS queue:** added `queue_name` to `defaults_pseudo_CT_launchpad.m` — set to `'p60'` for higher priority scheduling on Launchpad, or `''` for the default queue.
- **SDD cycle completed:** `launchpad-denoised-mprage-investigation` change planned, implemented, verified, and archived.

## 2.6.3 — Local Validation Policy
- Removed the GitHub Actions MATLAB workflow because this private repository cannot provide a MATLAB batch license token to GitHub-hosted runners.
- Validation remains local: run `scripts/run_lint.m` and `scripts/run_smoke_tests.m` before release.

## 2.6.2 — Investigation Cleanup Release
- **Coregistration-parity finding (qualitative):** MATLAB R2010b (7.11) / MCR 7.11 matches the compiled Launchpad v2.0 at `spm_run_coreg_estimate` for byte-identical input.
- **Divergence caveat:** Modern MATLAB (R2013b+, including R2026a) may produce divergent optimizer results even with identical input, SPM sources, and MEX.
- **Deferred-validation warning:** R2026a local E2E validation is deferred pending operator run; the compiled Launchpad v2.0 binary is unchanged.
- **Compatibility:** A legacy-compatible PCA shim (`pseudo_ct_princomp_legacy.m`) restores pre-coreg geometry when the legacy PCA path is selected. It does not claim to fix optimizer divergence.
- **Cleanup — removed transient artifacts:**
  - `package-lock.json` (accidental 6-line bare lockfile; no Node.js toolchain in project)
  - `openspec/changes/extract-version-changelog/archive-report.md` (stray archive output; duplicative of existing OpenSpec artifacts)
- **Cleanup — gitignored:** `spm8-dan/` (1.1 GB parity-testing SPM reference tree; stays on disk, operator-managed removal)
- **Reusable verification tools** remain tracked: `diff_entrypoint_runs.m`, `compare_nifti_data.m`, `compare_hash_strings.m`, and `pseudo_ct_princomp_legacy.m`.
- **Compatibility helpers:** `pseudo_CT_keep_temp_enabled.m`, `pseudo_CT_resolve_spm_root.m`, `TODO.md` (operator investigation notes).

## 2.6.1
- Centralized release version/history in `CHANGELOG.md`, exported `Pseudo_CT_AC_Version.txt` from the changelog source, and excluded `version.txt`, `Makefile`, and `scripts/` from packaged runtime releases.

## 2.6.0
- Unified UMAP discovery, configurable Batch_atlas resolution, and standalone release packaging.

## 2.5 (May 28, 2026)
- Repackaged as a standalone redistributable workflow for local execution while preserving the compiled v2.0 Launchpad backend option.

## 2.4 (Dec 17, 2017)
- Allows local FS connections (on 127.0.0.1)

## 2.3 (Sept 23, 2016)
- Improving of subject mask with MPRAGE_normalized.nii

## 2.2 (Jul 28, 2016)
- Integration of ssh_login()

## 2.1 (Jun 25, 2016)
- Printing a validation image in tiff

## 2.0 (Dec 9, 2014)
- Allowing Deployed version

## 1.8.1 (Sept 11, 2014)
- Including automatic nose-back anti-aliasing

## 1.8 (Sept 3, 2014)
- Centering subject in MPRAGE before normalization

## 1.7 (July 22, 2014)
- One big blob allowed on MPRAGE mask

## 1.6.2 (Apr 21, 2014)
- Including username in /cluster/scratch/monday folder

## 1.6.1 (Mar 13, 2014)
- Improving the Nose-job solution

## 1.6 (Feb 7, 2014)
- Increasing the attenuation mask to reduce Nose-job problems

## 1.5 (Aug 26, 2013)
- Solving bug when running parallel sessions

## 1.4 (Jun 21, 2013)
- Using Launchpad to run FreeSurfer commands

## 1.3 (May 16, 2013)
- New Larger atlas

## 1.2
- New FreeSurfer version 5.3

## 1.1
- We fill the head with soft-tissue when no atlas is present

---

Good News Everyone!! The paper has got accepted! (August/6/2014)!

If you use this method, or parts of it, please, quote this paper:

D. Izquierdo-Garcia, A.E. Hansen, S. Förster, D. Benoit, S. Schachoff, S. Fürst, K.T. Chen, D.B. Chonde, and C. Catana.
An SPM8-based Approach for Attenuation Correction Combining Segmentation and Non-rigid Template Formation: Application to Simultaneous PET/MR Brain Imaging. JNM. 2014. Nov;55(11):1825-30.

Enjoy it ;)) !!!
