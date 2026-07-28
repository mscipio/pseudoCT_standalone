# Launchpad Execution Pipeline

This document describes the end-to-end Launchpad pseudo-CT pipeline. It differs
fundamentally from the local path: the local MATLAB layer handles DICOM I/O and
output promotion, while the compiled `Pseudo_CT_launchpad` backend (MATLAB Compiler
Runtime 7.11 / R2010b) runs on a remote PBS cluster via SSH.

```
legend:
  ┌─────────┐  pipeline stage (local MATLAB)
  │ *.nii   │  file produced
  ├─────────┤
  └─────────┘
  ╔═════════════╗  stage inside compiled backend (remote)
  ║             ║
  ╚═════════════╝
  ~~~tool~~~       internal function or external tool
```

---

## Stage 1 — Input Preparation (local)

```
  MPRAGE DICOM (IMA)
  │
  ~~~ convert_dicom_i_2_nii ~~~
  │
  └── MR_PET/tmp/mprage.nii
```

Identical to the local pipeline. Each subject's primary MPRAGE DICOM is converted
to NIfTI into the local temporary working directory.

**Files created:**
- `MR_PET/tmp/mprage.nii`.

**Tools used:**
- `convert_dicom_i_2_nii` (`src/io/`) — wraps SPM DICOM import.

---

## Stage 2 — Upload, FreeSurfer, and Job Submission (local → remote)

```
  MR_PET/tmp/mprage.nii
  │
  ~~~ SCP (ssh2) ~~~
  │
  remote:/cluster/scratch/monday/<user>/<rand>/mprage.nii
  │
  ~~~ mri_normalize (FreeSurfer 5.3, cluster) ~~~
  │
  remote: mprage_normalized.nii
  │
  ~~~ Submit compiled Pseudo_CT_launchpad to PBS queue ~~~
  │
  └── Remote PBS job (qsub)
```

**2a — Upload.** The MPRAGE NIfTI is SCP'd to the Launchpad SSH host under
`/cluster/scratch/monday/<user>/<rand>/`.

**2b — FreeSurfer normalization.** `mri_normalize` runs on the remote host
(or via cluster submission if `config.normalization.cluster = 'Yes'`).
The normalized MPRAGE is the input to the compiled backend.

**2c — Job submission.** The compiled `Pseudo_CT_launchpad` is submitted to the
PBS queue via:

```
qsub [-q <queue>] run_Pseudo_CT_launchpad.sh <MCR_ROOT> \
  <normalized_nii> <batch_templates> <check_aliasing> <defaults_mat>
```

Environment variables `OMP_NUM_THREADS=1 MKL_NUM_THREADS=1` are set to eliminate
DARTEL thread-count non-determinism.

**Queue selection:**
- If `config.launchpad.queue` is set (e.g. `'p60'`), it overrides the default.
- If the subject count exceeds 100, `-q max100` is used automatically.
- Otherwise, PBS's default queue is used.

**Note on queue divergence:** The `p60` queue produces numerically different
results from the default queue for the same binary and input. See
[Parity Assessment](parity-assessment.md).

**Files created (remote):**
- `/cluster/scratch/.../<rand>/mprage_normalized.nii`.

**Tools used (local side):**
- `batch_pseudo_CT_launchpad` (`src/launchpad/`) — queue orchestration.
- `ssh2_config`, `scp_put` (`ssh2_v2_m1_r5/`).
- `ssh_login_pseudo_CT` (`src/remote/`).
- `run_launchpad_cmd_return` (`src/remote/`) — wraps qsub submission.

**Tools used (remote side):**
- `mri_normalize` (FreeSurfer 5.3).
- `run_Pseudo_CT_launchpad.sh` — compiled MCR app launcher.
- `Pseudo_CT_launchpad` — compiled MATLAB binary (see Stages 3–10).

---

## Stage 3 — Remote Processing Wait (local)

```
  ┌─────────────────────────────────────────────────────┐
  │  pseudoct: polling Launchpad job <N> (ctrl-C to     │
  │           abort, elapsed 00:12:34)                  │
  └─────────────────────────────────────────────────────┘
  │
  ~~~ check_launchpad_command_status ~~~
  │
  └── Exit status per subject (0 = success)
```

Polls the remote PBS job status every 60 seconds with a 10-minute timeout per
subject. The remote job is self-contained and processes exactly one subject.

**Tools used:**
- `check_launchpad_command_status` (`src/remote/`) — PBS job polling.

---

## Stage 4 — Download Outputs (remote → local)

```
  remote: /cluster/scratch/.../<rand>/*.nii
         (att_map.nii, Fusion*.tiff, all intermediate NIfTIs)
  │
  ~~~ SCP get (ssh2) ~~~
  │
  └── MR_PET/tmp/  (all files copied back)
```

All files created by the compiled backend on the remote scratch folder are
downloaded back to the subject's local `MR_PET/tmp/` directory.

If `att_map.nii` is absent despite a successful exit status (known failure mode
for subject-specific issues), the subject is marked as failed with code 711.

**Remote scratch cleanup:** Unless `keep_tmp` is set, the remote scratch files
are deleted after download.

**Tools used:**
- `scp_get` (`ssh2_v2_m1_r5/`).
- `ssh2_command` for cleanup.

---

## Stage 5 — Compiled Backend Internals (remote PBS node)

