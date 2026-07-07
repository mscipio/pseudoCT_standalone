# local-pipeline-qc Specification

## Purpose

Behavioral contract for the local (non-deployed) validation-image step at the end of the pseudo-CT pipeline. This domain is implementation-defined — the proposal states no spec-level capability change; this spec exists as a verification contract for the compatibility fix.

## Requirements

### Requirement: Validation TIFF Output Compatibility

The local pipeline QC step MUST produce `Fusion_MR_Pseudo_CT_validation.tiff` using only MATLAB I/O primitives. It MUST NOT depend on graphics-interaction APIs (`figure`, `imagesc`, `print`, `pause`, `close`) that are fragile across MATLAB releases from R2010b through R2026a.

The validation TIFF SHALL be written directly from the RGB composite returned by `quick_fusion_pseudo_ct` at approximately 300 DPI resolution.

| Output | Path | Format |
|--------|------|--------|
| Validation TIFF | `{processing_dir}/Fusion_MR_Pseudo_CT_validation.tiff` | RGB TIFF, ~300 DPI |

#### Scenario: Local pipeline on R2026a produces validation TIFF without error

- GIVEN a local pipeline run on MATLAB R2026a
- AND all atlas/DARTEL steps complete successfully
- WHEN the validation-image step executes
- THEN `Fusion_MR_Pseudo_CT_validation.tiff` is written to the processing directory
- AND no `InteractionsManager` or graphics-interaction errors are raised
- AND the pipeline continues to write the version file and finish

#### Scenario: Local pipeline on R2010b produces validation TIFF

- GIVEN a local pipeline run on MATLAB R2010b
- AND all atlas/DARTEL steps complete successfully
- WHEN the validation-image step executes
- THEN `Fusion_MR_Pseudo_CT_validation.tiff` is written
- AND the pipeline exits normally

#### Scenario: Validation TIFF is visibly correct

- GIVEN a completed local pipeline run
- AND a known-good subject MPRAGE input
- WHEN the output `Fusion_MR_Pseudo_CT_validation.tiff` is inspected
- THEN the image SHALL contain a fused MR/pseudo-CT overlay matching the pipeline's expected output
- AND the visible content is indistinguishable from the output produced by the prior graphics-based path

### Requirement: Scope Boundary

The validation-image fix MUST NOT alter the SPM Interactive window lifecycle (`spm('CreateIntWin','on')` / `close(fh)`). The fix MUST NOT modify `quick_fusion_pseudo_ct`, the attenuation-map write, the version-file write, or any other pipeline step. The deployed-mode `imwrite` path remains unchanged.

#### Scenario: SPM Interactive window unaffected

- GIVEN the local pipeline runs with the validation-image fix applied
- WHEN the pipeline reaches the SPM Interactive window creation at the start of processing
- THEN the window is opened and closed exactly as before the fix
- AND no new errors are introduced at `close(fh)`
