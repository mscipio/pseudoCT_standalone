# Release notes — v3.0.1 (corrective, consolidated from v2.8.4)

For full history see `CHANGELOG.md`. Technical detail: `docs/installation.md`, `docs/scientific-notes.md`, `docs/scientific-notes.md`.

> **Withdrawn:** v3.0.0 was withdrawn after an installation-path
> validation issue with the bundled MLSC CURRENT backend. v3.0.1
> corrects it with the compiled scientific backend unchanged. No
> production deployment is claimed. No v3.0.0 GitHub release or tag
> is published; the last published release remains v2.8.4.

## What is new

### 1. MLSC CURRENT compiled backend
Full MPRAGE + UMAP workflow on MLSC from the current source, via a compiled backend. The exact backend bytes already passed controlled validation on MLSC (job 10492486, strict Gate-A PASS, attenuation map byte-identical to the local-current reference). No new scientific run was needed for the unchanged binary in v3.0.1. Use requires: an installed version containing the bundled backend, a valid cluster account, and the provisioned runtime and resources below.

### 2. Eight profiles: five Recommended, three Specialized
| Selector label | Key | Workflow |
|---|---|---|
| LOCAL - Current | `local-current` | MPRAGE + UMAP, local, current source |
| MLSC - Current | `mlsc-current` | MPRAGE + UMAP, MLSC, current source |
| LOCAL - Legacy v2.0 (Aether) | `local-legacy` | MPRAGE + UMAP, local, legacy backend |
| MLSC - Legacy v2.0 (Aether) | `mlsc-legacy` | MPRAGE + UMAP, MLSC, legacy backend |
| LAUNCHPAD - Legacy v2.0 (Aether) | `launchpad-legacy` | MPRAGE + UMAP, Launchpad, legacy backend |
| Local MPRAGE Only | `local-mprage-only` | MPRAGE only, NIfTI only, local |
| MLSC MPRAGE Only | `mlsc-mprage-only` | MPRAGE only, NIfTI only, MLSC |
| Development Current MATLAB | `devel` | Development only |

The selector shows the five Recommended rows in order; the Specialized section starts collapsed. Scripts use canonical keys. Bare `mlsc` is only a deprecated alias for `mlsc-legacy`. Deprecated `launchpad`, `launchpad-mprage-only`, `local-near-parity-r2010b` stay excluded and unsupported.

Standard profiles require the UMAP reference and produce NIfTI + DICOM. MPRAGE-only profiles skip the UMAP and produce NIfTI only.

### 3. Launchpad Legacy restored
`launchpad-legacy` is selectable again (availability restoration only; behavior unchanged). No new correctness claim beyond the dataset-specific states in `docs/scientific-notes.md`. Only `launchpad-legacy` is selectable; the deprecated Launchpad keys remain unsupported.

### 4. Current vs Legacy
Different numerical paths; bounded comparisons only, no universal equivalence. Always inspect QC.

### 5. Unified versioned installation
Numbered version directories with a `pseudoCT_standalone-latest` link. Inside an installation, MLSC CURRENT files resolve under `<version>/compiled/` at load time. Missing bundled files fail closed instead of silently using another location. Explicit artifact overrides remain for testing.

### 6. Portability correction (why v3.0.0 was withdrawn)
The original build/certification validation required absolute installed paths, so a relocated install failed validation even where install-relative defaults were available. v3.0.1 corrects validation to content identity for relocated identical artifacts and resolves defaults inside the installed version directory. Submitting-side handling only; the compiled backend is unchanged.

### 7. Workflow improvements since v2.8.4
Input (DICOM first-file or NIfTI, UMAP auto-discovery, cancel-safe selection), submission (dialog/batch/list, transient runtime credentials, runtime account handling), processing (local direct and remote paths with verified copy-back before finalization; keep MATLAB open), validation (resource checks first, missing/corrupt/foreign rejection, non-empty attenuation map required), logging (per-subject log, profile summary, version record), failure handling (retain intermediates, restart from beginning).

### 8. Controlled-dataset check (narrow)
On the controlled dataset the compiled MLSC CURRENT map matched the local-current reference byte-identically. Dataset-specific only; not a general claim and not a substitute for QC. v3.0.1 added no new scientific or submission run.

### 9. Documentation
Corrected researcher guidance, complete help workflow, and linked technical validation material. Historical records preserved.

### 10. MATLAB, dependencies, limits
- Verified: R2010b minimum for local/legacy paths; R2019+ for the aliasing/recentering facade (older releases continue with the original input plus an unavailable diagnostic); R2026a Update 2 with MCR 26.1 for the MLSC CURRENT build and run.
- Externally provisioned SPM, atlas/templates, FreeSurfer, converter, and aliasing tool are required and not bundled.
- MATLAB must stay open during processing and remote monitoring/finalization.
- Remote use needs a valid cluster account and provisioned paths; numerical results remain host-sensitive — inspect QC.

## Tested in this release
Existing controlled validation (MLSC job 10492486; strict Gate-A PASS and strict prepublication PASS on the exact backend bytes) carries forward unchanged. This release performed no new scientific, submission, or production run.

## History and support
v3.0.1 is the current documented source. v3.0.0 is a withdrawn historical entry only. v2.8.4 remains the last published archive. For failed or suspicious runs, keep the run log, profile summary, QC image, and software version.
