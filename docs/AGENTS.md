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

  The former entrypoints `run_pseudo_CT_local.m` and `run_pseudo_CT_launchpad.m` are not included in this tree. Use `run_pseudo_CT.m` with an explicit profile instead.

## Repo Layout

| Path | Role |
|---|---|
| `run_pseudo_CT.m` | Primary user-facing entry point; dispatches to the selected profile |
| `deprecated/automatic_anti_aliasing_nose_2_back.m`, `deprecated/center_subject_in_image.m`, `deprecated/convert_dicom_i_2_nii.m` | Legacy helper implementations, preserved unmodified for reference only; not active runtime dependencies |
| `src/` | Project MATLAB source — config, core, io, remote, launchpad, qc, ui |
| `src/config/` | Profile-owned runtime configuration and external resource path setup |
| `src/config/fs_setenv_530_from_launchpad.sh` | FreeSurfer 5.3 environment setup script |
| External `Batch_atlas/` | Atlas NIfTI images + SPM batch `.mat` templates, configured by `atlas_root` |
| `vers/` | Local overrides for `spm_vol_nifti`, `spm_preproc_write8`, `spm_dicom_convert` |
| External `spm8-r6313/` | Deployment-provided SPM8 installation, configured by `spm_root` |
| `ssh2_v2_m1_r5/` | SSH/SCP toolbox for Launchpad path |
| `imgaussian/` | External image filtering (MEX/C) |

## Dependencies & Environment

- **MATLAB** with a compatible externally provisioned SPM8 installation (for
  example `spm8-r6313`); the selected profile's `spm_root` must point to it.
- **Batch atlas resources** — an externally provisioned `Batch_atlas` directory
  containing the atlas NIfTIs and SPM batch templates; the selected profile's
  `atlas_root` must point to it. These resources are not in this repository or
  its release archives.
- **Launchpad deployment (launchpad profiles only)** — the compiled runner, MCR,
  defaults MAT, and remote batch-template directory are provisioned separately
  and configured through `config.launchpad.*`.
- **FreeSurfer 5.3** — `fs_setenv_530_from_launchpad.sh` points to `/usr/local/freesurfer/stable5_3_0`. Local profiles set normalization to localhost; the Launchpad profile uses its configured remote host.
- **Java SSH library** — the Launchpad SSH path uses the bundled custom
  `ganymed-ssh2-m1.jar` under `ssh2_v2_m1_r5/`. `atlas_based_attenuation_map.m`
  may additionally load `ganymed-ssh2-build250.jar` when the external atlas
  bundle provides it.
- **correct_aliasing (local profiles only)** — external standalone at `/usr/pubsw/packages/mrpet/standalone_apps/correct_aliasing/correct_aliasing_standalone-latest`. Path is configured via the `aliasing_root` profile field (required in all 6 profiles by `pseudo_CT_load_profile.m`). `setup_pseudo_CT_paths.m` validates `aliasing_root` in preflight for local profiles only (error id `AliasingRootMissing`), adds it to the MATLAB path with `addpath(..., '-begin')`, and runs `clear correct_aliasing; rehash` after. Launchpad profiles skip this validation and import — aliasing remains delegated to the compiled `Pseudo_CT_launchpad` via `check_aliasing`, unchanged. Requires MATLAB R2019+; local aliasing correction will fail on older releases (e.g. `local-near-parity-r2010b`) if invoked.

## Execution Model

### Local Path

1. `run_pseudo_CT` with a local profile adds `src/`, the configured external SPM package, `vers/`, `imgaussian/`, and `ssh2_v2_m1_r5/` to the MATLAB path via `setup_pseudo_CT_paths`, which validates the configured resources before path setup.
2. Collects jobs (GUI or batch), creates `MR_PET/`, `MR_PET/tmp/`, `MR/pseudo_muMAP/` dirs.
3. For each subject: DICOM→NIfTI, FreeSurfer normalization (via SSH or local), SPM new segment + DARTEL + inverse warp, CT→att_map, NIfTI→DICOM, QC image, cleanup `MR_PET/tmp/`.

### Launchpad Path

Same input/DICOM output layer, but `batch_pseudo_CT_launchpad.m` delegates core atlas processing to a compiled Launchpad app (`Pseudo_CT_launchpad`). Polls for remote completion.

## Key Gotchas

