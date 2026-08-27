# pseudo-CT Package — AGENTS.md

## Purpose

MATLAB/SPM8 pipeline that generates pseudo-CT attenuation maps from Biograph mMR MPRAGE inputs. Three execution profiles: `local-current` (editable MATLAB), `local-near-parity-r2010b`, and `launchpad` (legacy compiled backend via SSH).

## Entry Points

- `run_pseudo_CT.m` — primary entrypoint with 3 profiles, named arguments, and GUI integration. Profiles: `local-current` (default), `local-near-parity-r2010b`, `launchpad`.

  Call with no arguments to open the profile selector GUI, then the single-subject GUI.
  Call with named arguments for CLI/script mode:
  ```
  run_pseudo_CT()
  run_pseudo_CT('profile', 'local-current')
  run_pseudo_CT('profile', 'launchpad', 'subjects', 'batch')
  run_pseudo_CT('profile', 'local-current', 'subjects', subject_list, 'correct_aliasing', 0)
  ```

  The old entrypoints `run_pseudo_CT_local.m` and `run_pseudo_CT_launchpad.m` have been moved to `deprecated/` and are preserved unmodified for backward compatibility.

## Repo Layout

| Path | Role |
|---|---|
| `run_pseudo_CT.m` | Primary user-facing entry point; dispatches to the selected profile |
| `deprecated/run_pseudo_CT_local.m`, `deprecated/run_pseudo_CT_launchpad.m` | Legacy entry points preserved for backward compatibility |
| `deprecated/automatic_anti_aliasing_nose_2_back.m`, `deprecated/center_subject_in_image.m` | Legacy aliasing/centering implementations, preserved unmodified pending deletion |
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
- **correct_aliasing (local profiles only)** — external standalone at `/usr/pubsw/packages/mrpet/standalone_apps/correct_aliasing/correct_aliasing_standalone-latest`. Path is configured via the `aliasing_root` profile field (required in all 6 profiles by `pseudo_CT_load_profile.m`). `setup_pseudo_CT_paths.m` validates `aliasing_root` in preflight for local profiles only (error id `AliasingRootMissing`), adds it to the MATLAB path with `addpath(..., '-begin')`, and runs `clear correct_aliasing; rehash` after. Launchpad profiles skip this validation and import — aliasing remains delegated to the compiled `Pseudo_CT_launchpad` via `check_aliasing`, unchanged. Requires MATLAB R2019+; local aliasing correction will fail on older releases (e.g. `local-near-parity-r2010b`) if invoked.

## Execution Model

### Local Path

1. `run_pseudo_CT` with a local profile (`local-current` or `local-near-parity-r2010b`) adds `src/`, the selected SPM package, `vers/`, `imgaussian/`, `ssh2_v2_m1_r5/` to MATLAB path via `setup_pseudo_CT_paths`. Calls `pseudo_CT_preflight` before any path mutation to validate all resource dependencies.
2. Collects jobs (GUI or batch), creates `MR_PET/`, `MR_PET/tmp/`, `MR/pseudo_muMAP/` dirs.
3. For each subject: DICOM→NIfTI, FreeSurfer normalization (via SSH or local), SPM new segment + DARTEL + inverse warp, CT→att_map, NIfTI→DICOM, QC image, cleanup `MR_PET/tmp/`.

### Launchpad Path

Same input/DICOM output layer, but `batch_pseudo_CT_launchpad.m` delegates core atlas processing to a compiled Launchpad app (`Pseudo_CT_launchpad`). Polls for remote completion.

## Key Gotchas

