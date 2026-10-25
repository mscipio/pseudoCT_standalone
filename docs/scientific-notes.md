# Scientific method and evidence

## Method

This software implements the SPM8-based atlas method described by Izquierdo-Garcia et al., *An SPM8-based Approach for Attenuation Correction Combining Segmentation and Non-rigid Template Formation: Application to Simultaneous PET/MR Brain Imaging*, *Journal of Nuclear Medicine* 2014;55(11):1825–1830. It combines tissue segmentation and non-rigid template formation to generate a subject-specific pseudoCT attenuation map from a T1-weighted MPRAGE. Cite the publication when using the method. The software implementation should also be acknowledged as appropriate; see the repository's [release history](../CHANGELOG.md).

## Current and legacy implementations

`current` is the MATLAB source processing path; `legacy-v2` is the compiled v2.0 backend (Aether lineage). Local and remote execution are separate choices from implementation. The two implementations follow different numerical paths, so results are not assumed to be universally equivalent.

One controlled MLSC CURRENT dataset produced an attenuation map byte-identical to its local-current reference. This is a bounded finding for that dataset and those exact artifacts, not a general equivalence claim. The v3.0.2 corrective release changed installation-path resolution and did not change the compiled scientific backend or add a new scientific run. The published v3.0.2 archive contains the current local CURRENT source, in which the local facade delegates preparation and computation to the shared `pseudo_CT_current_prepare`/`pseudo_CT_current_compute` helpers; the controlled MLSC CURRENT evidence above applies unchanged, and no additional validation is claimed for the refactored local facade. Always inspect the generated QC and output.

Historical comparisons distinguish LocalLegacy/MLSCLegacy references from LaunchpadLegacy. Separate matched October 19, v2.6.0/v2.6.4 archives were compared on 40 NIfTI stages; these are distinct historical reference paths, not interchangeable labels for current processing. A historical recentering “No” comparison is not the current default (“Yes”). Launchpad ignores the local recentering setting; only the remote aliasing check is forwarded, a workflow limitation rather than proof of numerical equivalence.

The bounded six-profile experiment is scientific comparison evidence across those profile paths. A separate user-accepted MLSC production run (Slurm job `10515471`) completed with exit code 0 in 43m50; one subject succeeded, zero failed, and MLSC result/copyback, DICOM output, output promotion, and cleanup were verified. The accepted executable described by the artifact provenance record is current-lineage PseudoCT v3 compiled using MATLAB R2010b, not historical Aether v2; its exact association with job `10515471` is not independently verified. The user-supplied `att_map.nii` SHA-256 is `1517efbe3fbb8e0f4df3fb3b2a4e40c387ba09fbcbac326496fe47cf8a6981ff`. For this dataset, the map was byte-identical to `local-current`, `local-legacy`, `mlsc-legacy`, and `mlsc-current-r2010b`, and differed from R2026a `mlsc-current` and `launchpad-legacy`. These findings apply only to this dataset, output, and artifacts; they do not establish universal equivalence, full-workflow parity, clinical correctness, or accuracy superiority of any profile. The dirty source fingerprint was not independently reconstructed; see the [artifact provenance record](../RELEASE_PROVENANCE_v3.1.0.md).

In a controlled host comparison, New Segment differed between the historical host and the Celer R2010 compiled/interpreted paths; the latter matched each other while following a different iterative numerical path. CPU dispatch and system-math effects were not isolated independently, and thread pinning is not established as a universal fix. These observations are host- and dataset-bounded; they do not establish a universal cause or parity guarantee.

## Interpretation and limitations

- The reported comparisons are bounded to specific datasets, software artifacts, and environments. They do not establish universal parity or clinical correctness.
- Host/runtime numerical behavior can affect intermediate results; evidence does not isolate every contributing factor.
- Visual review remains necessary: inspect the MPRAGE/pseudoCT fusion QC and scroll through the final volume for misregistration, missing anatomy, and abnormal attenuation outside the head.
- The source version metadata is 3.1.1; v3.0.2 is the previous published archive in the preserved release history, while v3.0.0 and v3.0.1 remain withdrawn. No production deployment is claimed.
