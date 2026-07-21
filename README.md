# Standalone Pseudo-CT Package

Maintained by Michele Scipioni, PhD  
mscipioni@mgh.harvard.edu  
Last updated: July 21, 2026.

If you use this method, or parts of it, please, quote this paper:
>D. Izquierdo-Garcia, A.E. Hansen, S. Förster, D. Benoit, S. Schachoff, S. Fürst, K.T. Chen, D.B. Chonde, and C. Catana.
>An SPM8-based Approach for Attenuation Correction Combining Segmentation and Non-rigid Template Formation: Application to Simultaneous PET/MR Brain Imaging. JNM. 2014. Nov;55(11):1825-30.

This package provides two independent ways to generate pseudo-CT attenuation maps from an mMR MPRAGE input.

- `run_pseudo_CT_local.m`: runs the editable MATLAB/SPM pipeline locally.
- `run_pseudo_CT_launchpad.m`: stages the subject to Launchpad and runs the legacy compiled `Pseudo_CT_launchpad` backend.

## Top-Level Layout

- `run_pseudo_CT_local.m`, `run_pseudo_CT_launchpad.m`: user-facing entry points.
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

### Local

`run_pseudo_CT_local.m` adds `src/`, `spm8-r6313/`, `vers/`, `ssh2_v2_m1_r5/`, and `imgaussian/` to the MATLAB path, prompts for the subject files, runs `atlas_based_attenuation_map`, then writes the final DICOM pseudo-muMAP output.

Local mode supports both single-subject and batch usage:

- `run_pseudo_CT_local` opens the existing single-subject selection dialog.
- `run_pseudo_CT_local('batch')` opens a multi-select file picker for MPRAGE files and auto-discovers each subject's UMAP reference.
- `run_pseudo_CT_local(subject_list)` accepts a cell array or char matrix of MPRAGE filenames and processes them sequentially.

Examples:

```matlab
run_pseudo_CT_local('batch')
run_pseudo_CT_local('batch', 0)

subject_list = {
  '/path/to/subj1/MR/MEMPRAGE/file1.IMA'
  '/path/to/subj2/MR/MEMPRAGE/file1.IMA'
};
run_pseudo_CT_local(subject_list)
run_pseudo_CT_local(subject_list, 0)
```

For localhost execution, temporary FreeSurfer normalization staging now happens under each subject's own `MR_PET/tmp` folder rather than under the hardcoded `host_folder` path in the defaults template. On successful completion, the final NIfTI/QC/version artifacts are promoted back into `MR_PET` and the `MR_PET/tmp` folder is removed.

### Launchpad

`run_pseudo_CT_launchpad.m` uses the same local input selection and final DICOM output layer, but the core atlas processing is delegated to the legacy compiled Launchpad application through the queue helpers in `src/launchpad/`.

Launchpad mode supports both single-subject and batch usage:

- `run_pseudo_CT_launchpad` opens the existing single-subject selection dialog.
- `run_pseudo_CT_launchpad('batch')` opens a multi-select file picker for MPRAGE files, auto-discovers each subject's UMAP reference, and submits the batch through Launchpad.
- `run_pseudo_CT_launchpad(subject_list)` accepts a cell array or char matrix of MPRAGE filenames and processes them sequentially through the Launchpad backend.

Examples:

```matlab
run_pseudo_CT_launchpad('batch')
run_pseudo_CT_launchpad('batch', 0)

subject_list = {
  '/path/to/subj1/MR/MEMPRAGE/file1.IMA'
  '/path/to/subj2/MR/MEMPRAGE/file1.IMA'
};
run_pseudo_CT_launchpad(subject_list)
run_pseudo_CT_launchpad(subject_list, 0)
```

## Launchpad and Local Numerical Compatibility

The final controlled comparison places the practical compatibility boundary at
SPM New Segment, and specifically at the host environment used to execute the
same package, input, and job. The legacy PBS E5472/RHEL7/glibc 2.17 environment
matched the historical result exactly. On celer, R2010 compiled and interpreted
runs matched each other but followed a slightly different iterative numerical
path. The experiment did not independently isolate CPU dispatch from glibc or
other system-math behavior.

From exact cleaned `rc*` inputs, the compared celer R2010 DARTEL, inverse-warp,
reslice, and final attenuation-map outputs were byte-identical at every stage.
This is evidence from one controlled subject, not universal end-to-end parity.
Manual pipeline execution and review of the generated QC TIFF remain required.

For historical output compatibility:

- Keep `recenter_before_normalization = 'No'`. Launchpad runs `mri_normalize`
  first and passes `_normalized.nii`, so the recenter branch is bypassed.
- Keep production bone reduction enabled.
- Keep `zero_background = 'No'`.
- Keep the production New Segment settings unchanged: `affreg = ''`,
  `biasfwhm = 30`, and `warp.reg = 10`.

The local entry point continues to load the supported `vers/` compatibility
overrides. The controlled host-boundary result does not attribute New Segment
parity to those writer overrides.

See [Legacy Launchpad Parity](docs/legacy-launchpad-parity.md) for the controlled
provenance, exact stage results, final hash, and limits of the finding.

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

See [CHANGELOG.md](CHANGELOG.md) for release history. Version 2.6.5 adds the
configurable background policy, records the bounded Launchpad parity finding,
and removes superseded investigation tooling while keeping generic comparators.
