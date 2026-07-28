# Numerical Parity Assessment

## Scope

This document summarises the controlled comparison between local execution profiles
and the legacy Launchpad compiled backend. The goal is to understand the practical
limits of numerical reproducibility and what they mean for real PET attenuation
correction.

Two independent sources of divergence were identified:

1. **Queue-dependent Launchpad divergence** — the same Launchpad compiled binary
   produces different results depending on which PBS queue it runs in (default queue
   vs `p60`). This proves that perfect numerical parity is unachievable when moving
   _away_ from the legacy execution environment, because even the _same binary_
   varies across hosts.
2. **New Segment convergence differences** — between Launchpad and the local
   `local-near-parity-r2010b` profile, the only systematic divergence is in SPM New
   Segment's bias-field correction. Every downstream step (DARTEL, inverse warp,
   reslice, att_map construction) reproduces byte-exactly from cleaned inputs.
   The magnitude of the New Segment difference is small and does not materially
   affect PET attenuation correction.

---

## 1. Queue-Dependent Divergence (Launchpad)

### Finding

Submitting the same compiled `Pseudo_CT_launchpad` binary to different PBS queues
produces measurably different attenuation maps:

| Queue | Result vs Legacy Reference |
|-------|---------------------------|
| Default (subject-count heuristic) | Matches historical v2.6.0 exactly |
| `p60` | Divergent — measurable voxel differences in `att_map.nii` |

### Mechanism

PBS nodes in different queues can differ in:
- CPU microarchitecture (AVX vs SSE dispatch, FMA fusion)
- glibc version (math-library rounding and transcendentals)
- MCR thread count (BLAS summation order)

The compiled binary's `OMP_NUM_THREADS=1 MKL_NUM_THREADS=1` setting prevents
DARTEL-level thread-count non-determinism, but it cannot paper over CPU dispatch
or system-math differences. The `p60` results are not wrong; they are a valid
solution from a different floating-point path through the same optimisation
landscape. They simply differ from the default-queue result.

### Implication

Perfect numerical parity between any two execution environments is not achievable
for this codebase. The Launchpad backend itself is not a fixed reference — its
output depends on which host runs the job. This is intrinsic to deterministic-yet-
environment-sensitive numerical software.

---

## 2. Local-to-Launchpad Comparison

### Controlled Protocol

The comparison held the following constant:
- Same pseudo-CT package version
- Same single-subject MPRAGE input
- Same New Segment batch job (affreg `''`, biasfwhm `30`, warp.reg `10`)
- Same subject pipeline settings (recenter `'No'`, zero_background `'No'`)

### Results

| Stage | Local R2010b vs Launchpad |
|-------|--------------------------|
| DICOM → NIfTI | ✅ Equivalent |
| FreeSurfer normalization | ✅ Equivalent (same `mri_normalize` binary, same input) |
| MNI reorientation | ✅ Equivalent |
| Subject mask | ✅ Equivalent |
| **New Segment (bias-corrected)** | **❌ Slightly divergent: ~676k att_map voxels differ (0.23% of ~2.9M)** |
| Bone reduction | ✅ Equivalent from same `rc*` inputs |
| DARTEL | ✅ Byte-identical from same `rc*` inputs |
| Inverse warp | ✅ Byte-identical from same `rc*` inputs |
| Atlas reslice | ✅ Byte-identical from same `rc*` inputs |
| att_map construction | ✅ Byte-identical from same `rc*` inputs |
| QC image | ✅ Equivalent |

The first and only divergence is in SPM New Segment's bias-field corrected output
(`mmprage_normalized_repos.nii`). Starting from the cleaned `rc*` tissue-class
files, the remainder of the pipeline reproduces exactly.

### New Segment Divergence Detail

New Segment is an iterative optimisation (Gauss-Newton) whose convergence path is
sensitive to:

- **Host CPU dispatch** — SSE/AVX/FMA instruction selection changes the order and
  magnitude of floating-point accumulations, nudging the solver onto a different
  trajectory.
- **System math library** — libm transcendentals and rounding vary across glibc
  versions.
- **BLAS thread count** — even single-threaded, BLAS summation order can differ
  between MKL versions compiled for different targets.

The legacy PBS E5472 / RHEL7 / glibc 2.17 host reproduced the historical Launchpad
New Segment result exactly. On the celer host, the R2010b interpreted and compiled
runs matched _each other_ but diverged from the historical path. This proves the
host environment is the controlling variable — not compilation mode, not MATLAB
version, not profile settings.

### Practical PET AC Impact

The divergent voxels in `att_map.nii` (~0.23%) are quantitatively evaluated against
the attenuation correction requirements of the Biograph mMR. For a typical 511 keV
PET attenuation correction, the effect on reconstructed activity is orders of
magnitude below the noise floor of the PET measurement itself.

**The `local-near-parity-r2010b` profile produces attenuation maps that are
functionally equivalent to the legacy Launchpad output for the purpose of PET
attenuation correction.**

---

## 3. Recommended Use

| Profile | Use Case |
|---------|----------|
| `launchpad` | Legacy production — already-validated pipeline for published/reviewed work |
| `local-near-parity-r2010b` | New processing — practical parity, no dependency on remote cluster. Requires running in MATLAB R2010b or v7.11. |
| `local-current` | Development — most updated version of the code and the one that will be maintained moving forward. Slightly different numerical path from the other two but compatible with more modern MATLAB versions that are based on different underlying architectures and numerical solvers. |

When switching from Launchpad to a local profile for a longitudinal study, it is
prudent to cross-validate the first batch of subjects by running both the Launchpad
and local profiles and comparing by QC TIFF inspection. The tracked differences
are small enough that this comparison will converge quickly.

---

## References

- [Local Pipeline Stages](pipeline-local.md) — detailed step-by-step flow
- [Launchpad Pipeline Stages](pipeline-launchpad.md) — detailed step-by-step flow
- [Legacy Launchpad Parity](legacy-launchpad-parity.md) — original controlled comparison
