# Local Execution Pipeline

This document describes the end-to-end local pseudo-CT pipeline as implemented by
`atlas_based_attenuation_map.m`. Stages below correspond to the log output from
`run_pseudo_CT` with a `mode='local'` profile.

Section references are to sections within the same repository unless the complete
path is shown.

## External Resources

The repository supplies the pipeline source and orchestration, not the external
runtime payloads. Before a local run, configure the selected profile's
`config.spm_root` to a compatible SPM8 installation, `config.atlas_root` to the
external `Batch_atlas` directory, `config.d2n_root` to the standalone
DICOM-to-NIfTI converter, and `config.aliasing_root` to the standalone
aliasing/recentering facade. `setup_pseudo_CT_paths` validates these four roots
before changing the MATLAB path. FreeSurfer is also external and is invoked via
`config.normalization.source_command`; its installation is validated when the
normalization command runs, not by this path preflight. Every `Batch_atlas/...`
reference below means a file under `config.atlas_root`, not a directory expected
at the repository root.

```
legend:
  ┌─────────┐  pipeline stage
  │ *.nii   │  file produced (pseudoCT/tmp/)
  ├─────────┤
  └─────────┘
  ~~~tool~~~   external tool or internal function
```

---

## Stage 1 — Input Preparation

```
  MPRAGE DICOM (IMA/DCM)   or   MPRAGE NIfTI (.nii / .nii.gz)
  │
  ~~~ dcm2nii (dicom2nifti_standalone) ~~~
  │
  └── MR_PET/tmp/mprage.nii
```

Called by `run_pseudo_CT → local_run_subject`. The input can be either:

- **DICOM** (`.dcm`, `.DCM`, `.ima`, `.IMA`): converted to NIfTI via SPM's DICOM
  import. A separate UMAP DICOM file is needed for the DICOM output geometry.
- **NIfTI** (`.nii`, `.nii.gz`): staged into `tmp/mprage.nii` by the standalone
  `dcm2nii` converter. A UMAP reference is still required for DICOM output
  (discovered from the sibling `MR/` directory tree).

### NIfTI input

To use a pre-converted NIfTI instead of raw DICOM:

```matlab
run_pseudo_CT('profile', 'local-near-parity-r2010b', 'subjects', ...
    {'/path/to/subject/MR_PET/mprage.nii'})
```

Place the NIfTI in the `MR_PET/` folder alongside the existing `MR/` tree.
The UMAP auto-discovery finds the reference UMAP from the sibling `MR/`
directory. The expected layout is:

```
<subject_root>/
├── MR/
│   ├── UMAP/            ← reference UMAP (for DICOM geometry)
│   ├── MEMPRAGE/        ← original DICOM (optional when using NIfTI)
│   └── ...
└── MR_PET/              ← contains a NIfTI MPRAGE
    └── mprage.nii
```

The NIfTI is copied (not moved) into `MR_PET/tmp/` during staging, leaving the
original untouched.

**Files created:**
- `MR_PET/tmp/mprage.nii` — the working MPRAGE in NIfTI format (copy of input).

**Tools used:**
- `dcm2nii` (`d2n_root` from profile config) — standalone DICOM-to-NIfTI converter that
  handles DICOM import (via SPM's `spm_dicom_convert`, overridden by
  `vers/spm_dicom_convert.m` for R2010b compatibility), `.nii.gz` decompression,
  and plain `.nii` pass-through.
  The legacy `convert_dicom_i_2_nii` helper has been retired to `deprecated/`.

---

## Stage 2 — FreeSurfer Normalization

```
  MR_PET/tmp/mprage.nii
  │
  ├─ if aliasing OR recentering is requested and the input is not already
  │  `_normalized.nii` or `_moved.nii`
  │  ~~~ correct_aliasing (independent AliasCorrection/Centering flags) ~~~
  │  └── MR_PET/tmp/mprage_corrected.nii
  │
  ~~~ mri_normalize (FreeSurfer 5.3) ~~~
  │
  └── MR_PET/tmp/mprage_normalized.nii
```

Runs `mri_normalize` on the MPRAGE to correct intensity non-uniformity. When
`config.normalization.host` is `'127.0.0.1'`, the command runs locally via
`system()`. Otherwise, the MPRAGE is SCP'd to the remote host, `mri_normalize`
runs there, and the result is SCP'd back.

