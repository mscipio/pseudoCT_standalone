# Installation and requirements

## Martinos deployment

Martinos users should use the centrally provisioned installation at `/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/`. Add the `pseudoCT_standalone-latest` deployment directory to MATLAB's path; for a numbered installed version, add its bundled `source/` directory. Run `run_pseudo_CT` from a convenient working directory. Keep MATLAB open during processing and, for remote jobs, monitoring and finalization. See the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/) for input layout, step-by-step use, outputs, and QC.

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
% or: addpath('/path/to/pseudoCT_standalone-<version>/source')
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

Verified versions include MATLAB R2010b minimum for local/legacy paths and R2026a Update 2 with the version-specific MCR for building/running the MLSC CURRENT backend. The aliasing/recentering facade requires R2019+.

## Profiles

The selector offers five Recommended profiles:

| Key | Workflow | Typical use |
|---|---|---|
| `local-current` | Current MATLAB source, local | Recommended routine workflow |
| `mlsc-current` | Current MATLAB source, MLSC/Slurm | Remote standard workflow; installed bundled backend and provisioned resources required |
| `local-legacy` | Legacy v2.0 compiled backend (Aether lineage), local | When the legacy backend is required |
| `mlsc-legacy` | Legacy v2.0 compiled backend, MLSC/Slurm | Remote legacy workflow |
| `launchpad-legacy` | Legacy v2.0 compiled backend, Launchpad | Selectable availability; provisioned Launchpad resources required |

Three profiles are under Specialized / Custom and are not for routine use:

| Key | Workflow |
|---|---|
| `local-mprage-only` | Local MPRAGE-only, NIfTI output |
| `mlsc-mprage-only` | MLSC MPRAGE-only, NIfTI output |
| `devel` | Development workflow |

The standard workflow uses MPRAGE and its UMAP reference and produces NIfTI and DICOM outputs. MPRAGE-only profiles do not require UMAP and produce NIfTI only. `mlsc` is a deprecated alias for `mlsc-legacy`; deprecated Launchpad keys are unsupported. Remote credentials are used transiently for a run.

For the bundled MLSC CURRENT backend, normal installations resolve files from the installed version's `<version>/compiled/` directory. Users should not need path overrides. Explicit artifact-root/record overrides are advanced options for exceptional controlled setups; the bundle is validated and missing/invalid files fail closed rather than falling back elsewhere.

## Inputs and outputs

For DICOM, select the first MPRAGE series file in `<subject>/MR/MPRAGE/`; the corresponding reference is normally discovered in `<subject>/MR/UMAP/`. A preprocessed `.nii` or `.nii.gz` MPRAGE can be provided under `<subject>/MR_PET/`. The standard workflow writes `MR_PET/att_map.nii`, a fusion QC TIFF, logs and a profile summary, and the final DICOM series under `MR/pseudo_muMAP/`. Inspect the QC image and final volume before use. Detailed steps are in the [User Guide](https://mscipio.github.io/pseudoCT_standalone/help/).
