# pseudoCT_standalone

Atlas-based pseudoCT generation for PET/MR attenuation correction.

`pseudoCT_standalone` is the actively maintained Martinos implementation of the SPM8-based atlas pseudoCT method described by Izquierdo-Garcia et al. It generates a subject-specific attenuation map from a T1-weighted MPRAGE for use in PET/MR attenuation correction.

The software supports:

- MPRAGE input as DICOM, `.nii`, or `.nii.gz`
- Local MATLAB processing
- Single-subject and batch workflows
- Automatic UMAP discovery for the standard PET/MR workflow
- Optional MPRAGE aliasing correction and recentering
- NIfTI and DICOM pseudoCT output
- Automatic QC image generation
- Per-subject processing logs and provenance information

> **Martinos users:** use the centrally deployed version rather than cloning this repository. See the PseudoCT User Guide for step-by-step processing instructions, expected folder structure, outputs, and quality control.

---

## Citation

If you use this method, please cite:

> D. Izquierdo-Garcia, A.E. Hansen, S. Förster, D. Benoit, S. Schachoff, S. Fürst, K.T. Chen, D.B. Chonde, and C. Catana.  
> **An SPM8-based Approach for Attenuation Correction Combining Segmentation and Non-rigid Template Formation: Application to Simultaneous PET/MR Brain Imaging.**  
> *Journal of Nuclear Medicine.* 2014;55(11):1825-1830.

### Software acknowledgement

In addition to citing the methodological publication above, users are kindly asked to acknowledge **Michele Scipioni, PhD** for the development, integration, and ongoing maintenance of the Martinos pseudoCT software in publications, abstracts, presentations, and grant applications that make use of this implementation.

---

## Quick start at Martinos

The centrally deployed software is located under:

```text
/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/
```

For normal use, add the current recommended deployment to the MATLAB path:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
```

Then, from a convenient working directory near your data, run:

```matlab
run_pseudo_CT
```

For routine processing, select **Local MATLAB (Current)**.

Detailed instructions are available in the PseudoCT User Guide.

---

## Version selection and reproducibility

The Martinos deployment contains numbered builds together with:

```text
pseudoCT_standalone-latest
```

which points to the current recommended deployment.

The source tree currently identifies itself as **2.8.4** for release preparation.
Until `v2.8.4` is tagged and published, it is an intended version rather than a
public release or downloadable archive.

For new processing, users should normally use `pseudoCT_standalone-latest`.

For studies that will be processed over an extended period, it is recommended to use the same **numbered pseudoCT build or published release** for the entire study. This avoids introducing software-version changes within a dataset.

New releases may add functionality or correct minor issues. If a problem is identified that makes continued use of an older release inadvisable, this will be explicitly communicated together with the reason for the change.

---

## Execution profiles

PseudoCT uses profile-based execution.

### Local MATLAB (Current)

**Recommended for routine use.**

Runs the full MPRAGE + UMAP workflow locally using the current Martinos MATLAB environment.

Typical processing time on an average workstation is approximately 30 minutes per subject.

### Launchpad (Aether Legacy Workflow)

The historical Launchpad workflow uses the legacy compiled pseudoCT backend.

**Launchpad is currently unavailable.**

It is being replaced by an MLSC-based workflow. Until that replacement is available, Martinos users should use the Local MATLAB profile for routine processing.

### Specialized profiles

Additional profiles are available for specific systems, compatibility testing, validation, and development workflows.

They are not intended for routine use.

**If you do not already know why you need a specialized profile, do not select one.**

---

## Input data

### Standard DICOM workflow

For DICOM input, the expected subject structure is:

```text
<subject>/
└── MR/
    ├── MPRAGE/
    └── UMAP/
```

Select the **first DICOM file of the MPRAGE series**.

The corresponding UMAP is normally discovered automatically from the sibling `MR/UMAP/` directory.

### Preprocessed NIfTI workflow

A preprocessed MPRAGE may instead be supplied as `.nii` or `.nii.gz`.

Place the NIfTI file under:

```text
<subject>/MR_PET/
```

For example:

```text
<subject>/
├── MR/
│   ├── MPRAGE/
│   └── UMAP/
└── MR_PET/
    └── mprage_preprocessed.nii.gz
