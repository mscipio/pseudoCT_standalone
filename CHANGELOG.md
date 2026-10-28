3.2.0

## 3.2.0-rc2 — MLSC MPRAGE-only current artifact correction

- Routes `mlsc-mprage-only` through the same current-lineage MLSC artifact and scheduler contract as `mlsc-current`, while retaining its MPRAGE-only, no-UMAP, NIfTI-only policies. Artifact-root and Gate-A-record overrides are accepted for both current MLSC profiles; missing or invalid artifacts still fail closed with no Aether fallback.
- Extends the exact v3.2.0-rc2 assembler/validator identity to the unchanged retained R2010b compiled payload. Provenance, package inventory, size, and SHA-256 checks are unchanged; no rebuild or scientific processing was performed.
- Updates operator and installation documentation. Source version metadata remains 3.2.0; no production deployment is claimed.

## 3.2.0-rc1 — Standalone release archive packaging

- Assembles the source and MLSC compiled payload under one `pseudoCT_standalone-3.2.0-rc1/` installation root so `run_pseudo_CT` and bundled compiled files resolve from an extracted archive. A working-source preview is explicitly marked nonpublishable; release assembly remains bound to the final committed source.
- Preserves the accepted R2010b compiled files and their exact manifest, executable, launcher, inventory size/SHA-256 checks, and documented provenance limits. No recompilation, scientific processing, shared-install modification, deployment, or startup-validation claim is made.
- Source version metadata is 3.2.0; the v3.1.1 release history and existing artifact provenance remain unchanged.

## 3.1.1 — Exact-payload release validation and documentation provenance

- Permits release validation of only the exact pinned current-lineage R2010b artifact for v3.1.1, with explicit pre-tag source identity and the final matching release tag; complete package inventory size and SHA-256 checks remain required. The compiled scientific executable is unchanged.
- Aligns operator and installation documentation with the Standard Processing, MPRAGE-only Processing, and Legacy Processing selector names and clarifies MATLAB R2010b compatibility requirements.
- Clarifies that the accepted MLSC executable described by the prior artifact record is current-lineage PseudoCT v3 compiled using MATLAB R2010b, not the historical v2 Aether implementation. Its association with user-accepted job 10515471 is unverified; the dirty source fingerprint cannot be independently reconstructed, and the scientific result remains dataset-specific. See [artifact provenance](RELEASE_PROVENANCE_v3.1.0.md).
- Source version metadata is 3.1.1; no production deployment is claimed.

## 3.1.0 — Profile terminology and evidence documentation

- Documents the recommended PseudoCT v3 — MLSC default, accepted current-lineage R2010b Compiler 4.14/MCR 7.14 backend, chosen-version local execution, MPRAGE-only requirements, and retained Aether profiles.
- Records user-accepted job 10515471 and its dataset-specific map digest/comparison; its association with the cited executable is unverified. Executor sidecar reporting is implemented, but live delivery is unconfirmed.

<a id="release-v3-0-2"></a>

## 3.0.2 — Flat-layout corrective release, published 2026-10-21

- Resolves the v3.0.0 MLSC validation issue and v3.0.1 source-wrapper incompatibility while retaining the complete v3 feature set; compiled scientific executable unchanged.
- See [installation requirements](docs/installation.md) and [scientific notes](docs/scientific-notes.md). No production deployment is claimed.
- Corrected source packaging: the published archive contains the complete current development source. The local CURRENT path (`src/core/atlas_based_attenuation_map.m`) is a thin facade that delegates preparation to `src/core/pseudo_CT_current_prepare.m` and computation to `src/core/pseudo_CT_current_compute.m`; the shared helpers and the MLSC CURRENT backend are unchanged.
- The corresponding CLI/progress regression test (`scripts/test_cli_progress_output.m`) is included and updated for the shared-boundary contract. The compiled scientific executable is unchanged (SHA-256 `6649a6ae91fd49f41b71d948a7c05012a8b8ac7c044edd05b4d53352f8cd518d`); no new scientific, submission, or production run was performed.

## 3.0.1 — WITHDRAWN (historical body retained; see the [v3.0.2 changelog entry](#release-v3-0-2))

- Corrects the withdrawn v3.0.0 installation-path validation issue; the compiled scientific backend is unchanged. No production deployment is claimed.
- Retains eight profiles, including selectable `launchpad-legacy`; current and legacy implementations have different numerical paths, with bounded evidence only.
- The existing controlled MLSC CURRENT validation carries forward for exact artifacts and one dataset; v3.0.1 added no new scientific run.
- See [installation requirements](docs/installation.md) and [scientific notes](docs/scientific-notes.md). v2.8.4 remains the last published archive.

## 3.0.0 — WITHDRAWN (historical entry only; do not use)
- MLSC CURRENT support: selectable `mlsc-current` profile (fail-closed before Gate-A), compiled-payload build path with content-bound provenance, and a fail-closed publication validator. Tooling is implemented and synthetically tested; no release-candidate build has been compiled and no package published.
- Consolidated profiles: eight active profiles (`local-current`, `local-legacy`, `mlsc-legacy`, `mlsc-current`, `launchpad-legacy`, `local-mprage-only`, `mlsc-mprage-only`, `devel`); deprecated profiles stay excluded from discovery and unsupported.
- `launchpad-legacy` availability: restored as a selectable recommended profile (availability only). Observed final-map states are dataset-specific (three states on the compared datasets); no state is declared correct and no universal parity is claimed.
- Provenance improvements: content-bound source fingerprints, complete packaged-file SHA-256 inventories, and deployment-copy provenance checked at the exact runtime path.
- Parity-evidence scope and limits: bounded controlled comparisons only; host CPU/system-math effects were not isolated independently, so results are not universal parity proof — inspect the QC image.
- No Gate-A PASS, deployment, or certification is claimed: Gate-A execution, publication, and any deployment remain separately human-authorized on a clean checkout at the release tag.
- MLSC CURRENT submitting-side default resolution (profile configuration only; certified-compiled-payload bytes unchanged): the `mlsc-current` profile defaults for runner/build/resource manifests and the Gate-A record resolve relative to the installed pseudoCT version directory derived from the profile location at load time. No absolute `/usr/pubsw/.../pseudoCT_mlsc_current/` fallback remains; absent bundled files fail closed at missing-file validation. Explicit `mlsc_current_artifact_root`/`mlsc_current_gate_a_record` overrides win. MCR pin (`/usr/pubsw/common/matlab/26.1`) untouched.

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
