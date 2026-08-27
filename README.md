# Standalone Pseudo-CT Package

Maintained by Michele Scipioni, PhD  
mscipioni@mgh.harvard.edu  
Last updated: July 28, 2026.

If you use this method, or parts of it, please, quote this paper:
>D. Izquierdo-Garcia, A.E. Hansen, S. Förster, D. Benoit, S. Schachoff, S. Fürst, K.T. Chen, D.B. Chonde, and C. Catana.
>An SPM8-based Approach for Attenuation Correction Combining Segmentation and Non-rigid Template Formation: Application to Simultaneous PET/MR Brain Imaging. JNM. 2014. Nov;55(11):1825-30.

This package provides a unified entrypoint `run_pseudo_CT.m` with three execution profiles:

- `local-current` (default): runs the editable MATLAB/SPM pipeline with your system-installed MATLAB.
- `local-near-parity-r2010b`: local pipeline pinned to near-R2010b (7.11) numerical parity for consistent optimizer results across MATLAB versions.
- `launchpad`: stages the subject to Launchpad and runs the legacy compiled `Pseudo_CT_launchpad` backend.

The former entrypoints `run_pseudo_CT_local.m` and `run_pseudo_CT_launchpad.m` are not included in this tree. Use the unified entrypoint with an explicit profile instead; the retained files under `deprecated/` are legacy helpers for reference only.

## Top-Level Layout

- `run_pseudo_CT.m`: primary user-facing entry point.
- `deprecated/`: legacy helper implementations preserved for reference only; not active runtime dependencies and excluded from release archives.
- `src/`: project-owned MATLAB source files grouped by function.
- External `Batch_atlas/`: atlas images and SPM batch templates used by the pseudo-CT pipeline; configured through `atlas_root` and not included here.
- External `spm8-r6313/`: deployment-provided SPM8 installation; configured through `spm_root` and not included here.
- `vers/`: local SPM overrides required by this pipeline.
- `ssh2_v2_m1_r5/`: bundled SSH/SCP toolbox used by the Launchpad path.
- `imgaussian/`: external image filtering dependency.

## External Prerequisites and Provisioning

This repository and its release archives are **not self-contained**. They do not
include or distribute the atlas data/templates in `Batch_atlas/` or an SPM8 tree
such as `spm8-r6313/`. Provision compatible external resources before running the
pipeline:

- Provision the required atlas NIfTI files and SPM batch templates, then set the
  selected profile's `config.atlas_root` to that external `Batch_atlas` directory.
  The directory must contain the templates and atlas files used by the selected
  workflow (including `ch2.nii`, `TPM.nii`, `Template_*.nii`, the batch `.mat`
  files, and the `*Atlas*.nii` files).
- Provision a compatible SPM8 installation and set the selected profile's
  `config.spm_root` to its absolute path. The checked-in profiles show the site
  defaults; deployment-specific paths may be substituted while preserving the
  profile's MATLAB/SPM compatibility requirements.
- For `launchpad`, provision the separate remote Launchpad deployment and set
  `config.launchpad.runner`, `config.launchpad.mcr_root`,
  `config.launchpad.defaults_mat`, and `config.launchpad.batch_templates` to the
  corresponding external files/directories. `batch_templates` must resolve to the
  remote provisioned atlas/template directory.

`setup_pseudo_CT_paths` checks the configured resource directories and required
Launchpad files before changing the MATLAB path. A missing external prerequisite
therefore fails during setup; it is not supplied by cloning this repository or
downloading a release archive.

## Source Tree

- `src/config/`: runtime defaults and environment setup.
  Contains the profile files, resource path setup, and the local FreeSurfer setup script.
- `src/core/`: pseudo-CT processing logic.
  Contains atlas warping, attenuation-map generation, masking, aliasing correction, and subject centering.
- `src/io/`: input/output helpers.
  Contains DICOM to NIfTI conversion, final DICOM writing, output-folder resolution, and cleanup helpers.
- `src/ui/`: interactive MATLAB UI helpers.
  Contains the file-selection GUIDE dialog and password dialog.
- `src/remote/`: SSH/SCP and remote normalization helpers.
  Contains the login shim plus wrappers for remote command execution and file transfer.
- `src/launchpad/`: Launchpad queue orchestration.
  Contains job submission, job polling, and the standalone Launchpad batch wrapper.
- `src/qc/`: quick-look quality-control utilities.
  Contains the overlay renderer and color map used for fused MR/pseudo-CT QC images.

## Execution Paths

### Local (profiles: `local-current`, `local-near-parity-r2010b`)

