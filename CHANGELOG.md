2.6.3

## 2.6.3 — Local Validation Policy
- Removed the GitHub Actions MATLAB workflow because this private repository cannot provide a MATLAB batch license token to GitHub-hosted runners.
- Validation remains local: run `scripts/run_lint.m` and `scripts/run_smoke_tests.m` before release.

## 2.6.2 — Investigation Cleanup Release
- **Coregistration-parity finding (qualitative):** MATLAB R2010b (7.11) / MCR 7.11 matches the compiled Launchpad v2.0 at `spm_run_coreg_estimate` for byte-identical input.
- **Divergence caveat:** Modern MATLAB (R2013b+, including R2026a) may produce divergent optimizer results even with identical input, SPM sources, and MEX.
- **Deferred-validation warning:** R2026a local E2E validation is deferred pending operator run; the compiled Launchpad v2.0 binary is unchanged.
- **Compatibility:** A legacy-compatible PCA shim (`pseudo_ct_princomp_legacy.m`) restores pre-coreg geometry under `PSEUDOCT_USE_PRINCOMP=1`. It is documented as legacy-compatible and does not claim to fix optimizer divergence.
- **Cleanup — removed transient artifacts:**
  - `package-lock.json` (accidental 6-line bare lockfile; no Node.js toolchain in project)
  - `openspec/changes/extract-version-changelog/archive-report.md` (stray archive output; duplicative of existing OpenSpec artifacts)
- **Cleanup — gitignored:** `spm8-dan/` (1.1 GB parity-testing SPM reference tree; stays on disk, operator-managed removal)
- **Reusable investigation diagnostics** remain tracked: `diff_entrypoint_runs.m`, `compare_nifti_data.m`, `compare_hash_strings.m`, `restart_from_repos_checkpoint.m`, `sweep_smoothing_fwhm.m`, `normalized_2_att_map.m`, `pseudo_ct_princomp_legacy.m`. Each carries an `% Investigation tool — investigation-cleanup-release.` banner.
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
