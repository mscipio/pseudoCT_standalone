3.3.0

# pseudoCT — Version History

This concise history identifies the major change associated with each version. The complete technical and development history is maintained in `docs/CHANGELOG_DETAILED.md` in the source repository. Exact processing provenance is recorded separately in the application's version metadata, logs, and package manifest.

- **3.3.0** — Added multi-subject GUI/CLI inputs, concurrent local and MLSC processing, per-subject progress and results, and a bundled Python runtime.
- **3.2.0 (unpublished)** — Consolidated scientific worker naming, cleaned up the standalone architecture, and clarified build and deployment requirements.
- **3.2.0-rc2 (prerelease)** — Corrected the MLSC MPRAGE-only workflow and validated reuse of its retained compiled artifact.
- **3.2.0-rc1 (prerelease)** — Introduced unified standalone release-archive assembly around the retained compiled payload.
- **3.1.1** — Strengthened exact-payload release validation and clarified installation and compiled-artifact provenance.
- **3.1.0** — Standardized processing-profile terminology and documented scientific validation evidence and limitations.
- **3.0.2 (published)** — Corrected standalone installation and source packaging defects while retaining the scientific executable.
- **3.0.1 (withdrawn)** — Superseded by 3.0.2 following installation and packaging issues; do not use.
- **3.0.0 (withdrawn)** — Initial v3 MLSC CURRENT and profile architecture; superseded by 3.0.2; do not use.
- **2.8.4 (published)** — Released GUI controls for independent aliasing correction and MPRAGE recentering.
- **2.8.3 (published)** — Clarified external SPM8 and Batch_atlas prerequisites and removed stale Git LFS rules.
- **2.8.2 (published)** — Refined repository layout and release-archive inclusion policy.
- **2.8.1 (published)** — Aligned release documentation, version fallback, and smoke-test references.
- **2.8.0 (published)** — Introduced the profile-configured external aliasing/centering interface.
- **2.7.3 (published)** — Made the DICOM-to-NIfTI converter path configurable by profile.
- **2.7.2 (unpublished)** — Integrated the standalone DICOM/NIfTI converter and retired the legacy conversion code.
- **2.7.1 (published)** — Improved profile selection, MPRAGE-only processing, and compressed NIfTI input support.
- **2.7.0 (published)** — Introduced the unified `run_pseudo_CT` entry point and named processing-profile architecture.
- **2.6.6 (unpublished)** — Established external SPM resource authority and revision preflight checks.
- **2.6.5 (unpublished)** — Added configurable background masking and bounded Launchpad parity checks.
- **2.6.4 (published)** — Corrected NIfTI MPRAGE staging and output resolution and made the Launchpad queue configurable.
- **2.6.3 (published)** — Moved MATLAB validation to local lint and smoke-test workflows.
- **2.6.2 (tag only)** — Cleaned up legacy compatibility code following R2010b/Launchpad parity investigation.
- **2.6.1 (tag only)** — Centralized release history and historical version-file export around the changelog.
- **2.6.0 (published)** — Introduced standalone release packaging and unified UMAP discovery.
- **2.5** — Repackaged the workflow for standalone local execution with the retained v2 Launchpad option.
- **2.4** — Enabled local FreeSurfer connections through `127.0.0.1`.
- **2.3** — Improved subject masking using `MPRAGE_normalized.nii`.
- **2.2** — Integrated SSH login support.
- **2.1** — Added TIFF validation-image output.
- **2.0** — Enabled deployed execution.
- **1.8.1** — Added automatic nose/back anti-aliasing.
- **1.8** — Added MPRAGE centering before normalization.
- **1.7** — Supported a single connected MPRAGE mask region.
- **1.6.2** — Included the username in the cluster scratch-folder name.
- **1.6.1** — Improved nose-artifact handling.
- **1.6** — Increased the attenuation mask to reduce nose-related artifacts.
- **1.5** — Fixed parallel-session handling.
- **1.4** — Used Launchpad to run FreeSurfer commands.
- **1.3** — Introduced a larger atlas.
- **1.2** — Updated FreeSurfer to version 5.3.
- **1.1** — Filled the head with soft-tissue attenuation when no atlas is available.
