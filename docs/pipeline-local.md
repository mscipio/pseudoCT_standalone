# Local Execution Pipeline

This document describes the end-to-end local pseudo-CT pipeline as implemented by
`atlas_based_attenuation_map.m`. Stages below correspond to the log output from
`run_pseudo_CT` with a `mode='local'` profile.

Section references are to sections within the same repository unless the complete
path is shown.

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
  MPRAGE DICOM (IMA/DCM)   or   MPRAGE NIfTI (.nii)
  │
  ~~~ convert_dicom_i_2_nii ~~~
  │
  └── MR_PET/tmp/mprage.nii
```

Called by `run_pseudo_CT → local_run_subject`. The input can be either:

- **DICOM** (`.dcm`, `.DCM`, `.ima`, `.IMA`): converted to NIfTI via SPM's DICOM
  import. A separate UMAP DICOM file is needed for the DICOM output geometry.
- **NIfTI** (`.nii`): **copied** directly to `tmp/mprage.nii` preserving the
  original file. A UMAP reference is still required for DICOM output (discovered
  from the sibling `MR/` directory tree).

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
- `convert_dicom_i_2_nii` (`src/io/`) — for DICOM wraps SPM's `spm_dicom_convert`
  (overridden by `vers/spm_dicom_convert.m` in local profiles for R2010b
  compatibility); for NIfTI performs a direct file copy.

---

## Stage 2 — FreeSurfer Normalization

```
  MR_PET/tmp/mprage.nii
  │
  ~~~ atlas_based_attenuation_map ~~~
  │
  ├── MR_PET/tmp/mprage_normalized.nii
```

Runs `mri_normalize` on the MPRAGE to correct intensity non-uniformity. When
`config.normalization.host` is `'127.0.0.1'`, the command runs locally via
`system()`. Otherwise, the MPRAGE is SCP'd to the remote host, `mri_normalize`
runs there, and the result is SCP'd back.

Optionally preceded by `center_subject_in_image` if
`config.recenter_before_normalization = 'Yes'` (default: `'No'` on all profiles).

**Conditional file (only when recenter enabled):**
- `MR_PET/tmp/mprage_moved.nii` — recentered MPRAGE (never seen in normal use).

**Files created:**
- `MR_PET/tmp/mprage_normalized.nii` — intensity-normalized MPRAGE.

**Tools used:**
- `center_subject_in_image` (`src/core/`) — wraps pixel data to centre the head
  (only when enabled).
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
- Reference: `Batch_atlas/ch2.nii` — the MNI T2 template.

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

Loads `Batch_atlas/new_segment_batch.mat`, sets the channel to the masked MPRAGE,
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
- `Batch_atlas/new_segment_batch.mat` — SPM batch template.
- `Batch_atlas/TPM.nii` — tissue probability maps.
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

Loads `Batch_atlas/dartel_existing_template_batch.mat`, populates the 6 tissue
images, sets the templates from `Batch_atlas/Template_*.nii` (Large FOV templates),
and runs DARTEL (existing template) to compute the flow field that maps the subject
to the atlas space.

**Files created:**
- `MR_PET/tmp/u_rc1mprage_normalized_repos.nii` — DARTEL flow field.

**Tools used:**
- `cfg_util` (SPM8) — batch runner.
- `Batch_atlas/dartel_existing_template_batch.mat` — batch template.
- `Batch_atlas/Template_1.nii` through `Template_6.nii` — DARTEL templates.

---

## Stage 7 — Inverse Warp

```
  MR_PET/tmp/u_rc1mprage_normalized_repos.nii
  │
  ~~~ cfg_util('run', create_inverse_warped_batch.mat) ~~~
  │
  ├── MR_PET/tmp/w*Atlas*_u_rc1mprage_normalized_repos.nii
```

Loads `Batch_atlas/create_inverse_warped_batch.mat`, sets the flow field and atlas
images, and runs the inverse warp to project all atlases from atlas-space back
into subject DARTEL-space.

The atlases are discovered at runtime from `Batch_atlas/*Atlas*.nii`:
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
- `Batch_atlas/create_inverse_warped_batch.mat` — batch template.

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
  │
  ~~~ pseudo_CT_promote_final_outputs ~~~
  │
  ├── MR_PET/att_map.nii
  ├── MR_PET/Fusion_MR_Pseudo_CT_validation.tiff
  ├── MR_PET/Pseudo_CT_AC_Version.txt
  │
  ~~~ rmdir (optional, controlled by config.cleanup_on_success) ~~~
  │
  └── MR_PET/tmp/  (removed if cleanup enabled, default: preserved)
```

The four final deliverables (att_map.nii, QC TIFF, version log, and DICOM
mu-map in `MR/pseudo_muMAP/`) are the persistent outputs. Intermediate NIfTIs
in `MR_PET/tmp/` are preserved by default for debugging and are removed only when
`config.cleanup_on_success = true`.

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
│   ├── pseudo_CT_<profile>_<runid>.log
│   └── tmp/                    ← all intermediate NIfTIs (preserved by default)
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