`run_pseudo_CT.m` with a local profile runs the editable MATLAB/SPM pipeline. It sets up the MATLAB path via `setup_pseudo_CT_paths`, collects the subject jobs, runs `atlas_based_attenuation_map`, then writes the final DICOM pseudo-muMAP output.

Both local profiles support interactive, batch, and explicit-list usage:

- `run_pseudo_CT()` — opens the profile selector GUI, then the single-subject selection dialog.
- `run_pseudo_CT('profile', 'local-current')` — skips the profile selector and opens the single-subject dialog.
- `run_pseudo_CT('profile', 'local-current', 'subjects', 'batch')` — opens a multi-select file picker for MPRAGE files and auto-discovers each subject's UMAP reference.
- `run_pseudo_CT('profile', 'local-current', 'subjects', subject_list)` — accepts a cell array or char matrix of MPRAGE filenames and processes them sequentially.

Examples:

```matlab
run_pseudo_CT()
run_pseudo_CT('profile', 'local-current')
run_pseudo_CT('profile', 'local-current', 'subjects', 'batch')
run_pseudo_CT('profile', 'local-current', 'subjects', 'batch', 'correct_aliasing', 0)

subject_list = {
  '/path/to/subj1/MR/MEMPRAGE/file1.IMA'
  '/path/to/subj2/MR/MEMPRAGE/file1.IMA'
};
run_pseudo_CT('profile', 'local-current', 'subjects', subject_list)
run_pseudo_CT('profile', 'local-current', 'subjects', subject_list, 'correct_aliasing', 0)
```

Near-parity profile:

```matlab
run_pseudo_CT('profile', 'local-near-parity-r2010b')
run_pseudo_CT('profile', 'local-near-parity-r2010b', 'subjects', 'batch')
```

When `local-near-parity-r2010b` is selected on a MATLAB release other than R2010b, a warning is shown that results may differ from expected near-parity output, and the runtime guard is bypassed.

### NIfTI Input

All profiles accept **pre-converted NIfTI files** in place of raw DICOM. Place
the NIfTI in the subject's `MR_PET/` folder and pass its path to the `subjects`
argument. The UMAP reference is discovered from the sibling `MR/` directory:

```
<subject_root>/
├── MR/
│   ├── UMAP/         ← reference UMAP (for DICOM output geometry)
│   └── ...
└── MR_PET/
    └── mprage.nii    ← input NIfTI (processed in place)
```

Example:

```matlab
run_pseudo_CT('profile', 'local-current', 'subjects', ...
    {'/path/to/subject/MR_PET/mprage.nii'})
```

The NIfTI is copied into `MR_PET/tmp/mprage.nii` during staging, preserving the
original input file. All pipeline stages (UMAP discovery, DICOM output, QC,
promotion) work identically to the DICOM input path.

For localhost execution, temporary FreeSurfer normalization staging happens under each subject's own `MR_PET/tmp` folder rather than under the hardcoded `host_folder` path in the defaults template. On successful completion, the final NIfTI/QC/version artifacts are promoted back into `MR_PET` and the `MR_PET/tmp` folder is removed.

### Launchpad (profile: `launchpad`)

`run_pseudo_CT.m` with the `launchpad` profile uses the same local input selection and final DICOM output layer, but the core atlas processing is delegated to the legacy compiled Launchpad application through the queue helpers in `src/launchpad/`.

Launchpad mode supports interactive, batch, and explicit-list usage:

- `run_pseudo_CT('profile', 'launchpad')` — skips the profile selector and opens the single-subject selection dialog, then SSH login.
- `run_pseudo_CT('profile', 'launchpad', 'subjects', 'batch')` — opens a multi-select file picker for MPRAGE files, auto-discovers each subject's UMAP reference, and submits the batch through Launchpad.
- `run_pseudo_CT('profile', 'launchpad', 'subjects', subject_list)` — accepts a cell array or char matrix of MPRAGE filenames and processes them sequentially through the Launchpad backend.

Examples:

```matlab
run_pseudo_CT('profile', 'launchpad')
run_pseudo_CT('profile', 'launchpad', 'subjects', 'batch')
run_pseudo_CT('profile', 'launchpad', 'subjects', 'batch', 'correct_aliasing', 0)

subject_list = {
  '/path/to/subj1/MR/MEMPRAGE/file1.IMA'
  '/path/to/subj2/MR/MEMPRAGE/file1.IMA'
};
run_pseudo_CT('profile', 'launchpad', 'subjects', subject_list)
run_pseudo_CT('profile', 'launchpad', 'subjects', subject_list, 'correct_aliasing', 0)
```