```

Then select the NIfTI file as the MPRAGE input.

The original input file is preserved during processing.

---

## MPRAGE preprocessing

PseudoCT supports automatic preprocessing intended to improve segmentation and registration to the MNI atlas.

The standard workflow includes two independent controls for:

- nose/neck aliasing correction
- recentering of the MPRAGE within the field of view

For shipped local profiles, both are enabled by default. The historical parity
comparison used `recenter_before_normalization = 'No'`; that is a compatibility
setting, not the current local default. Launchpad profiles retain the local
recentering field for the shared profile contract, but Launchpad ignores it:
the remote compiled workflow performs normalization before pseudoCT processing;
the current orchestration invokes `mri_normalize` before the compiled backend.
Only the independent aliasing request is forwarded as the remote
`check_aliasing` control.

On the local path, the external preprocessing facade is called when either
request is enabled and receives separate aliasing and recentering flags. The
controls can therefore be changed independently; disabling one does not disable
the other.

The preprocessing tools determine whether a correction is actually required, so leaving both options enabled is recommended for routine processing.

---

## Batch processing

To process multiple subjects:

```matlab
run_pseudo_CT('profile', 'local-current', 'subjects', 'batch')
```

This opens a multi-file picker.

Select the first MPRAGE DICOM from each subject, or the corresponding NIfTI input, then click **Done**.

Subjects are processed sequentially.

An explicit subject list can also be supplied:

```matlab
subject_list = {
    '/path/to/subj1/MR/MPRAGE/file1.dcm'
    '/path/to/subj2/MR/MPRAGE/file1.dcm'
};

run_pseudo_CT( ...
    'profile', 'local-current', ...
    'subjects', subject_list);
```

---

## Outputs

For the standard MPRAGE + UMAP workflow, pseudoCT creates the required output directories automatically.

After a successful local run, the subject directory contains approximately:

```text
<subject>/
├── MR/
│   ├── MPRAGE/
│   ├── UMAP/
│   └── pseudo_muMAP/
│       └── final DICOM pseudoCT series
│
└── MR_PET/
    ├── att_map.nii
    ├── Fusion_MR_Pseudo_CT_validation.tiff
    ├── MPRAGE_spm.nii
    ├── MPRAGE_spm_normalized.nii
    ├── Pseudo_CT_AC_Version.txt
    ├── pseudo_CT_local-current_*.log
    └── pseudo_CT_profile_summary.txt