- **`vers/` overrides SPM8 functions** — `spm_vol_nifti.m` and `spm_preproc_write8.m` in `vers/` shadow SPM originals. The entrypoint runs `clear spm_vol_nifti spm_preproc_write8; rehash` after path setup.
- **Warning suppression** — the entrypoint calls `warning('off', 'all')` and restores on exit.
- **Output folder discovery** — `pseudo_CT_resolve_output_dirs.m` walks up from the MPRAGE file to find the `MR/` parent. Outputs go to `<subject_root>/MR_PET/` (processing), `<subject_root>/MR_PET/tmp/` (intermediate), `<subject_root>/MR/pseudo_muMAP/` (DICOM).
- **UMAP auto-discovery** — `pseudo_CT_auto_discover_ute_umap.m` looks for `MR/UMAP/*0001.*` or `MR/*UMAP*/*0001.*` relative to the MPRAGE path. Subjects without a detected UMAP are silently skipped in batch mode.
- **Anti-aliasing and centering** — second positional arg controls nose/back aliasing correction. Defaults to `1` in batch/explicit-list modes. In GUI mode, set via checkbox in `load_mr_4_AC.fig`. The external `correct_aliasing` facade owns both alias correction and centering via a file-based API: `correct_aliasing(inputPath, outputPath, 'AliasCorrection', ..., 'Centering', ..., 'Overwrite', ...)`, returning a four-field result `{status, outputs, message, details}` mirroring the `dicom2nifti` pattern. Legacy in-package implementations are preserved unmodified under `deprecated/` for reference only and are not on the active MATLAB path.
- **Profile fields are authoritative** — resource paths and behavior-changing settings come from the selected profile in `src/config/profiles/`; configure external resource paths there rather than relying on repository-relative directories.
- **Historical output settings** — both defaults use `recenter_before_normalization = 'No'` and `zero_background = 'No'`. Launchpad runs `mri_normalize` first and passes `_normalized.nii`, so recentering is bypassed. Bone reduction remains enabled.
- **New Segment host boundary** — one controlled subject matched the historical New Segment result on legacy PBS E5472/RHEL7/glibc 2.17. Celer R2010 compiled and interpreted runs matched each other but followed a different iterative numerical path. CPU dispatch and system-math effects were not isolated independently; this is not universal parity proof.

## Shell Mode & Compiled App

- `run_pseudo_CT.m` supports a **deployed (compiled) mode** via `isdeployed`: if called with one arg pointing to a `.mat` defaults file, it loads that instead of the default profile configuration. This preserves the existing launchpad deployed mode contract.
- Local mode has its deployed code path handled through the same unified entrypoint (in contrast to the old local entrypoint which had it commented out).

## Testing & CI

**CI** — No GitHub Actions workflow is configured because this private repository cannot provide a MATLAB batch license token to GitHub-hosted runners. Run lint and smoke tests locally before release.

**Lint** — `scripts/run_lint.m` runs MATLAB's built-in `mlint` over `src/` and `vers/`. The smoke suite separately discovers and parses `run_pseudo_CT.m` and the maintainer scripts.

**Smoke tests** — `scripts/run_smoke_tests.m` checks:
- Primary entry script `run_pseudo_CT.m` exists and parses
- All `src/**/*.m` files parse
- The 3 `vers/` SPM overrides parse
- Maintainer/comparator scripts under `scripts/` are discovered from the script directory and parse
- The profile-authority check confirms the three retained `deprecated/` helpers and the absence of the obsolete legacy entrypoints

**Maintainer Makefile** — `deprecated/Makefile` retains only `lint`, `test`, and `tag` targets. Invoke it as `make -f deprecated/Makefile <target>` from the repository root, or pass its absolute path from any working directory; it derives the repository root from its own location. It does not build release archives. Release archives use the repository's `.gitattributes` export-ignore policy.

**Repository versus release archives** — `scripts/`, `docs/`, `deprecated/`, and tracked maintainer metadata remain on GitHub for maintenance and reference, but are excluded from v2.8.3 release archives. Deployable runtime paths, `README.md`, and `CHANGELOG.md` remain included. The external SPM8 and `Batch_atlas` prerequisites are not included, so the release is not self-contained.

**Targeted TDD tests** — `scripts/test_auto_discover_messages.m` is a red-green style test for the `batch-discovery-messages` change. Not wired into CI; run manually when iterating on `pseudo_CT_auto_discover_ute_umap`.

**What is NOT here** — no formal unit-test framework (MOxUnit, `matlab.unittest.TestCase`), no formatter, no typechecker, no coverage tool. `strict_tdd` resolves to `false` in SDD for this project (see `sdd-init-go/pseudo_ct_package_new_for_collab`).

**Manual verification is still required** for end-to-end pipeline runs: the smoke tests cover file/parse integrity, not pipeline output. The QC TIFF is the ground truth.

## Versioning

Code version falls back to `2.8.3` in `atlas_based_attenuation_map.m` and otherwise reads line 1 of `CHANGELOG.md`. A `Pseudo_CT_AC_Version.txt` is written to the processing directory with full version history.