Note: In GUI mode (`run_pseudo_CT()` with no arguments), the profile selector dialog is shown first, enabling GUI-based profile choice before subject selection.

## Documentation

Detailed pipeline documentation is maintained in the repository's `docs/` directory.
That directory is intentionally excluded from release archives, so the links below
use GitHub URLs rather than archive-relative paths.

- **[Pipeline Stages: Local](https://github.com/mscipio/pseudoCT_standalone/blob/main/docs/pipeline-local.md)** — step-by-step flow for
  local profiles (`local-current`, `local-near-parity-r2010b`): which files are
  created at each stage and which tools are used.
- **[Pipeline Stages: Launchpad](https://github.com/mscipio/pseudoCT_standalone/blob/main/docs/pipeline-launchpad.md)** — step-by-step flow
  for the `launchpad` profile: local I/O layer, remote compiled-backend internals,
  and post-processing.
- **[Numerical Parity Assessment](https://github.com/mscipio/pseudoCT_standalone/blob/main/docs/parity-assessment.md)** — controlled
  comparison between local profiles and the legacy Launchpad backend: what
  diverges, why, and the practical impact on PET attenuation correction.
- **[Legacy Launchpad Parity](https://github.com/mscipio/pseudoCT_standalone/blob/main/docs/legacy-launchpad-parity.md)** — original
  host-boundary finding (superseded by the broader parity assessment above).

## Numerical Compatibility

Two independent sources of numerical divergence have been characterised
(see the [full parity assessment](https://github.com/mscipio/pseudoCT_standalone/blob/main/docs/parity-assessment.md) for detail):

1. **Queue-dependent Launchpad divergence.** The same compiled `Pseudo_CT_launchpad`
   binary produces measurably different attenuation maps when submitted to
   different PBS queues (default vs `p60`). This is intrinsic to environment-
   sensitive numerical software (CPU dispatch, glibc, MCR BLAS) and proves that
   perfect parity is not achievable when moving away from the legacy execution
   environment — the same binary already varies across hosts within the cluster.

2. **New Segment convergence differences.** Between the local
   `local-near-parity-r2010b` profile and the Launchpad backend, the only
   systematic divergence is in SPM New Segment's Gauss-Newton convergence path.
   From exact cleaned `rc*` inputs, every downstream stage (DARTEL, inverse warp,
   reslice, att_map construction) reproduces byte-identically. The divergent
   voxels in the final `att_map.nii` (~0.23%) are functionally negligible for
   511 keV PET attenuation correction.

**Practical conclusion:** The `local-near-parity-r2010b` profile produces
attenuation maps that are practically equivalent to the legacy Launchpad output
for the purpose of PET attenuation correction. The Launchpad backend itself
lacks a fixed numerical reference because its output depends on which PBS queue
runs the job. A cross-validation period (running both Launchpad and local for the
first batch of subjects in a new study) is recommended but expected to converge
quickly.

For historical output compatibility retain these settings (all profiles ship
with these defaults):

- `recenter_before_normalization = 'No'`.
- Bone-segmentation reduction enabled.
- `zero_background = 'No'`.
- New Segment batch settings: `affreg = ''`, `biasfwhm = 30`, `warp.reg = 10`.

## Repository and Release Archives

The GitHub repository retains maintainer/test/reference content in `scripts/`,
`docs/`, and `deprecated/`, plus tracked maintainer metadata such as
`.gitattributes` and `.gitignore`. These paths are excluded from v2.8.3 release
archives; deployable runtime paths, `README.md`, and `CHANGELOG.md` remain
included. External `Batch_atlas/` and SPM8 resources are not included in the
repository or release archives, so the release is not self-contained.

## Configuration

Runtime configuration is owned by the selected profile in
`src/config/profiles/`:

- `config.spm_root` points to the externally provisioned SPM8 installation.
- `config.atlas_root` points to the externally provisioned `Batch_atlas` tree.
- `config.launchpad.*` points to the separately provisioned Launchpad files and
  remote batch-template directory when the `launchpad` profile is selected.

All profiles define `recenter_before_normalization = 'No'` and
`zero_background = 'No'`. Setting `zero_background` to `'Yes'` opts into final
subject-mask background zeroing. On the Launchpad path this is a local
post-fetch operation performed before DICOM conversion; the compiled backend is
unchanged. Older deployed defaults without the key safely retain `'No'`.

## Version History

See [CHANGELOG.md](CHANGELOG.md) for release history. The current release is
**2.8.3** (external prerequisite documentation correction).