Before normalization, local jobs carry two independent permissions:
`correct_aliasing` for nose/back aliasing correction and
`recenter_before_normalization` for MPRAGE recentering. The selected profile
supplies their defaults (`aliasing_default = 1` and
`recenter_before_normalization = 'Yes'` in all shipped profiles), and the GUI
controls can change them independently. The historical parity comparison used
`recenter_before_normalization = 'No'`; that compatibility setting is not the
current local default.

The local preprocessing gate is OR-based. When either permission is enabled and
the input is not already `_normalized.nii` or `_moved.nii`, the external
`correct_aliasing` standalone is called with independent named arguments:

```matlab
result = correct_aliasing(inputPath, outputPath, ...
    'AliasCorrection', aliasing_requested, ...
    'Centering', recentering_requested, 'Overwrite', true)
```

When both permissions are false, the facade is not called and the original input
continues unchanged. The four-field result (`status`, `outputs`, `message`, and
`details`) is reported per operation: `details.centering.performed` and
`details.alias_correction.performed` distinguish “Successfully applied” from a
successful “Not required” no-op; missing or unusable operation details are
reported as unavailable without changing the operation's result handling.

The external facade requires MATLAB R2019+. On R2010b, the compatibility guard
does not call or inspect it: requested operations are reported unavailable, the
original input is retained, and the historical pipeline continues without
failing or falling back to the deprecated in-package implementations.

Legacy in-package implementations (`center_subject_in_image`,
`automatic_anti_aliasing_nose_2_back`) are preserved unmodified in `deprecated/`
pending deletion.

**Conditional file (when local preprocessing is invoked):**
- `MR_PET/tmp/mprage_corrected.nii` — MPRAGE produced by the external
  `correct_aliasing` standalone (alias-corrected and/or recentered according to
  the two independent requests).

**Files created:**
- `MR_PET/tmp/mprage_normalized.nii` — intensity-normalized MPRAGE.

**Tools used:**
- `correct_aliasing` (external standalone at `aliasing_root` from profile config) —
  owns both nose/back alias correction and subject centering for local profiles.
  It is guarded on older releases (e.g. `local-near-parity-r2010b`) because it
  requires MATLAB R2019+; requested operations are reported unavailable without
  failing the historical path. Launchpad profiles delegate aliasing to the
  compiled backend and do not require the local standalone.
- `mri_normalize` (FreeSurfer 5.3) — via SSH or local `system()` call.
- `ssh_login_pseudo_CT` / `ssh2_config` (`src/remote/`) — SSH connection.
- `scp_put_david` / `scp_get_david` — file transfer when remote.

---

## Stage 3 — MNI Repositioning

```
  MR_PET/tmp/mprage_normalized.nii
  │
  ~~~ move_image_2_MNI(ch2.nii) ~~~
  │
  ├── MR_PET/tmp/mprage_normalized_repos.nii
```

Aligns the normalized MPRAGE approximately to the MNI `ch2.nii` template. This
is a rigid-body reorientation (6-parameter: 3 rotations + 3 translations) followed
by an affine registration (9-parameter: +3 scaling). The pitch angle is forced to
0.3 rad and roll is zeroed to compensate for known variability in the template
matching.

After the initial rigid transform, `spm_coreg` (estimate only, no reslice) further
refines the affine alignment including scaling. This step is **not** governed by
`recenter_before_normalization` — it is always executed.

**Files created:**
- `MR_PET/tmp/mprage_normalized_repos.nii` — MNI-aligned MPRAGE.
- `MR_PET/tmp/mprage_normalized_repos_move2mni_debug.mat` — debug struct (only
  when environment variable `PSEUDOCT_DEBUG_MOVE2MNI` is set).

**Tools used:**
- `move_image_2_MNI` (`src/core/`) — PCA-based orientation + rigid + affine
  coreg to `ch2.nii`.
- `pseudo_CT_pca_resolver` (`src/config/`) — selects the PCA implementation
  (repo_legacy or callable_pca) from the profile's `pca_order`.
- `spm_run_coreg_estimate` (SPM8) — affine coregistration (estimate only).
- Reference: `config.atlas_root/ch2.nii` from the external `Batch_atlas` tree — the MNI T2 template.

---

## Stage 4 — Subject Masking

```
  MR_PET/tmp/mprage_normalized_repos.nii
  │
  ~~~ spm_smooth(4mm) ~~~
  │   MR_PET/tmp/smprage_normalized_repos.nii  (temp)
  │
  ~~~ head_mask_mprage(Ims, 15) ~~~
  │
  ~~~ imdilate, NaN outside mask ~~~
  │
  ├── MR_PET/tmp/mprage_normalized_repos.nii  (modified — NaN outside head)
```

