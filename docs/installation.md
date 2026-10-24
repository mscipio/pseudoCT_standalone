# Installation and requirements

## Martinos deployment

Martinos users should use the centrally provisioned installation at `/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/`. Add the installation root (`pseudoCT_standalone-latest` or a numbered version directory) to MATLAB's path. Run `run_pseudo_CT` from a convenient working directory. Keep MATLAB open during processing and, for remote jobs, monitoring and finalization. See the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/) for input layout, step-by-step use, outputs, and QC.

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
% or: addpath('/path/to/pseudoCT_standalone-3.1.0')
run_pseudo_CT
```

## External installations

This repository is not a self-contained software installation. MATLAB and compatible, separately provisioned resources are required:

- SPM8 and the pseudoCT atlas images and SPM batch templates (`spm_root`, `atlas_root`).
- The standalone DICOM-to-NIfTI converter (`d2n_root`).
- FreeSurfer 5.3, available through the selected profile's normalization environment command.
- For local profiles, the standalone aliasing/recentering tool (`aliasing_root`). The facade requires MATLAB R2019+; older MATLAB continues with the original input and an unavailable diagnostic.
- For remote profiles, the relevant cluster/Launchpad runtime and provisioned resources. MLSC use also needs a valid cluster account; MATLAB remains open while jobs are monitored and finalized.

These resources are not included in the repository or release archive. Martinos profiles provide site-specific defaults. Outside that environment, configure the paths in the selected profile under `src/config/profiles/` for compatible installations. Resource validation occurs at startup where applicable; FreeSurfer is checked when normalization runs.

MATLAB R2010b is the selector's minimum supported release. The accepted current-lineage Center Standard MLSC production backend uses MATLAB R2010b with MATLAB Compiler 4.14 and requires MCR 7.14. This is distinct from Local execution, which uses the chosen MATLAB version; results may vary. R2026a comparison records are a separate runtime path. The aliasing/recentering facade requires R2019+.

## Profiles

**Standard Processing** shows **PseudoCT v3 — MLSC** as the recommended default and **PseudoCT v3 — Local** as an alternate. The initially collapsed **MPRAGE-only Processing** and **Legacy Processing** sections retain their separate profile choices. Selector labels do not change the canonical profile identities shown in summaries or used for configuration.

| Section | Canonical ID | Selector label | Selector description |
|---|---|---|---|
| Standard Processing | `mlsc-current` | PseudoCT v3 — MLSC | Run the pseudoCT pipeline on MLSC using a compiled MATLAB R2010b backend. |
| Standard Processing | `local-current` | PseudoCT v3 — Local | Run the pseudoCT pipeline on this computer using a chosen MATLAB version. Results may vary. |
| MPRAGE-only Processing | `local-mprage-only` | MPRAGE-only — Local | Generate a NIfTI-only pseudoCT from MPRAGE alone on this computer. No UMAP required. |
| MPRAGE-only Processing | `mlsc-mprage-only` | MPRAGE-only — MLSC | Generate a NIfTI-only pseudoCT from MPRAGE alone on MLSC. No UMAP required. |
| Legacy Processing | `local-legacy` | PseudoCT v2 (Aether) — Local | Run the original v2 pipeline on this computer for comparison with older studies. |
| Legacy Processing | `mlsc-legacy` | PseudoCT v2 (Aether) — MLSC | Run the original v2 pipeline on MLSC for comparison with older studies. |
| Legacy Processing | `launchpad-legacy` | PseudoCT v2 (Aether) — Launchpad | Run the original v2 pipeline on Launchpad for comparison with older studies. |

The two MPRAGE-only profiles use MPRAGE only, require no UMAP, and produce NIfTI only. All three legacy Aether profiles remain selectable under Legacy Processing; site resources for `launchpad-legacy` may be unavailable. Missing or invalid MLSC runtime/artifact requirements fail closed; selection does not silently fall back to Local or a historical profile.

The deprecated `mlsc` alias maps to `mlsc-legacy`; the deprecated `launchpad` alias is rejected. Use the canonical `launchpad-legacy` key, not that alias.

The development profile is available only by explicit canonical key, not in the routine selector.

The standard workflow uses MPRAGE and its UMAP reference and produces NIfTI and DICOM outputs. Remote credentials are used transiently for a run.

The profile summary preserves the canonical profile ID even when it also shows a display name. Submitter MATLAB and configured scientific paths/settings are distinct from executor facts. “Selected … (configured),” configured paths, scheduler requests, and configured PCA order describe settings—not proof of execution. The pre-dispatch summary does not confirm the actual executor/runtime or runtime options. Requested aliasing/recentering are listed separately from confirmation; because no per-stage confirmation is recorded, those operations are “Not confirmed.” Actual MLSC scheduler and local-finalization outcomes appear only when current-run lifecycle evidence is available. Executor host, CPU, runtime, and build remain unknown unless an actual record proves them; “Not confirmed”/“Not recorded” is not evidence of absence or success. The accepted job 10515471 documents its supplied R2010b Compiler 4.14/MCR 7.14 runtime and output finalization, but does not establish unreported host, CPU, or build details. Executor-side provenance reporting is implemented on a best-effort basis; live sidecar delivery has not been independently confirmed.

Center Standard MLSC resolves its bundled files from the installed version's `<version>/compiled/` directory. Explicit artifact-root/record overrides are advanced options for controlled setups; missing or invalid bundle files fail closed without substituting another profile.

## Inputs and outputs

For DICOM, select the first MPRAGE series file in `<subject>/MR/MPRAGE/`; the corresponding reference is normally discovered in `<subject>/MR/UMAP/`. A preprocessed `.nii` or `.nii.gz` MPRAGE can be provided under `<subject>/MR_PET/`. The standard workflow writes `MR_PET/att_map.nii`, a fusion QC TIFF, logs and a profile summary, and the final DICOM series under `MR/pseudo_muMAP/`. Inspect the QC image and final volume before use. Detailed steps are in the [User Guide](https://mscipio.github.io/pseudoCT_standalone/help/).
