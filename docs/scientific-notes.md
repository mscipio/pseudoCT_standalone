# Scientific method and evidence

This page owns the scientific method, the bounded evidence and the interpretation
limits. Installation is in [Installation](installation.md); packaging and build
verification are in [Release catalog and layout](releases.md); the release history
is in [CHANGELOG](../CHANGELOG.md).

## Method and attribution

PseudoCT implements the SPM8-based atlas method described by Izquierdo-Garcia
et al., *An SPM8-based Approach for Attenuation Correction Combining
Segmentation and Non-rigid Template Formation: Application to Simultaneous
PET/MR Brain Imaging*, *Journal of Nuclear Medicine* 2014;55(11):1825–1830. The
method combines tissue segmentation and non-rigid template formation to generate
a subject-specific attenuation map from a T1-weighted MPRAGE. Cite the publication
when using the method, and acknowledge the software and its maintainers as
appropriate.

The four supported profiles (`local`, `mlsc`, `local-mprage-only` and
`mlsc-mprage-only`) use the same compiled scientific payload. Profile choice
controls the execution location and the input/output policy, not a separate
algorithm. The two MPRAGE-only profiles omit UMAP collection and DICOM output.

## Bounded comparison evidence

The records below are bounded to the datasets, artifacts and environments named
in them. None establishes universal equivalence, full-workflow parity, clinical
correctness or accuracy superiority of any implementation or execution environment.

- **Controlled MLSC/local comparison:** one controlled MLSC dataset produced an
  attenuation map byte-identical to its matched Local reference. This is evidence
  for that dataset and those exact artifacts only.
- **Local R2010b comparison (maintainer-reported):** a compiled R2010b local
  end-to-end run ("t10") was reported as byte-identical to the v3.0.2 outputs for
  40 NIfTI, 2 TIFF and 128 DICOM files. The evidence record is not included in this
  repository, so this statement is the maintainer's report, not a result that this
  repository reproduces. The dataset and environment of that run are not identified here.
- **Accepted MLSC production run (Slurm job `10515471`):** recorded as completed with
  exit code 0 in 43m50; one subject succeeded, none failed, and MLSC result/copy-back,
  DICOM output, output promotion and cleanup were verified. The accepted executable
  described by the artifact provenance record was compiled with MATLAB R2010b. Its
  exact association with job `10515471` was not independently verified, and the
  source fingerprint for that run was not independently reconstructed. The
  user-supplied `att_map.nii` SHA-256 was
  `1517efbe3fbb8e0f4df3fb3b2a4e40c387ba09fbcbac326496fe47cf8a6981ff`.
- **Host-dependent numerics:** in a controlled host comparison, New Segment differed
  between the historical host and the Celer R2010 compiled/interpreted paths; the two
  Celer paths matched each other while following a different iterative numerical path. CPU dispatch and system-math effects were not isolated
  independently, and thread pinning is not established as a universal fix.
- Older archived comparisons include earlier scientific artifacts and execution
  paths. They are historical evidence, not supported profile choices or general-purpose
  reference outputs.

Comparison tools remain available under `tests/manual/` and `scripts/`. They must be
used only with authorized existing data, and the automated test commands do not run
them (see [Tests](../tests/README.md)).

## Interpretation and quality control

- Intermediate numerical results may depend on host and runtime behavior; the
  available evidence does not isolate every contributing factor.
- Inspect the MPRAGE/pseudoCT fusion QC and scroll through the final volume for
  misregistration, missing anatomy and abnormal attenuation outside the head.
- A successful scheduler state or process exit is not proof of verified scientific
  completion. MLSC completion requires verified outputs and copy-back evidence.
- Run logs and JSONL events record what happened for each subject, but they do not
  replace the QC review (see [Output, logs and progress](headless-cli.md#output-logs-and-progress)).

## Provenance and licensing

Dependency provenance and redistribution status are recorded in
[`dependencies.lock.json`](../dependencies.lock.json). The lock records local
identities and hashes; it does not grant redistribution rights or replace complete
provenance and license review. Preserve the repository and dependency license files
and notices. Public packaging remains blocked by the gate in
[Publication status](releases.md#publication).