Smooths the reposited MPRAGE with a 4mm Gaussian kernel, creates a binary head
mask at threshold 15, dilates it with a 13×13×13 structuring element, and sets
voxels outside the dilated mask to NaN. This prevents SPM New Segment from
classifying background noise.

**Files modified:**
- `MR_PET/tmp/mprage_normalized_repos.nii` — overwritten with NaN outside the
  dilated head mask.

**Files created (intermediate, cleaned up):**
- `MR_PET/tmp/smprage_normalized_repos.nii` — temporarily stores the smoothed
  image; this file is used only for mask creation and is not referenced further.

**Tools used:**
- `spm_smooth` (SPM8) — Gaussian smoothing.
- `head_mask_mprage` (`src/core/`) — threshold + morphological closing via
  `imfill`, `imerode`, `imdilate` (Image Processing Toolbox).
- `imgaussian` (`imgaussian/`) — alternative Gaussian filter available.

---

## Stage 5 — SPM New Segment

```
  MR_PET/tmp/mprage_normalized_repos.nii  (NaN-masked)
  │
  ~~~ cfg_util('run', new_segment_batch.mat) ~~~
  │
  ├── MR_PET/tmp/c1mprage_normalized_repos.nii   (GM)
  ├── MR_PET/tmp/c2mprage_normalized_repos.nii   (WM)
  ├── MR_PET/tmp/c3mprage_normalized_repos.nii   (CSF)
  ├── MR_PET/tmp/c4mprage_normalized_repos.nii   (Bone)
  ├── MR_PET/tmp/c5mprage_normalized_repos.nii   (Soft tissue)
  ├── MR_PET/tmp/c6mprage_normalized_repos.nii   (Air/background)
  ├── MR_PET/tmp/mmprage_normalized_repos.nii    (bias-corrected MPRAGE)
  ├── MR_PET/tmp/rc1mprage_normalized_repos.nii  (cleaned GM)
  ├── MR_PET/tmp/rc2mprage_normalized_repos.nii  (cleaned WM)
  ├── MR_PET/tmp/rc3mprage_normalized_repos.nii  (cleaned CSF)
  ├── MR_PET/tmp/rc4mprage_normalized_repos.nii  (cleaned Bone)
  ├── MR_PET/tmp/rc5mprage_normalized_repos.nii  (cleaned Soft tissue)
  └── MR_PET/tmp/rc6mprage_normalized_repos.nii  (cleaned Air/background)
```

Loads `config.atlas_root/new_segment_batch.mat` from the external `Batch_atlas` tree, sets the channel to the masked MPRAGE,
overrides batch parameters (`affreg=''`, `biasfwhm=30`, `warp.reg=10`), and runs
the full New Segment pipeline:
1. Bias-field correction → `m*` (bias-corrected image).
2. Tissue probability segmentation → `c*` (native space).
3. DARTEL-import cleanup → `rc*` (cleaned and imported to DARTEL space).

This is the **divergent step** between execution environments — the Gauss-Newton
optimiser's convergence path depends on host CPU dispatch and system math library.

### Bone Reduction (Sub-stage)
```matlab
if config.bone_enabled
    [Prc_new] = reduce_bone_segment(Prc_old);  % modifies rc2* (WM/bone)
end
```
When enabled (default), `reduce_bone_segment` reclassifies part of the WM (`rc2`)
into the bone class to improve the bone-CT attenuation mapping. This is a
post-segmentation relabelling; it does not affect the already-written `c*` files,
only the `rc*` inputs to DARTEL.

**Files created:**
- 6× `c*` — native-space tissue segments.
- 1× `m*` — bias-corrected anatomical image.
- 6× `rc*` — cleaned segments ready for DARTEL.

**Tools used:**
- `cfg_util` (SPM8) — batch runner for the SPM job manager.
- `config.atlas_root/new_segment_batch.mat` — external SPM batch template.
- `config.atlas_root/TPM.nii` — external tissue probability maps.
- `reduce_bone_segment` (`src/core/`) — reclassifies WM→Bone.

---

## Stage 6 — DARTEL

```
  MR_PET/tmp/rc[1-6]mprage_normalized_repos.nii
  │
  ~~~ cfg_util('run', dartel_existing_template_batch.mat) ~~~
  │
  └── MR_PET/tmp/u_rc1mprage_normalized_repos.nii  (flow field)
```