```
  ╔══════════════════════════════════════════════════════╗
  ║  Pseudo_CT_launchpad (compiled MCR R2010b binary)   ║
  ║                                                      ║
  ║  ┌── Stage 3a: MNI repos (same move_image_2_MNI)    ║
  ║  ├── Stage 4a: Subject mask (same logic)             ║
  ║  ├── Stage 5a: New Segment (same batch, built-in     ║
  ║  │              SPM8)     ← divergent step           ║
  ║  ├── Stage 5b: Bone reduction (same code)            ║
  ║  ├── Stage 6a: DARTEL (same batch)                   ║
  ║  ├── Stage 7a: Inverse warp (same batch)             ║
  ║  ├── Stage 8a: Atlas reslice (same)                  ║
  ║  ├── Stage 9a: att_map construction (same)           ║
  ║  └── Stage 10a: QC + version log (same)              ║
  ║                                                      ║
  ║  Outputs:                                            ║
  ║   - att_map.nii                                      ║
  ║   - Fusion_MR_Pseudo_CT_validation.tiff              ║
  ║   - Pseudo_CT_AC_Version.txt                         ║
  ║   - All intermediate NIfTIs                           ║
  ╚══════════════════════════════════════════════════════╝
```

The compiled backend uses a **self-contained SPM8 installation** bundled with
the MCR deployment and the same `Batch_atlas` templates. Its pipeline stages are
structurally identical to the local pipeline Stages 3–10. The key difference is
that New Segment runs through the compiled MCR path (R2010b base) instead of the
local MATLAB interpreter.

**The remote backend produces the same intermediate files as the local pipeline:**
- `mprage_normalized_repos.nii` (MNI repos)
- `c1..6*.nii`, `rc1..6*.nii`, `m*.nii` (New Segment)
- `u_rc1*.nii` (DARTEL flow field)
- `w*Atlas_*.nii`, `rw*Atlas_*.nii` (warped and resliced atlases)
- `att_map.nii` (final attenuation map)
- `Fusion_MR_Pseudo_CT_validation.tiff` (QC)
- `Pseudo_CT_AC_Version.txt` (version log)

---

## Stage 6 — Optional Background Mask (local)

```
  MR_PET/tmp/att_map.nii
  MR_PET/tmp/mprage_normalized.nii
  │
  ┌─ if config.zero_background == 'Yes' ─┐
  │  ~~~ head_mask_mprage(+largest blob)  │
  │  ~~~ dilate + multiply att_map        │
  │  └── att_map.nii (modified)           │
  └───────────────────────────────────────┘
```

Performed locally after the remote outputs have been fetched. When
`zero_background = 'Yes'`, a subject mask is derived from the normalized MPRAGE
and applied to zero out background voxels in `att_map.nii`. On the Launchpad path,
the compiled backend writes `att_map.nii` with the `zero_background` setting from
its own defaults; this local step overrides it.

**Tools used:**
- `head_mask_mprage` (`src/core/`).
- `bwlabeln` (Image Processing Toolbox) — largest-blob selection.

---

## Stage 7 — DICOM Output (local)

```
  MR_PET/tmp/att_map.nii
  │
  ~~~ pseudo_CT_write_mu_map_dicom(umap_ref, fwhm) ~~~
  │
  └── MR/pseudo_muMAP/*.dcm
```

Identical to the local pipeline. The final NIfTI attenuation map is converted to
Siemens-style DICOM mu-map using the original UMAP geometry reference.

**Tools used:**
- `pseudo_CT_write_mu_map_dicom` (`src/io/`).

---

## Stage 8 — Promotion and Cleanup (local)

```
  MR_PET/tmp/att_map.nii      →  MR_PET/att_map.nii
  MR_PET/tmp/QC.tiff          →  MR_PET/Fusion_MR_Pseudo_CT_validation.tiff
  MR_PET/tmp/version.txt      →  MR_PET/Pseudo_CT_AC_Version.txt
  │
  ┌─ if config.cleanup_on_success ─┐
  │  rmdir MR_PET/tmp/ (recursive) │
  └─────────────────────────────────┘
  │
  ~~~ pseudo_CT_cleanup_intermediates ~~~
  └── Deletes *repos_params.mat
```

Same promotion logic as the local pipeline. Intermediates in `MR_PET/tmp/` are
preserved by default (configurable).

---

## Output Directory Structure (Launchpad profile)

```
<subject_root>/
├── MR/
│   └── pseudo_muMAP/         ← DICOM mu-map (final deliverable)
├── MR_PET/
│   ├── att_map.nii
│   ├── Fusion_MR_Pseudo_CT_validation.tiff
│   ├── Pseudo_CT_AC_Version.txt
│   ├── pseudo_CT_launchpad_<runid>.log
│   └── tmp/                    ← all files fetched from remote + local outputs
│       ├── mprage.nii
│       ├── mprage_normalized.nii
│       ├── (all remote intermediate NIfTIs)
│       ├── att_map.nii
│       ├── Fusion_MR_Pseudo_CT_validation.tiff
│       └── Pseudo_CT_AC_Version.txt
```

---

## Key Differences from Local Pipeline

| Aspect | Local | Launchpad |
|--------|-------|-----------|
| SPM execution | Local MATLAB interpreter | Compiled MCR 7.11 (R2010b) |
| New Segment host | Local workstation | PBS cluster node (variable) |
| Normalization | Local or SSH to remote host | Always on cluster head node |
| Pipeline stages | All in one MATLAB session | Split across local + remote |
| Output promotion | From `tmp/` to `MR_PET/` | SCP fetch → local processing → promote |
| Debug access | All intermediates available immediately | Requires `keep_tmp` on remote |

---

## References

- [Local Pipeline](pipeline-local.md) — the equivalent local execution stages
- [Parity Assessment](parity-assessment.md) — numerical reproducibility findings
