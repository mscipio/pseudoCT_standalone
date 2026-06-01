# pseudo-CT Package — AGENTS.md

## Purpose

MATLAB/SPM8 pipeline that generates pseudo-CT attenuation maps from Biograph mMR MPRAGE inputs. Two execution paths: local (editable MATLAB) and Launchpad (legacy compiled backend via SSH).

## Entry Points

- `run_pseudo_CT_local.m` — local MATLAB/SPM pipeline
- `run_pseudo_CT_launchpad.m` — delegates atlas processing to compiled Launchpad backend over SSH

Both accept: `'batch'` (multi-select GUI), a cell/char list of MPRAGE filenames, or no args (single-subject GUI). Example: `run_pseudo_CT_local('batch')`.

## Repo Layout

| Path | Role |
|---|---|
| `run_pseudo_CT_local.m` / `run_pseudo_CT_launchpad.m` | User-facing entry points; add dependencies to path then dispatch |
| `src/` | Project MATLAB source — config, core, io, remote, launchpad, qc, ui |
| `src/config/` | Defaults: `defaults_pseudo_CT.m` (local) and `defaults_pseudo_CT_launchpad.m` (Launchpad) |
| `src/config/fs_setenv_530_from_launchpad.sh` | FreeSurfer 5.3 env setup, referenced by defaults |
| `Batch_atlas/` | Atlas NIfTI images + SPM batch `.mat` templates for segmentation/DARTEL |
| `vers/` | Local overrides for `spm_vol_nifti`, `spm_preproc_write8`, `spm_dicom_convert` |
| `spm8-r6313/` | Bundled SPM8 (full tree) |
| `ssh2_v2_m1_r5/` | SSH/SCP toolbox for Launchpad path |
| `imgaussian/` | External image filtering (MEX/C) |

## Dependencies & Environment

- **MATLAB** with SPM8 (bundled)
- **FreeSurfer 5.3** — `fs_setenv_530_from_launchpad.sh` points to `/usr/local/freesurfer/stable5_3_0`. For local execution, `defaults_pseudo_CT.m` sets `HOSTNAME = '127.0.0.1'` to run FS commands on localhost.
- **Java SSH library** — `ganymed-ssh2-build250.jar` in `Batch_atlas/`; added to javaclasspath automatically by `atlas_based_attenuation_map.m`.

## Execution Model

### Local Path

1. `run_pseudo_CT_local` adds `src/`, `spm8-r6313/`, `vers/`, `imgaussian/`, `ssh2_v2_m1_r5/` to MATLAB path via `genpath`. Calls `clear spm_vol_nifti spm_preproc_write8` then `rehash` to override stock SPM functions with `vers/` versions.
2. Collects jobs (GUI or batch), creates `MR_PET/`, `MR_PET/tmp/`, `MR/pseudo_muMAP/` dirs.
3. For each subject: DICOM→NIfTI, FreeSurfer normalization (via SSH or local), SPM new segment + DARTEL + inverse warp, CT→att_map, NIfTI→DICOM, QC image, cleanup `MR_PET/tmp/`.

### Launchpad Path

Same input/DICOM output layer, but `batch_pseudo_CT_launchpad.m` delegates core atlas processing to a compiled Launchpad app (`Pseudo_CT_launchpad`). Polls for remote completion.

## Key Gotchas

- **`vers/` overrides SPM8 functions** — `spm_vol_nifti.m` and `spm_preproc_write8.m` in `vers/` shadow SPM originals. The entry scripts run `clear spm_vol_nifti spm_preproc_write8; rehash` after path setup.
- **Warning suppression** — both entry points call `warning('off', 'all')` and restore on exit.
- **Output folder discovery** — `pseudo_CT_resolve_output_dirs.m` walks up from the MPRAGE file to find the `MR/` parent. Outputs go to `<subject_root>/MR_PET/` (processing), `<subject_root>/MR_PET/tmp/` (intermediate), `<subject_root>/MR/pseudo_muMAP/` (DICOM).
- **UMAP auto-discovery** — `pseudo_CT_auto_discover_ute_umap.m` looks for `MR/UMAP/*0001.*` or `MR/*UMAP*/*0001.*` relative to the MPRAGE path. Subjects without a detected UMAP are silently skipped in batch mode.
- **Anti-aliasing** — second positional arg controls nose/back aliasing correction. Defaults to `1` in batch/explicit-list modes. In GUI mode, set via checkbox in `load_mr_4_AC.fig`.
- **Defaults are `eval`'d** — `defaults_pseudo_CT.m` and `defaults_pseudo_CT_launchpad.m` use `eval([defstr ';'])`. Setting names must match the variable name in the file (e.g. `'HOSTNAME'`, `'source_command'`).

## Shell Mode & Compiled App

- `run_pseudo_CT_launchpad.m` supports a **deployed (compiled) mode** via `isdeployed`: if called with one arg pointing to a `.mat` defaults file, it loads that instead of hardcoded defaults.
- Local mode has its deployed code path **commented out** (lines 48–59, 86–88, 206–208 in `run_pseudo_CT_local.m`).

## No Tests, No CI

No test framework, CI config, linter, formatter, or typechecker exist. The repo has 3 git commits total. Verification is manual: run the pipeline and check the QC TIFF output.

## Versioning

Code version is hardcoded as `code_version = '2.5'` in `atlas_based_attenuation_map.m:90`. A `Pseudo_CT_AC_Version.txt` is written to the processing dir with full version history.
