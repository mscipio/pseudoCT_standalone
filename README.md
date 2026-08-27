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

The old entrypoints `run_pseudo_CT_local.m` and `run_pseudo_CT_launchpad.m` have been moved to `deprecated/` and are preserved unmodified for backward compatibility.

## Top-Level Layout

- `run_pseudo_CT.m`: primary user-facing entry point.
- `deprecated/`: contains `run_pseudo_CT_local.m` and `run_pseudo_CT_launchpad.m`, the legacy entry points preserved unmodified for backward compatibility.
- `src/`: project-owned MATLAB source files grouped by function.
- `Batch_atlas/`: atlas images and SPM batch templates used by the pseudo-CT pipeline.
- `spm8-r6313/`: bundled SPM8 tree.
- `vers/`: local SPM overrides required by this pipeline.
- `ssh2_v2_m1_r5/`: bundled SSH/SCP toolbox used by the Launchpad path.
- `imgaussian/`: external image filtering dependency.
- `candidates_for_review/`: non-runtime files that may be removable after review.

## Source Tree

- `src/config/`: runtime defaults and environment setup.
  Contains the local and Launchpad defaults functions plus the local FreeSurfer setup script.
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

- **[Pipeline Stages: Local](docs/pipeline-local.md)** — step-by-step flow for
  local profiles (`local-current`, `local-near-parity-r2010b`): which files are
  created at each stage and which tools are used.
- **[Pipeline Stages: Launchpad](docs/pipeline-launchpad.md)** — step-by-step flow
  for the `launchpad` profile: local I/O layer, remote compiled-backend internals,
  and post-processing.
- **[Numerical Parity Assessment](docs/parity-assessment.md)** — controlled
  comparison between local profiles and the legacy Launchpad backend: what
  diverges, why, and the practical impact on PET attenuation correction.
- **[Legacy Launchpad Parity](docs/legacy-launchpad-parity.md)** — original
  host-boundary finding (superseded by the broader parity assessment above).

## Numerical Compatibility

Two independent sources of numerical divergence have been characterised
(see the [full parity assessment](docs/parity-assessment.md) for detail):

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

## Defaults

Configuration remains in the two legacy defaults functions:

- `src/config/defaults_pseudo_CT.m` controls local execution.
- `src/config/defaults_pseudo_CT_launchpad.m` controls Launchpad execution.

Both define `recenter_before_normalization = 'No'` and
`zero_background = 'No'`. Setting `zero_background` to `'Yes'` opts into final
subject-mask background zeroing. On the Launchpad path this is a local
post-fetch operation performed before DICOM conversion; the compiled backend is
unchanged. Older deployed defaults without the key safely retain `'No'`.

The existing environment overrides remain available for maintainer workflows:
`PSEUDOCT_BATCH_ATLAS`, `PSEUDOCT_KEEP_TMP`, `PSEUDOCT_SPM_ROOT`,
`PSEUDOCT_SPM_VARIANT`, and `PSEUDOCT_ZERO_BACKGROUND`.

## Version History

See [CHANGELOG.md](CHANGELOG.md) for release history. The current release is
**2.8.1** (documentation / version-fallback coherence correction after v2.8.0).
