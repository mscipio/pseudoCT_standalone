# launchpad-matlab-compat Specification

## Purpose

MATLAB version compatibility across the Launchpad pipeline's local-side code. Fixes two confirmed version-sensitive bugs and adds diagnostic observability for silent cluster-side failures.

## Requirements

### Requirement: Pre-R2013a strsplit Backport

`run_launchpad_cmd_return.m` MUST NOT call `strsplit`. PBS job-number parsing SHALL use `regexp(..., '\.', 'split')`, available since R14 and compatible with the cluster's R2010b runtime floor.

#### Scenario: PBS job number parsed on R2010b

- GIVEN local MATLAB R2010b and a PBS job-number line containing `.`
- WHEN the helper parses the line at line 44
- THEN the integer job number is returned without referencing `strsplit`
- AND the result matches the prior `strsplit`-based output for the same input

#### Scenario: Job-number line with no dot

- GIVEN a job-number line with no `.`
- WHEN parsed by the regexp split mechanism
- THEN the full line is returned as a single-element cell array

### Requirement: Post-R2015a numel Colon Fix

The DICOM loop in `nii2dcm_header_copy_vb20_david.m:82` MUST use a scalar endpoint. `for m=1:size(dicom_ref_all)` SHALL be replaced with `for m=1:numel(dicom_ref_all)`, scalar on every MATLAB release (R14–R2026a+).

#### Scenario: Multi-slice DICOM on R2026a

- GIVEN a DICOM directory with N slices and MATLAB R2026a
- WHEN the loop executes with `numel(dicom_ref_all)`
- THEN it iterates exactly N times and no "Colon operands must be real scalars" error is raised

#### Scenario: Single-slice DICOM

- GIVEN a DICOM directory with exactly 1 slice
- WHEN the loop runs
- THEN it iterates exactly 1 time and produces 1 output DICOM

### Requirement: Post-Copy-Back Missing-Output Diagnostics

When the cluster job exits 0 but `att_map.nii` is absent from the copy-back, the system MUST surface a diagnostic to stdout naming the subject, listing the temp-dir contents, and (when reachable) printing the first lines of the PBS `.o*`/`.e*` log files. The diagnostic SHALL degrade to the current opaque message when PBS logs are unreachable; the batch MUST NOT crash and MUST continue to the next subject.

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

### Requirement: Minimum MATLAB Version Documentation

The `run_pseudo_CT_launchpad.m` header and `src/config/defaults_pseudo_CT_launchpad.m` MUST document the committed minimum MATLAB version as R2010b (7.11), consistent with the cluster's compiled-app MCR runtime.

#### Scenario: Header documentation

- GIVEN a user reads `run_pseudo_CT_launchpad.m`
- WHEN they view the header comment block
- THEN a line states "Minimum supported MATLAB: R2010b" with a note matching the cluster runtime

#### Scenario: Defaults documentation

- GIVEN a user reads `src/config/defaults_pseudo_CT_launchpad.m`
- WHEN they view the help text
- THEN the minimum MATLAB version R2010b is documented