Loads `config.atlas_root/dartel_existing_template_batch.mat` from the external `Batch_atlas` tree, populates the 6 tissue
images, sets the templates from `Batch_atlas/Template_*.nii` (Large FOV templates),
and runs DARTEL (existing template) to compute the flow field that maps the subject
to the atlas space.

**Files created:**
- `MR_PET/tmp/u_rc1mprage_normalized_repos.nii` — DARTEL flow field.

**Tools used:**
- `cfg_util` (SPM8) — batch runner.
- `config.atlas_root/dartel_existing_template_batch.mat` — external batch template.
- `config.atlas_root/Template_1.nii` through `Template_6.nii` — external DARTEL templates.

---

## Stage 7 — Inverse Warp

```
  MR_PET/tmp/u_rc1mprage_normalized_repos.nii
  │
  ~~~ cfg_util('run', create_inverse_warped_batch.mat) ~~~
  │
  ├── MR_PET/tmp/w*Atlas*_u_rc1mprage_normalized_repos.nii
```

Loads `config.atlas_root/create_inverse_warped_batch.mat` from the external `Batch_atlas` tree, sets the flow field and atlas
images, and runs the inverse warp to project all atlases from atlas-space back
into subject DARTEL-space.

The atlases are discovered at runtime from the external `config.atlas_root/*Atlas*.nii`:
- `*Atlas_rCT*` — CT atlas (converted to att_map later).
- `*Atlas_rMPRAGE*` — MPRAGE atlas.
- `*Atlas_rUTE1*` — UTE1 atlas.
- `*Atlas_rUTE2*` — UTE2 atlas.
- `*Atlas_head_mask*` — head mask atlas.

**Files created:**
- `MR_PET/tmp/w*Atlas_*_u_rc1mprage_normalized_repos.nii` — warped atlases
  (one per atlas image).

**Tools used:**
- `cfg_util` (SPM8) — batch runner.
- `config.atlas_root/create_inverse_warped_batch.mat` — external batch template.

---

## Stage 8 — Atlas Reslice

```
  w*Atlas*_u_rc1mprage_normalized_repos.nii
  │
  ~~~ spm_reslice (to MPRAGE space) ~~~
  │
  └── MR_PET/tmp/rw*Atlas*_u_rc1mprage_normalized_repos.nii
```

Reslices all warped atlases back into the original MPRAGE space. Uses 7th degree
B-spline interpolation. The reference image is the original `mprage.nii` (before
any reorientation).

**Files created:**
- `MR_PET/tmp/rw*Atlas*_u_rc1mprage_normalized_repos.nii` — resliced atlases in
  MPRAGE space.

**Tools used:**
- `spm_reslice` (SPM8) — coregistration write/reslice.

---

## Stage 9 — Attenuation Map Construction

```
  rw*Atlas_rCT*.nii (CT atlas in MPRAGE space)
  rw*Atlas_head_mask*.nii (head mask in MPRAGE space)
  mprage.nii (original MPRAGE)
  │
  ~~~ CT_2_att_map ~~~
  │   ┌── att_map (converted from HU to 511 keV mu)
  │   ├── multiply by warped head_mask
  │   ├── fill gaps with soft-tissue (0.096 cm⁻¹)
  │   ├── soft-tissue ring from dilated mask (v1.6.1)
  │   └── optional background zeroing (config.zero_background)
  │
  └── MR_PET/tmp/att_map.nii
```

Converts the resliced CT atlas (Hounsfield units) to a 511 keV attenuation map
using `CT_2_att_map`. The core steps are:

1. **CT → mu conversion** — piecewise linear mapping (HU to linear attenuation).
2. **Head mask multiplication** — from the warped head mask atlas.
3. **Gap filling** — where the subject mask extends beyond the atlas mask, fill
   with 0.096 cm⁻¹ (soft tissue equivalent).
4. **Nose-job fix (v1.6.1)** — a dilated/eroded subject mask creates a soft-tissue
   ring to handle aliasing at the edges.
5. **Optional background zeroing** — when `zero_background = 'Yes'`, voxels outside
   the subject mask are set to zero.

**Files created:**
- `MR_PET/tmp/att_map.nii` — final attenuation map.
- `MR_PET/tmp/att_map_no_filled.nii` — pre-gap-filling att_map (diagnostic,
  overwritten by the final named output).

**Tools used:**
- `CT_2_att_map` (`src/core/`) — HU → mu conversion.
- `head_mask_mprage` (`src/core/`) — for the subject mask from original MPRAGE.
- `bwlabeln` (MATLAB Image Processing Toolbox) — largest-blob selection.