```

Important outputs include:

- `MR/pseudo_muMAP/` — final pseudoCT DICOM series.
- `MR_PET/att_map.nii` — final pseudoCT attenuation map in NIfTI format.
- `MR_PET/Fusion_MR_Pseudo_CT_validation.tiff` — MPRAGE/pseudoCT fusion image for visual QC.
- `MR_PET/pseudo_CT_local-current_*.log` — detailed processing log.
- `MR_PET/pseudo_CT_profile_summary.txt` — concise record of the execution profile, relevant settings, and MATLAB environment used for processing.
- `MR_PET/Pseudo_CT_AC_Version.txt` — software version and release-history information associated with the run.

Intermediate files are staged under `MR_PET/tmp/`.

For the shipped production profiles, `cleanup_on_success = true`, so
`MR_PET/tmp/` is removed after successful output promotion. The development
profile intentionally sets this value to `false` for inspection. If cleanup is
disabled, or processing is interrupted or fails, the intermediate files are
retained.

---

## Quality control

Every generated pseudoCT should be visually inspected before it is used for PET attenuation correction.

Two QC steps are recommended.

### 1. MPRAGE / pseudoCT coregistration

Inspect:

```text
MR_PET/Fusion_MR_Pseudo_CT_validation.tiff
```

Check for:

- agreement between the MPRAGE and pseudoCT anatomy
- appropriate skull and brain contour alignment
- reasonable registration around the nose and sinuses
- appropriate posterior-head alignment
- missing or displaced skull regions
- gross atlas-registration errors
- obvious problems caused by poor positioning within the field of view

### 2. Final pseudoCT volume

Open the DICOM series under:

```text
MR/pseudo_muMAP/
```

in an appropriate DICOM viewer and scroll through the complete volume.

Inspect for unexpected attenuation values or other artifacts.

One known failure mode occurs when noise in the background of the MPRAGE is segmented and incorrectly classified as soft tissue rather than air. This can produce spurious attenuation values outside the head.

If this occurs, the MPRAGE background should be cleaned and the resulting image provided to pseudoCT as a NIfTI input before repeating processing.

A dedicated MPRAGE background-cleanup tool is planned for release.

---

## Interrupting and restarting processing

MATLAB must remain running for the duration of processing.

It is safe to interrupt pseudoCT, but interruption stops the current run and leaves intermediate files generated up to that point.

Starting pseudoCT again for the same subject restarts processing from the beginning and overwrites existing processing files as needed.

---

## External installation

The GitHub repository is **not a completely self-contained installation**.

The Martinos deployment relies on externally provisioned resources including:

- SPM8
- pseudoCT atlas images and SPM batch templates
- FreeSurfer
- the standalone DICOM-to-NIfTI converter
- for local profiles, the standalone aliasing/recentering tool
- remote infrastructure for legacy/compatibility workflows

Runtime locations are defined by the selected profile under:

```text
src/config/profiles/
```

Every execution requires compatible SPM, atlas, and DICOM-to-NIfTI resources.
Local profiles additionally require the external aliasing/recentering resource.
In particular:

```matlab
config.spm_root
config.atlas_root
config.d2n_root
config.aliasing_root  % local profiles
```

must point to compatible external installations.

Users outside the Martinos environment should therefore expect to configure these resources before running the pipeline.

For local profiles, startup validates the configured SPM, atlas, DICOM-to-NIfTI,
and aliasing roots before adding them to the MATLAB path. FreeSurfer itself is
also external: the selected profile's `config.normalization.source_command`
must source a compatible installation, but that command is checked when
normalization runs rather than by this preflight. Launchpad profiles do not
validate or import the local aliasing standalone; they require the separately
provisioned remote runner, MCR, defaults MAT, and batch-template directory, and
delegate aliasing/recentering behavior to the compiled backend as described
above.

---

## Technical documentation

The repository contains additional technical and validation documentation under [`docs/`](docs/).

Useful references include:

- [Local Pipeline Stages](docs/pipeline-local.md)
- [Launchpad Pipeline Stages](docs/pipeline-launchpad.md)
- [Numerical Parity Assessment](docs/parity-assessment.md)
- [Legacy Launchpad Parity](docs/legacy-launchpad-parity.md)
- [Release History](CHANGELOG.md)

The main README is intentionally user-facing. Detailed implementation and maintainer information should be kept in the technical documentation rather than duplicated here.

---

## Repository and release archives

The GitHub repository retains maintainer, test, legacy, and technical-reference
content such as `scripts/`, `docs/`, and `deprecated/`. The intended v2.8.4
tag-based archive will apply the committed `.gitattributes` `export-ignore`
policy to exclude those paths and maintainer metadata while retaining the
deployable runtime, `README.md`, and `CHANGELOG.md`. External SPM8, atlas,
FreeSurfer, converter, aliasing, and Launchpad resources are not bundled, so the
archive is not self-contained.

No public `v2.8.4` tag, release, or archive exists yet; the archive wording here
describes the preparation policy rather than an already-published artifact.

---

## Repository structure

```text
run_pseudo_CT.m
src/
    config/
    core/
    io/
    launchpad/
    qc/
    remote/
    ui/
docs/
deprecated/
scripts/
vers/
imgaussian/
ssh2_v2_m1_r5/
```

Key directories:

- `src/config/` — profiles, environment configuration, and path setup
- `src/core/` — pseudoCT processing pipeline
- `src/io/` — input/output and conversion helpers
- `src/ui/` — MATLAB graphical user interface
- `src/qc/` — QC image generation
- `src/remote/` — remote execution support
- `src/launchpad/` — legacy Launchpad orchestration
- `docs/` — technical and validation documentation
- `deprecated/` — historical implementations retained for reference

---

## Maintainer

**Michele Scipioni, PhD**  
Athinoula A. Martinos Center for Biomedical Imaging  
Massachusetts General Hospital / Harvard Medical School

Email: mscipioni@mgh.harvard.edu

For processing problems, please retain the subject's:

- pseudoCT processing log
- `pseudo_CT_profile_summary.txt`
- QC TIFF
- pseudoCT software version

when requesting support.
