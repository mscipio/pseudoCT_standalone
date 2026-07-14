# Delta for launchpad-matlab-compat

## ADDED Requirements

### Requirement: NIfTI Input Staging at Entry Time

When the pipeline receives a NIfTI input (`.nii` or `.nii.gz`), the system MUST stage the file into `MR_PET/tmp/mprage.nii` at entry time, before any downstream lookup that assumes the NIfTI lives in `temp_dir`. The standardized name `mprage.nii` SHALL be used regardless of the original basename. The original input file MUST NOT be deleted by staging.

#### Scenario: NIfTI input staged as mprage.nii

- GIVEN a NIfTI input at any path (e.g., `MR/MEMPRAGE/MEMPRAGE_BC_denoised.nii`)
- WHEN the entry script processes the subject
- THEN `MR_PET/tmp/mprage.nii` exists and matches the input content
- AND the standardized name is used regardless of original basename

#### Scenario: DICOM input — NIfTI staging skipped

- GIVEN a DICOM input directory (no `.nii` file in the input)
- WHEN the entry script processes the subject
- THEN the NIfTI staging step is skipped
- AND the existing DICOM-to-NIfTI conversion continues to populate `MR_PET/tmp/mprage.nii` as before

#### Scenario: NIfTI input matches downstream path expectation

- GIVEN a NIfTI input that was staged into `MR_PET/tmp/mprage.nii` at entry time
- WHEN the cluster copies back `att_map.nii` to `MR_PET/tmp/`
- THEN downstream promotion and DICOM write succeed without a path-mismatch error
- AND no "Pseudo-CT processing finished without creating" diagnostic is emitted

## MODIFIED Requirements

### Requirement: Post-Copy-Back Missing-Output Diagnostics

When the cluster job exits 0 but `att_map.nii` is absent from the copy-back, the system MUST surface a diagnostic to stdout naming the subject, listing the temp-dir contents, and (when reachable) printing the first lines of the PBS `.o*`/`.e*` log files. The diagnostic SHALL degrade to the current opaque message when PBS logs are unreachable; the batch MUST NOT crash and MUST continue to the next subject. The NIfTI-input path mismatch is no longer a trigger for this diagnostic, since NIfTI inputs are staged into `MR_PET/tmp/mprage.nii` at entry time; the diagnostic remains valuable for other failure modes (SSH copy-back failure, cluster crash, disk-full, remote app non-zero exit masked by wrapper).
(Previously: Triggered by the same condition, with no carve-out for the NIfTI-input path mismatch.)

#### Scenario: Silent failure with reachable PBS logs

- GIVEN a cluster job exiting 0 with no `att_map.nii` in copy-back
- WHEN the entry script processes that subject
- THEN stdout contains the subject path, `temp_dir` listing, and head of the PBS log files
- AND the batch continues to the next subject

#### Scenario: PBS logs unreachable

- GIVEN `att_map.nii` missing after copy-back and PBS log path unreachable
- WHEN diagnostics attempt the log fetch
- THEN the system falls through to the current opaque message via try/catch
- AND remaining subjects continue processing

#### Scenario: Successful job — no false diagnostics

- GIVEN a cluster job that produces `att_map.nii` in the copy-back
- WHEN the entry script processes that subject
- THEN no missing-output diagnostics are emitted
- AND the subject proceeds to DICOM conversion

#### Scenario: NIfTI input round-trip — no false diagnostics

- GIVEN a NIfTI input that was staged into `MR_PET/tmp/mprage.nii` at entry time and the cluster returns `att_map.nii` in copy-back
- WHEN the entry script processes that subject
- THEN no missing-output diagnostics are emitted
- AND the subject proceeds to DICOM conversion

## REMOVED Requirements

None.

## RENAMED Requirements

None.
