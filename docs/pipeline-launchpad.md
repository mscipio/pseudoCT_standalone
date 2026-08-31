# Launchpad Execution Pipeline

This document describes the end-to-end Launchpad pseudo-CT pipeline. It differs
fundamentally from the local path: the local MATLAB layer handles DICOM I/O and
output promotion, while the compiled `Pseudo_CT_launchpad` backend (MATLAB Compiler
Runtime 7.11 / R2010b) runs on a remote PBS cluster via SSH.

The repository is not a self-contained Launchpad distribution. The local layer
still requires externally provisioned SPM8, `Batch_atlas`, and the standalone
DICOM-to-NIfTI converter through `config.spm_root`, `config.atlas_root`, and
`config.d2n_root`. Launchpad profiles do not validate or import the local
aliasing/recentering standalone. The compiled backend, its runner/MCR, defaults
MAT, and remote atlas/template directory must be provisioned separately and
supplied through the `config.launchpad.*` fields; this repository and the
intended v2.8.4 tag-based archive do not distribute those payloads. No public
v2.8.4 archive exists yet; this is the preparation policy.

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
  MPRAGE DICOM (IMA/DCM)   or   MPRAGE NIfTI (.nii / .nii.gz)
  │
  ~~~ dcm2nii (dicom2nifti_standalone) ~~~
  │
  └── MR_PET/tmp/mprage.nii
```

Identical to the local pipeline. Each subject's primary MPRAGE is staged into
the local temporary working directory. Input can be either:

- **DICOM** (`.dcm`, `.DCM`, `.ima`, `.IMA`): converted via SPM DICOM import.
- **NIfTI** (`.nii`, `.nii.gz`): staged by the standalone `dcm2nii` converter.

For NIfTI input in `MR_PET/`, the UMAP auto-discovery uses the sibling `MR/`
directory to find the reference UMAP. See [Local Pipeline Stage 1](pipeline-local.md#stage-1--input-preparation)
for the NIfTI layout and usage example.

**Files created:**
- `MR_PET/tmp/mprage.nii`.

**Tools used:**
- `dcm2nii` (`d2n_root` from profile config) — standalone DICOM-to-NIfTI converter.
  The legacy `convert_dicom_i_2_nii` helper has been retired to `deprecated/`.

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

**2a — Upload and preprocessing boundary.** The MPRAGE NIfTI is SCP'd to the
Launchpad SSH host under `/cluster/scratch/monday/<user>/<rand>/`. The GUI still
shows independent aliasing and recentering controls, initialized from the
selected profile, but Launchpad does not run the local `correct_aliasing`
facade or perform local recentering.

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

The `<check_aliasing>` slot is the only aliasing/recentering operation control
forwarded from the local layer: it carries the independent aliasing request to
the compiled remote backend. Shipped profiles default `aliasing_default` to `1`
and `recenter_before_normalization` to `'Yes'`, but only the former becomes the
remote flag. The historical parity comparison used
`recenter_before_normalization = 'No'`; that is not the current local default.
The local recentering value is not forwarded: the remote Launchpad/compiled
workflow owns normalization, with `mri_normalize` currently invoked before the
compiled backend receives the normalized MPRAGE. There is no local
per-operation `details.*.performed` result; the compiled backend owns its remote
behavior.

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
subject. The remote job processes exactly one subject and relies on the separately
provisioned Launchpad deployment and configured external resources.

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
are deleted after download. In the unified entrypoint, `keep_tmp` is derived
from `cleanup_on_success`, so the shipped Launchpad profiles remove remote
scratch on success.

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

The compiled backend uses the SPM8 and atlas/template resources provisioned with
the separate Launchpad deployment; `config.launchpad.batch_templates` supplies
the remote `Batch_atlas` directory. These resources are not bundled in this
repository or the intended v2.8.4 tag-based archive. Its pipeline stages are structurally
identical to the local pipeline Stages 3–10. The key difference is that New
Segment runs through the compiled MCR path (R2010b base) instead of the local
MATLAB interpreter.

The backend receives the remotely normalized MPRAGE and remains responsible for
the remote `check_aliasing` behavior. No local recentering step is inserted
before upload or after download.

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
  MR_PET/tmp/att_map.nii             →  MR_PET/att_map.nii
  MR_PET/tmp/Fusion_MR_Pseudo_CT_validation.tiff
                                      →  MR_PET/Fusion_MR_Pseudo_CT_validation.tiff
  MR_PET/tmp/Pseudo_CT_AC_Version.txt
                                      →  MR_PET/Pseudo_CT_AC_Version.txt
  MR_PET/tmp/mprage.nii               →  MR_PET/MPRAGE_spm.nii (when available)
  MR_PET/tmp/mprage_normalized.nii    →  MR_PET/MPRAGE_spm_normalized.nii (when available)
  │
  ┌─ if config.cleanup_on_success ─┐
  │  rmdir MR_PET/tmp/ (recursive) │
  └─────────────────────────────────┘
```

Same promotion logic as the local pipeline. All shipped Launchpad profiles set
`config.cleanup_on_success = true`, so the local `MR_PET/tmp/` directory is
removed after successful promotion. If cleanup is disabled, or the run fails or
is interrupted, the downloaded intermediates are retained; this is independent
of the remote-scratch `keep_tmp` option described above.

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
│   ├── MPRAGE_spm.nii          ← promoted seed input, when available
│   ├── MPRAGE_spm_normalized.nii ← promoted normalized input, when available
│   ├── pseudo_CT_<profile>_<runid>.log
│   ├── pseudo_CT_profile_summary.txt
│   └── tmp/                    ← retained only when cleanup is disabled or the run fails
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
| Aliasing/recentering controls | Independent local facade requests | Only remote `check_aliasing`; no local recentering |
| Pipeline stages | All in one MATLAB session | Split across local + remote |
| Output promotion | From `tmp/` to `MR_PET/` | SCP fetch → local processing → promote |
| Debug access | All intermediates available immediately | Requires `keep_tmp` on remote |

---

## References

- [Local Pipeline](pipeline-local.md) — the equivalent local execution stages
- [Parity Assessment](parity-assessment.md) — numerical reproducibility findings
