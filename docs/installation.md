# Installation and requirements

## Martinos deployment

Martinos users should use the centrally provisioned installation at `/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/`. Add the installation root (`pseudoCT_standalone-latest` or a numbered version directory) to MATLAB's path. Run `run_pseudo_CT` from a convenient working directory. Keep MATLAB open during processing and, for remote jobs, monitoring and finalization. See the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/) for input layout, step-by-step use, outputs, and QC.

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
% or pin a numbered installation: addpath('/path/to/pseudoCT_standalone-<version>')
run_pseudo_CT
```

## External installations

The v3.2.0-rc2 standalone archive candidate uses the installation root `pseudoCT_standalone-3.2.0-rc2/`. Add the extracted installation root to the MATLAB path and run `run_pseudo_CT`; the selector source and bundled MLSC compiled files resolve from that root, with the compiled payload under `compiled/`. Opening the selector does not require a `/usr/pubsw/shared` symlink or a shared installation. The candidate archive does not claim to bundle all scientific processing resources; separately provisioned resources below remain required where applicable. The development checkout now also contains locally staged dependency candidates under `external/`, but those local copies are not public redistribution clearance and are not evidence that an archive contains them. v3.2.0-rc2 is a source/profile correction, not a new compiled scientific payload, and no deployment is claimed.

The v3.1.1 archive had a layout limitation: its files were wrapped under `source/`, so the extracted archive root was not the installation root expected by `run_pseudo_CT` and `src/`. The v3.2.0-rc1 archive fixed that layout by placing the launcher, `src/`, `docs/`, and bundled `compiled/` payload directly under its version root; the rc2 candidate retains this layout under `pseudoCT_standalone-3.2.0-rc2/`.

```matlab
addpath('/path/to/pseudoCT_standalone-3.2.0-rc2')
run_pseudo_CT
```

This is not a self-contained software installation. MATLAB and compatible resources are required; local staged candidates in the development checkout do not replace site runtime services or establish redistribution rights:

- SPM8 and the pseudoCT atlas images and SPM batch templates (`spm_root`, `atlas_root`).
- The standalone DICOM-to-NIfTI converter (`d2n_root`).
- FreeSurfer through the selected profile's normalization environment command; `nmr-stable53` is the environment-script label, and the executable release was not independently verified.
- For local/current preprocessing, the standalone aliasing/recentering tool (`aliasing_root`). Aliasing correction and recentering are independent; requested operations must complete or the subject stops before normalization.
- For remote profiles, the relevant cluster/Launchpad runtime and provisioned resources. MLSC use also needs a valid cluster account; MATLAB remains open while jobs are monitored and finalized.

Some candidate source/resource trees are locally staged under `external/` for development and evidence collection; that local staging is separate from the release archive and from public redistribution clearance. Martinos profiles provide site-specific defaults. Outside that environment, configure the paths in the selected profile under `src/config/profiles/` for compatible installations. Resource validation occurs at startup where applicable; FreeSurfer is checked when normalization runs.

MATLAB R2010b is the selector's minimum supported release. The current-lineage **PseudoCT v3 — MLSC** and **PseudoCT v3 — Local** workflows use the same current-science payload compiled with MATLAB R2010b / Compiler 4.14 for MCR 7.14; local MATLAB coordinates preparation, external normalization, and finalization but does not execute an interpreted current-science fallback. This is not the historical Aether v2 implementation. **Legacy Processing** denotes historical compatibility and requires a MATLAB R2010b host. R2026a comparison records are a separate runtime path.

## Profiles

The selector groups choices under **Standard Processing**, **MPRAGE-only Processing**, and **Legacy Processing**. Selector labels do not change the canonical profile identities shown in summaries or used for configuration.

| Section | Canonical ID | Selector label | Selector description |
|---|---|---|---|
| Standard Processing | `mlsc-current` | PseudoCT v3 — MLSC | Run the pseudoCT pipeline on MLSC using a compiled MATLAB R2010b backend. |
| Standard Processing | `local-current` | PseudoCT v3 — Local | Run the pseudoCT workflow locally using the shared compiled current-science payload. |
| MPRAGE-only Processing | `local-mprage-only` | MPRAGE-only — Local | Generate a NIfTI-only pseudoCT from MPRAGE alone on this computer. No UMAP required. |
| MPRAGE-only Processing | `mlsc-mprage-only` | MPRAGE-only — MLSC | Generate a NIfTI-only pseudoCT from MPRAGE alone on MLSC. No UMAP required. |
| Legacy Processing | `local-legacy` | PseudoCT v2 (Aether) — Local | Run the original v2 pipeline on this computer for comparison with older studies. |
| Legacy Processing | `mlsc-legacy` | PseudoCT v2 (Aether) — MLSC | Run the original v2 pipeline on MLSC for comparison with older studies. |
| Legacy Processing | `launchpad-legacy` | PseudoCT v2 (Aether) — Launchpad | Run the original v2 pipeline on Launchpad for comparison with older studies. |

The two MPRAGE-only profiles use MPRAGE only, require no UMAP, and produce NIfTI only. `mlsc-mprage-only` uses the current-lineage R2010b compiled artifact and the same artifact-root override contract as `mlsc-current`; only the input, output, and GUI policies differ. Missing or invalid current MLSC runtime/artifact requirements fail closed and never select a legacy Aether backend. All three legacy Aether profiles remain selectable under Legacy Processing for historical compatibility; each requires a MATLAB R2010b host, and site resources for `launchpad-legacy` may be unavailable.

The deprecated `mlsc` alias maps to `mlsc-legacy`; the deprecated `launchpad` alias is rejected. Use the canonical `launchpad-legacy` key, not that alias.

The development profile is available only by explicit canonical key, not in the routine selector.

The standard workflow uses MPRAGE and its UMAP reference and produces NIfTI and DICOM outputs. Validation resolves the explicit per-subject inputs locally without authentication; submit revalidates the resolved job before authenticating. MLSC accepts an optional exact group account, defaulting to the first account returned for the user. Credentials are consumed from a secure single-use handoff only at submit; Launchpad retains its existing SSH/PBS behavior.

The profile summary preserves the canonical profile ID even when it also shows a display name. Submitter MATLAB and configured scientific paths/settings are distinct from executor facts. “Selected … (configured),” configured paths, scheduler requests, and configured PCA order describe settings—not proof of execution. The pre-dispatch summary does not confirm the actual executor/runtime or runtime options. Requested aliasing/recentering are listed separately from confirmation; because no per-stage confirmation is recorded, those operations are “Not confirmed.” Actual MLSC scheduler and local-finalization outcomes appear only when current-run lifecycle evidence is available. Executor host, CPU, runtime, and build remain unknown unless an actual record proves them; “Not confirmed”/“Not recorded” is not evidence of absence or success. The accepted job 10515471 documents its supplied R2010b Compiler 4.14/MCR 7.14 runtime and output finalization, but does not establish unreported host, CPU, or build details. Executor-side provenance reporting is implemented on a best-effort basis; live sidecar delivery has not been independently confirmed.

Both current MLSC profiles resolve their shared bundled files from the installed version's `<version>/compiled/` directory. Explicit artifact-root/record overrides are advanced options for controlled setups; missing or invalid bundle files fail closed without substituting another profile or implementation.

For the standalone command-line interface, request/result schemas, one-time
credential handoff, invocation examples, and exit/evidence semantics, see
[Headless CLI](headless-cli.md). The interactive selector and deployed
defaults-MAT workflow are unchanged.

## Inputs and outputs

For DICOM, select the first MPRAGE series file in `<subject>/MR/MPRAGE/`; the corresponding reference is normally discovered in `<subject>/MR/UMAP/`. A preprocessed `.nii` or `.nii.gz` MPRAGE can be provided under `<subject>/MR_PET/`. The standard workflow writes `MR_PET/att_map.nii`, a fusion QC TIFF, logs and a profile summary, and the final DICOM series under `MR/pseudo_muMAP/`. Inspect the QC image and final volume before use. Detailed steps are in the [User Guide](https://mscipio.github.io/pseudoCT_standalone/help/).

## Development and package layout

The agreed distribution uses one interpreted MATLAB orchestration layer shared by GUI and headless CLI, one shared compiled current-science implementation for local-current and MLSC-current, and an immutable historical payload. The exact package-root entries are:

- `bin/`
- `orchestration/`
- `compiled/legacy-v2.0.0/`
- `compiled/current/`
- `external/`
- `manifests/`
- `README.md`

The development checkout is organized under `src/{api,cli,gui,orchestration,backends,science,config,io,qc}`, `external/`, `compiled/`, `scripts/`, and `tests/`. The distribution target remains a separate package projection; package-level dependency/provenance manifests belong in `manifests/`, while current build/resource manifests stay paired with `compiled/current/`. The current payload was rebuilt after the shared-orchestration changes with MATLAB R2010b/Compiler 4.14; its recorded source commit/build provenance is the build-time record. The cleanup described here does not rebuild or modify that payload. Obsolete top-level compiled build-output contents and root build/log artifacts were removed; empty legacy directory shells may remain in development checkouts. The canonical `compiled/current/` payload and historical `compiled/legacy-v2.0.0/` remain separate and unchanged.

Dependency ownership follows the checked-in call sites and the intended two-layer boundary:

The source-only QC colormap resolver correction points to `src/qc/`; no rebuild was performed for that change, so the installed `compiled/current/` artifact remains the recorded T032 payload.

- **Interpreted orchestration runtime:** MATLAB interpreter and Java runtime are external system requirements. The source SSH2 transport required by MLSC/Launchpad is at `external/ssh2_v2_m1_r5/`; the move preserved its exact recorded source-tree hash. DICOM input conversion is conditional: `src/orchestration/pseudo_CT_run_lifecycle.m` calls `dcm2nii` for MPRAGE input before compiled scientific processing. The staged `dcm2nii.m` compatibility facade delegates to `dicom2nifti.api.run`; its DICOM route calls SPM DICOM functions in the interpreter. That conversion route requires SPM8 r6313 when used. Current `setup_pseudo_CT_paths.m` conservatively validates and adds SPM plus the three `src/science/overrides/` files for every `purpose='run'`, including a run whose input is already NIfTI; this is the present setup requirement, not evidence that NIfTI input invokes conversion. Setup initially selects the overrides ahead of SPM. During DICOM conversion, the pinned converter API adds configured SPM8 at path-begin; therefore the effective `spm_dicom_convert` is `external/spm8-r6313`, while initial `which` resolution remains the established override. This preserves prior converter behavior and is distinct from the overrides' compile-input role. Converter source/API path precedence was previously exercised; full conversion remains limited to the recorded prior synthetic smoke evidence.
- **Scientific build inputs:** `scripts/build_mlsc_current.m` names compiler source under `src/science/current`, `src/science/shared`, `src/science/legacy`, `src/science/overrides`, `src/io`, and `src/qc`; it pins SPM inputs, `correct_aliasing` v0.4.0, and `dicom2nifti` source. The current payload and paired manifests were rebuilt after the shared-orchestration changes with MATLAB R2010b/Compiler 4.14; the lock records their current identity. This cleanup performs no build. Runtime setup adds only orchestration/backend/config/I/O/QC code paths and conditionally adds DICOM resources; compiled current science is not added as an interpreted fallback, and runtime setup does not require/add `correct_aliasing`.
- **Compiled scientific runtime data:** `external/Batch_atlas/` is read through the current job/resource manifests and validated by the compiled payload. The separate historical atlas tree remains under `compiled/legacy-v2.0.0/Batch_atlas/`; the two trees are not interchangeable.
- **External processing and system services:** FreeSurfer is site-provisioned, not included. MLSC invokes `env -u LD_LIBRARY_PATH MLSC_FREESURFER_ENV=<configured-env> MLSC_INPUT_NAME=<input> MLSC_NORMALIZED_NAME=<normalized-output> tcsh -f -c 'source "$MLSC_FREESURFER_ENV"; mri_normalize "$TMPDIR/$MLSC_INPUT_NAME" "$TMPDIR/$MLSC_NORMALIZED_NAME"'`. MATLAB Compiler is build-time only; MATLAB interpreter, Java, MCR 7.14, Slurm/PBS interfaces, tcsh/bash, and remote SSH services have distinct runtime roles and are not interchangeable or bundled by this inventory.
- **Explicit exclusions:** the unused root `imgaussian/` development candidate contents and root `vers/` source files were removed after source/path reference checks; their empty directory shells may remain in development checkouts, and neither is an active runtime dependency. `src/science/overrides/` is different: the builder requires and includes its three files, and interpreted setup validates/adds all three ahead of SPM. The DICOM API path mutation makes the configured SPM8 `spm_dicom_convert` effective for converter input preparation; this does not establish that `spm_vol_nifti.m` or `spm_preproc_write8.m` participate in that conversion. `src/science/overrides/` is a narrow override set, not a second SPM package.

The current checkout has `bin/`, both compiled payload roots, and `external/`, but does not yet have package-root `orchestration/` or `manifests/`; `src/` remains the development source location. The dependency lock records the present root boundary and hashes for `bin/`, current/legacy payloads, staged external trees, `src/science/overrides/`, and SSH2. Local staging is not a release archive: public packaging remains blocked until every dependency's identity, provenance, complete transitive notices, compatibility, and redistribution rights are cleared. No runtime flow, code path, or scientific algorithm is changed by this package/documentation record.
