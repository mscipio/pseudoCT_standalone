2.8.4

## 2.8.4 — Published release (2026-08-31)
- Published release archive is available.
- Added matching, aligned GUI checkboxes for independent nose/back aliasing correction and MPRAGE recentering; the visual GUI alignment refinement did not change processing or API behavior.

## 2.8.3 — Published release (2026-08-27): External Prerequisite Documentation Correction
- Clarified that `Batch_atlas` and SPM8 are externally provisioned prerequisites, not bundled repository or release-archive content.
- Removed stale `Batch_atlas` Git LFS rules; no external payloads or pipeline behavior changed.

## 2.8.2 — Published release (2026-08-27): Repository Layout and Release Archive Policy
- Moved maintainer metadata and the Makefile out of runtime paths, and applied export-ignore rules so maintenance/docs content is excluded from release archives while deployable runtime files remain included.
- Reconciled documentation, version fallback, and smoke-test references without changing pipeline behavior.

## 2.8.1 — Published release (2026-08-27): Documentation / Version-Fallback Coherence
- Aligned the hardcoded version fallback, current-release documentation, and smoke-test assertion with 2.8.1; no pipeline behavior changed.

## 2.8.0 — Published release (2026-08-27): External Aliasing and Centering Facade
- Added profile-configured `aliasing_root`; the external `correct_aliasing` standalone owns local alias correction and centering, while Launchpad remains delegated to its compiled backend.
- Smoke and profile-authority validation passed; legacy in-package implementations were retained under `deprecated/`.

## 2.7.3 — Published release (2026-08-26): Profile-Configurable dicom2nifti Path
- Made the standalone DICOM/NIfTI converter path profile-configurable through `d2n_root`, with preflight validation and compressed-NIfTI regression coverage using the profile.

## 2.7.2 — Unpublished; no public ref (GitHub commit date 2026-08-04): Standalone DICOM/NIfTI Converter Integration
- Replaced legacy conversion calls with the standalone `dcm2nii` converter for DICOM import, `.nii.gz` decompression, and plain `.nii` pass-through; the legacy converter was moved to `deprecated/`.

## 2.7.1 — Published release (2026-07-30): Profile UX, MPRAGE-Only Workflows, and Compressed NIfTI Input
- Added grouped profile selection, MPRAGE-only policies, and deterministic profile metadata, with validated reference/output/GUI behavior.
- Added safe compressed-NIfTI staging and output promotion; focused MATLAB checks and the smoke suite passed.

## 2.7.0 — Published release (2026-07-28): Unified Entrypoint and Profile Architecture
- Replaced separate entrypoints with `run_pseudo_CT.m`, named profiles, shared job collection, and GUI profile selection; old entrypoints remain under `deprecated/`.
- Made deployment-provided SPM authoritative through profile templates and revision preflight, with fail-before-mutation resource checks.

## 2.6.6 — Unpublished; no public ref (GitHub commit date 2026-07-23): Profile Resource Authority
- Established external SPM packages, profile registry/templates, revision validation, and fail-before-mutation preflight; removed the tracked SPM tree and added focused validation.

## 2.6.5 — Unpublished; no public ref (GitHub commit date 2026-07-21): Configurable Background Policy and Bounded Launchpad Parity
- Added opt-in background masking and bounded Launchpad parity checks, corrected the historical Launchpad recenter compatibility setting to `'No'`, and documented host-environment sensitivity.

## 2.6.4 — Published release (2026-07-14): NIfTI MPRAGE Input Workflow
- Fixed `.nii` MPRAGE staging and output-directory resolution, added a `princomp` compatibility fallback, and made the Launchpad queue configurable.

## 2.6.3 — Published release (2026-07-13): Local Validation Policy
- Moved MATLAB validation from unavailable GitHub-hosted licensing to local `scripts/run_lint.m` and `scripts/run_smoke_tests.m` checks before release.

## 2.6.2 — Public annotated tag only (annotated tagger date 2026-07-13): Investigation Cleanup
- Recorded R2010b/compiled-Launchpad coregistration parity and modern-MATLAB divergence, added a legacy-compatible PCA shim, and removed transient investigation artifacts.

## 2.6.1 — Public annotated tag only (annotated tagger date 2026-07-07): Changelog-Centered Release Metadata
- Centralized release history in `CHANGELOG.md`, exported `Pseudo_CT_AC_Version.txt` from it, and excluded maintainer-only files from packaged runtime releases.

## 2.6.0 — Published release (2026-06-30): Standalone Release Packaging
- Added unified UMAP discovery, configurable `Batch_atlas` resolution, and standalone release packaging.

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
