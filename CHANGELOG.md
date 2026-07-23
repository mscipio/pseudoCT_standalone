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
