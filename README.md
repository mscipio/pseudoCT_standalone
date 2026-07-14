# Standalone Pseudo-CT Package

Maintained by Michele Scipioni, PhD  
mscipioni@mgh.harvard.edu  
Last updated: July 14, 2026.

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

## Version History

Historical notes before numbered releases:

- 04/09/2013: added the FreeSurfer intensity-normalization step so the workflow runs from MPRAGE inputs before atlas processing.
- 05/28/2013: added a third input argument for SSH login reuse so subjects could be processed in batches.

Numbered releases:

- 1.1: fill missing atlas-covered head regions with soft tissue.
- 1.2: moved to FreeSurfer 5.3.
- 1.3: updated to the larger atlas set from May 16, 2013.
- 1.4: switched FreeSurfer execution to Launchpad on Jun 21, 2013.
- 1.5: fixed parallel-session issues on Aug 26, 2013.
- 1.6: expanded the attenuation mask to reduce nose-job artifacts on Feb 7, 2014.
- 1.6.1: improved the nose-job correction on Mar 13, 2014.
- 1.6.2: included the username in `/cluster/scratch/monday` staging on Apr 21, 2014.
- 1.7: restricted the MPRAGE mask to the largest connected component on Jul 22, 2014.
- 1.8: added pre-normalization recentering of the MPRAGE to reduce nose/back cropping on Sep 3, 2014.
- 1.8.1: added automatic nose-back anti-aliasing on Sep 11, 2014.
- 2.0: added deployed execution on Dec 9, 2014. <-- VERSION RUNNING ON AETHER (probably!)
- 2.1: added fused QC TIFF output on Jun 25, 2016.
- 2.2: integrated `ssh_login()` to standardize SSH handling on Jul 28, 2016.
- 2.3: improved subject masking using `MPRAGE_normalized.nii` on Sep 23, 2016.
- 2.4: allowed local FreeSurfer execution through `127.0.0.1` on Dec 17, 2017.
- 2.5: repackaged the workflow as a standalone, redistributable package for local execution while preserving the historical compiled `v2.0` Launchpad backend path.
- 2.6.0: unified UMAP discovery, configurable Batch_atlas resolution, and standalone release packaging.
- 2.6.4: re-established NIfTI MPRAGE input support for both local and Launchpad pipelines; configurable PBS queue priority.

## Defaults

- Local mode reads `src/config/defaults_pseudo_CT.m`.
- Launchpad mode reads `src/config/defaults_pseudo_CT_launchpad.m`.

The local defaults file resolves the bundled FreeSurfer setup script relative to its own folder so the configuration remains valid after reorganization.
