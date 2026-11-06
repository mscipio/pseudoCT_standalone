# Scientific method and evidence

## Method and attribution

PseudoCT implements the SPM8-based atlas method described by Izquierdo-Garcia
et al., *An SPM8-based Approach for Attenuation Correction Combining
Segmentation and Non-rigid Template Formation: Application to Simultaneous
PET/MR Brain Imaging*, *Journal of Nuclear Medicine* 2014;55(11):1825–1830. The
method combines tissue segmentation and non-rigid template formation to
generate a subject-specific attenuation map from a T1-weighted MPRAGE. Cite
the publication when using the method; acknowledge the software and its
maintainers as appropriate. See the repository's [release history](../CHANGELOG.md).

The four supported profiles (`local`, `mlsc`, `local-mprage-only`, and
`mlsc-mprage-only`) use the same compiled scientific payload. Profile choice
controls execution location and input/output policy, not a separate algorithm.
The two MPRAGE-only profiles omit UMAP collection and DICOM output.

## Bounded comparison evidence

One controlled MLSC dataset produced an attenuation map byte-identical to its
matched Local reference. This is evidence for that dataset and those exact
artifacts only; it is not a general parity result. Existing archived
comparisons also include older scientific artifacts and execution paths. They
are historical evidence, not supported profile choices or general-purpose
reference outputs.

A user-accepted MLSC production run (Slurm job `10515471`) was recorded as
completed with exit code 0 in 43m50; one subject succeeded, no subject failed,
and MLSC result/copy-back, DICOM output, output promotion, and cleanup were
verified. The accepted executable described by the artifact provenance record
was compiled with MATLAB R2010b. Its exact association with job `10515471` was
not independently verified. The
user-supplied `att_map.nii` SHA-256 was
`1517efbe3fbb8e0f4df3fb3b2a4e40c387ba09fbcbac326496fe47cf8a6981ff`.
The source fingerprint for that run was not independently reconstructed.

In a controlled host comparison, New Segment differed between the historical
host and the Celer R2010 compiled/interpreted paths; the two Celer paths
matched each other while following a different iterative numerical path. CPU
dispatch and system-math effects were not isolated independently, and thread
pinning is not established as a universal fix.

These records are dataset-, artifact-, and environment-bounded. They do not
establish universal equivalence, full-workflow parity, clinical correctness,
or accuracy superiority of any implementation or execution environment.
Comparison tools remain available under `tests/manual/` and `scripts/`; they
must be used only with authorized existing data and are not run by the
automated test commands.

## Interpretation and quality control

- Intermediate numerical results may depend on host and runtime behavior; the
  available evidence does not isolate every contributing factor.
- Inspect the MPRAGE/pseudoCT fusion QC and scroll through the final volume for
  misregistration, missing anatomy, and abnormal attenuation outside the
  head.
- A successful scheduler state or process exit is not itself proof of verified
  scientific completion; current MLSC completion requires verified outputs
  and copy-back evidence.
- The source version metadata is 3.2.0; the v3.2.0-rc2 material was recorded
  as a candidate, not a production deployment claim. The release history
  identifies the prior published archive and withdrawn versions.

## Provenance and licensing

The dependency lock records local identities and hashes; it does not grant
redistribution rights or replace complete provenance and license review.
Preserve the repository and dependency license files and notices. Public
packaging remains subject to dependency-specific provenance, compatibility,
and redistribution clearance.