- **`vers/` overrides SPM8 functions** — `spm_vol_nifti.m` and `spm_preproc_write8.m` in `vers/` shadow SPM originals. The entrypoint runs `clear spm_vol_nifti spm_preproc_write8; rehash` after path setup.
- **Warning suppression** — the entrypoint calls `warning('off', 'all')` and restores on exit.
- **Output folder discovery** — `pseudo_CT_resolve_output_dirs.m` walks up from the MPRAGE file to find the `MR/` parent. Outputs go to `<subject_root>/MR_PET/` (processing), `<subject_root>/MR_PET/tmp/` (intermediate), `<subject_root>/MR/pseudo_muMAP/` (DICOM).
- **UMAP auto-discovery** — `pseudo_CT_auto_discover_ute_umap.m` looks for `MR/UMAP/*0001.*` or `MR/*UMAP*/*0001.*` relative to the MPRAGE path. Subjects without a detected UMAP are silently skipped in batch mode.
- **Anti-aliasing and centering** — second positional arg controls nose/back aliasing correction. Defaults to `1` in batch/explicit-list modes. In GUI mode, set via checkbox in `load_mr_4_AC.fig`. The external `correct_aliasing` facade owns both alias correction and centering via a file-based API: `correct_aliasing(inputPath, outputPath, 'AliasCorrection', ..., 'Centering', ..., 'Overwrite', ...)`, returning a four-field result `{status, outputs, message, details}` mirroring the `dicom2nifti` pattern. Legacy in-package implementations (`automatic_anti_aliasing_nose_2_back.m`, `center_subject_in_image.m`) are preserved unmodified under `deprecated/` pending deletion.
- **Defaults are `eval`'d** — `defaults_pseudo_CT.m` and `defaults_pseudo_CT_launchpad.m` use `eval([defstr ';'])`. Setting names must match the variable name in the file (e.g. `'HOSTNAME'`, `'source_command'`).
- **Historical output settings** — both defaults use `recenter_before_normalization = 'No'` and `zero_background = 'No'`. Launchpad runs `mri_normalize` first and passes `_normalized.nii`, so recentering is bypassed. Bone reduction remains enabled.
- **New Segment host boundary** — one controlled subject matched the historical New Segment result on legacy PBS E5472/RHEL7/glibc 2.17. Celer R2010 compiled and interpreted runs matched each other but followed a different iterative numerical path. CPU dispatch and system-math effects were not isolated independently; this is not universal parity proof.

## Shell Mode & Compiled App

- `run_pseudo_CT.m` supports a **deployed (compiled) mode** via `isdeployed`: if called with one arg pointing to a `.mat` defaults file, it loads that instead of the default profile configuration. This preserves the existing launchpad deployed mode contract.
- Local mode has its deployed code path handled through the same unified entrypoint (in contrast to the old local entrypoint which had it commented out).

## Testing & CI

**CI** — No GitHub Actions workflow is configured because this private repository cannot provide a MATLAB batch license token to GitHub-hosted runners. Run lint and smoke tests locally before release.

**Lint** — `scripts/run_lint.m` runs MATLAB's built-in `mlint` over `src/`, `vers/`, and the entry script `run_pseudo_CT.m`.

**Smoke tests** — `scripts/run_smoke_tests.m` checks:
- Primary entry script `run_pseudo_CT.m` exists and parses
- Deprecated entry scripts `deprecated/run_pseudo_CT_local.m` and `deprecated/run_pseudo_CT_launchpad.m` exist and parse
- All `src/**/*.m` files parse
- The 3 `vers/` SPM overrides parse
- Key atlas assets exist (`Batch_atlas/TPM.nii`, `ch2.nii`, the 7 `Template_*.nii` DARTEL templates, `Batch_atlas/ganymed-ssh2-build250/ganymed-ssh2-build250.jar`)

**Targeted TDD tests** — `scripts/test_auto_discover_messages.m` is a red-green style test for the `batch-discovery-messages` change. Not wired into CI; run manually when iterating on `pseudo_CT_auto_discover_ute_umap`.

**What is NOT here** — no formal unit-test framework (MOxUnit, `matlab.unittest.TestCase`), no formatter, no typechecker, no coverage tool. `strict_tdd` resolves to `false` in SDD for this project (see `sdd-init-go/pseudo_ct_package_new_for_collab`).

**Manual verification is still required** for end-to-end pipeline runs: the smoke tests cover file/parse integrity, not pipeline output. The QC TIFF is the ground truth.

## Versioning

Code version falls back to `2.6.5` in `atlas_based_attenuation_map.m` and otherwise reads line 1 of `CHANGELOG.md`. A `Pseudo_CT_AC_Version.txt` is written to the processing directory with full version history.