---

## Stage 10 — QC Image

```
  MR_PET/tmp/att_map.nii  +  aligned MPRAGE
  │
  ~~~ quick_fusion_pseudo_ct ~~~
  │
  └── MR_PET/tmp/Fusion_MR_Pseudo_CT_validation.tiff
```

Creates a fused MR/pseudo-CT composite QC image showing all three planes
(axial, coronal, sagittal) with MIP overlay. Saved as 300 DPI TIFF.

**Files created:**
- `MR_PET/tmp/Fusion_MR_Pseudo_CT_validation.tiff`.

**Tools used:**
- `quick_fusion_pseudo_ct` (`src/qc/`) — overlay renderer (fused colour map).

---

## Stage 10 — Version Log

```
  ~~~ pseudo_CT_write_version_log ~~~
  └── MR_PET/tmp/Pseudo_CT_AC_Version.txt
```

Writes the current code version from `CHANGELOG.md` to the processing directory.

---

## Stage 11 — DICOM Output

```
  MR_PET/tmp/att_map.nii
  │
  ~~~ pseudo_CT_write_mu_map_dicom(umap_ref) ~~~
  │
  └── MR/pseudo_muMAP/*.dcm
```

Converts the NIfTI attenuation map to DICOM using the original UMAP geometry as
reference. Applies optional FWHM smoothing. Writes Siemens-style DICOM mu-map
images suitable for the mMR reconstruction chain.

**Files created:**
- `MR/pseudo_muMAP/` — DICOM series files.

**Tools used:**
- `pseudo_CT_write_mu_map_dicom` (`src/io/`) — NIfTI → DICOM with UMAP reference.

---

## Stage 12 — Promotion and Cleanup

```
  MR_PET/tmp/att_map.nii
  MR_PET/tmp/Fusion_MR_Pseudo_CT_validation.tiff
  MR_PET/tmp/Pseudo_CT_AC_Version.txt
  MR_PET/tmp/mprage.nii                 (when available)
  MR_PET/tmp/mprage_normalized.nii     (when available)
  │
  ~~~ pseudo_CT_promote_final_outputs ~~~
  │
  ├── MR_PET/att_map.nii
  ├── MR_PET/Fusion_MR_Pseudo_CT_validation.tiff
  ├── MR_PET/Pseudo_CT_AC_Version.txt
  ├── MR_PET/MPRAGE_spm.nii             (when available)
  └── MR_PET/MPRAGE_spm_normalized.nii  (when available)
  │
  ~~~ rmdir (optional, controlled by config.cleanup_on_success) ~~~
  │
  └── MR_PET/tmp/  (removed on success when cleanup is enabled)
```

The persistent outputs include `att_map.nii`, the QC TIFF, the version log,
available promoted MPRAGE copies (`MPRAGE_spm.nii` and
`MPRAGE_spm_normalized.nii`), and the DICOM mu-map in `MR/pseudo_muMAP/`.
All shipped production profiles set `config.cleanup_on_success = true`, so a
successful run removes `MR_PET/tmp/` after promotion. The development profile
sets it to `false`; disabling cleanup, or an interrupted or failed run, retains
the intermediate files for debugging.

---

## Output Directory Structure (local profile)

```
<subject_root>/
├── MR/
│   └── pseudo_muMAP/         ← DICOM mu-map (final deliverable)
├── MR_PET/
│   ├── att_map.nii             ← promoted from tmp/
│   ├── Fusion_MR_Pseudo_CT_validation.tiff  ← promoted
│   ├── Pseudo_CT_AC_Version.txt
│   ├── MPRAGE_spm.nii          ← promoted seed input, when available
│   ├── MPRAGE_spm_normalized.nii ← promoted normalized input, when available
│   ├── pseudo_CT_<profile>_<runid>.log
│   └── tmp/                    ← retained only when cleanup is disabled or the run fails
│       ├── mprage.nii
│       ├── mprage_normalized.nii
│       ├── mprage_normalized_repos.nii
│       ├── c1..6*.nii, rc1..6*.nii, m*.nii
│       ├── u_rc1*.nii
│       ├── w*Atlas_*.nii, rw*Atlas_*.nii
│       ├── att_map.nii
│       └── Fusion_MR_Pseudo_CT_validation.tiff
```

---

## References

- [Parity Assessment](parity-assessment.md) — numerical reproducibility across
  execution environments
- [Launchpad Pipeline](pipeline-launchpad.md) — the remote execution equivalent
