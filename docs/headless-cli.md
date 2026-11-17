# Headless API and CLI

This page is the reference for the terminal launcher (`bin/pseudoct`): options, validation
and submission, output files, exit codes and cancellation. Installation is in
[Installation](installation.md), and packaging and runtime selection are in
[Release catalog and layout](releases.md). `bin/pseudoct --help` prints the usage text of
the installed launcher. The step-by-step workflow for the window is in the
[PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/).

Developer material (the MATLAB request and result contract, the `headless` and `resolve`
operations) is at the end of this page.

## Entry points

```sh
bin/pseudoct validate --profile local \
  --mprage /subject/MR/MPRAGE/one.dcm \
  --umap /subject/MR/UMAP/one.dcm --format jsonl
bin/pseudoct run --profile local \
  --mprage /subject/MR/MPRAGE/one.dcm \
  --umap /subject/MR/UMAP/one.dcm --format jsonl
```

`validate` checks a request and is optional. `run` validates the same request and then submits it, and does not need a prior `validate`;
see [Validation and submission](#validation-and-submission).

One or more subjects can be given as a [subjects file](#subjects-file), with the same syntax
for one subject or many:

```sh
bin/pseudoct check-subjects --profile mlsc --subjects subjects.txt
bin/pseudoct run --profile mlsc --subjects subjects.txt --mcr R2019b
```

`check-subjects` is read-only: it checks the file, its paths and its DICOM series, and starts no
MATLAB Runtime, authentication or processing. `validate` additionally checks output folders and
runtime dependencies. `check-subjects --format tsv` prints the
[machine-readable table](#check-subjects-table) instead of the readable report.

The window (`run_pseudo_CT`) and the launcher share the same rules. The window checks its
subject list with `check-subjects --format tsv`, then runs `bin/pseudoct run --subjects FILE`
with a text result and reads the final result record from a file.

## Release selection (installed distribution)

An installed distribution (`runtimes/` beside `bin/`) ships one compiled release per
MATLAB Runtime. `bin/pseudoct` selects one of them for `run`, `headless` and `resolve`.
A repository checkout refuses `--mcr` and `--mcr-root`, and `resolve` requires an installed
distribution.

- `--mcr LABEL`: the release, as an exact catalog label such as `R2019b`. The default is the
  catalog default, R2010b.
- `--mcr-root DIR`: the MATLAB Runtime root. Without it, the root is the catalog location
  `/usr/pubsw/common/matlab/<D>` of the release, where `<D>` is the first two dotted
  components of its `matlab_version`. The runtime identity is always validated against the
  catalog, so a root never bypasses that check.
- `--list-releases`: prints one line per installed release, as
  `label<TAB>mcr_version<TAB>default|-`. It needs no MATLAB or MCR. In a repository checkout it
  lists every entry in `config/releases.json`.

An unknown label, a bad `--mcr-root` value or a usage error exits `64`. An incomplete release,
an unsupported architecture, or a missing or mismatched MATLAB Runtime exits `69`. Details are
in [Releases](releases.md#release-and-matlab-runtime-root-selection).

## Options (`validate`, `run`)

- `--profile NAME` (required): one of the four canonical profiles (`local`, `mlsc`,
  `local-mprage-only`, `mlsc-mprage-only`); see [Installation](installation.md#supported-profiles).
- `--subjects FILE`: one or more subjects from a [subjects file](#subjects-file). The whole file
  is checked before runtime selection, MATLAB, authentication or any file creation; every error
  is reported together and the launcher exits `64`. Use one input form: `--subjects`,
  `--mprage`/`--umap` or `--config`.
- `--mprage FILE [--umap FILE]`: one subject. On standard profiles the UMAP may be omitted;
  the launcher then discovers it from the subject layout. MPRAGE-only profiles reject `--umap`.
- `--config job.json`: several subjects. The JSON object has a non-empty `mprage` string
  array and an optional `umap` string array, paired by position:

  ```json
  {"mprage":["/data/one/MPRAGE.dcm","/data/two/MPRAGE.dcm"],
   "umap":["/data/one/UMAP.dcm","/data/two/UMAP.dcm"]}
  ```

- `--correct-aliasing yes|no`, `--recenter-before-normalization yes|no`,
  `--cleanup-on-success yes|no`: override the profile defaults.
- `--max-concurrent N` (`run`, `validate`): how many subjects execute at once, an integer from 1
  to 32. The default 1 runs the subjects one after another. See
  [Concurrent subjects](#concurrent-subjects).
- `--group-account ACCOUNT` (MLSC): the account to use. Blank or omitted: the first discovered
  account is selected, or, at a terminal prompt, you are asked for one.
- `--check-account` (MLSC, `validate` only): logs in, discovers the MLSC accounts and applies
  the account rule, then stops. It never submits: the result reports `submission_status`
  `not_attempted`, no job IDs, and no `sbatch` call is made. An invalid explicit account returns
  `INVALID_GROUP_ACCOUNT` (exit `66`). Combining it with another action or a non-MLSC profile exits
  `64`. It makes one login attempt; the retry rules below apply to `run`.
- `--host-key-file FILE` (MLSC): the strict host-key input for the cluster connection.
- `--format text|jsonl`: output format (default `text`). See
  [Output, logs and progress](#output-logs-and-progress).
- `--result-file PATH`: also writes the final JSON result record to `PATH`, atomically (a
  temporary file is renamed over `PATH`), in either format. Standard output is unchanged. The
  directory must exist and be writable.
- `--current-artifact-root PATH`: **developer only.** Accepted only by the MLSC profiles; the local
  profiles reject it with exit `64`. Installed distributions do not need it.
- `--credential-handoff FILE` (MLSC, `run` and `authenticate`): an existing single-use credential file,
  consumed on use and never reusable. It is created in MATLAB with `pseudo_CT_credentials('store', ...)`
  on the same host, as the user that runs the launcher. The window creates its own handoffs; do not
  reuse those. It replaces the terminal prompts, so `run` needs no terminal. Secrets are never accepted
  on the command line. See the [integration guide](THIRD_PARTY_INTEGRATION.md#a5-authentication-and-credentials).

## Subjects file

A subjects file lists each subject's MPRAGE and UMAP together:

```ini
# pseudoCT subjects v1

[Subject_001]
MPRAGE = /data/subject01/T1.nii.gz
UMAP = /data/subject01/MR/UMAP/image.dcm

[Subject_002]
MPRAGE = "/data/subject 02/MR/MPRAGE"
UMAP = "/data/subject 02/MR/UMAP"
```

Grammar:

- The file is UTF-8 text (a byte-order mark and Windows line endings are accepted).
- Blank lines are ignored. A line whose first non-blank character is `#` is a comment; there
  are no inline comments, so `#` later in a line is part of the value.
- `[SubjectID]` starts a subject. An identifier has 1 to 64 letters, digits, `.`, `_` or `-`,
  starts with a letter or digit, and is unique (compared without regard to case).
- `KEY = value` sets a field of the current subject. Spaces or tabs around `=` are optional,
  and the line is split at its first `=`, so a value may contain `=`. Keys are `MPRAGE` and
  `UMAP`, in any letter case; each may appear once per subject.
- A value may be enclosed in matching `"` or `'` quotes. The text between them is taken
  literally, including spaces, the other quote character and `\` (no escape sequences), so
  Windows-style backslashes are kept. Without quotes, the value is the text after `=` with
  surrounding spaces and tabs removed. A value that starts with a quote must end with the
  same quote.
- A relative path is resolved against the folder that contains the subjects file. `~` is not
  expanded.
- Every subject needs `MPRAGE`. `UMAP` is required by the `local` and `mlsc` profiles and is
  refused by the MPRAGE-only profiles. Execution settings (profile, release, processing
  options) are command-line options and are refused in the file.

Inputs:

- MPRAGE: a NIfTI file (`.nii`, `.nii.gz`), a representative DICOM file of the series, or a
  DICOM series directory. UMAP: a DICOM file or a DICOM series directory.
- A directory must hold exactly one DICOM image series (one SeriesInstanceUID among its
  image files) directly inside it; subdirectories are not searched. Non-DICOM files, and
  DICOM objects without image dimensions (Rows and Columns), such as reports or raw data,
  are ignored and reported. The series' first image file, by name, is passed to the
  pipeline as the representative file, and the existing DICOM conversion
  collects the rest of the series from the same folder. A directory with several series, or
  with none, is refused with the series it found; pseudoCT never chooses between series.
- Two subjects may not use the same MPRAGE input.

Errors list the file, line, subject and reason, for example:

```text
pseudoct: the subjects file subjects.txt is invalid (2 errors); nothing was started:
  subjects.txt:7: subject Subject_002: unmatched double quote in the MPRAGE value
  subjects.txt:12: subject Subject_003: MPRAGE directory /data/s3/MR: the directory contains 2 DICOM series (...)
```

### Check-subjects table

`bin/pseudoct check-subjects --profile P --subjects FILE --format tsv` performs the same check
as the readable report and prints a table on standard output, UTF-8, one record per line
(`\n`), fields separated by one tab. This contract is stable; version 1:

- First line: `pseudoct-subjects-tsv<TAB>1` (format name and version). A consumer refuses
  any other first line.
- Valid file: one `subject` row per subject, in file order, with 10 fields:
  `subject`, ID, then for MPRAGE and then for UMAP four fields each: the value as written
  in the file, its absolute path (relative values resolved against the folder of the
  subjects file), the resolved input file passed to the pipeline (for a DICOM series
  directory, its representative file) and a detail text (`NIfTI file`, `DICOM file`, or
  `DICOM series directory: N image files, series S 'description'`). The four UMAP fields
  are empty for MPRAGE-only profiles.
- Invalid file: no `subject` rows; one `error` row per error, ordered by line, with 4 fields:
  `error`, the line number (empty when the error concerns the whole file), the subject ID
  (empty when none), and the message.
- Last line: `end<TAB>SUBJECTS<TAB>ERRORS` with the number of `subject` and `error` rows.
  A table without it is incomplete.
- Escapes in every field: `\` is written `\\`, tab `\t`, line feed `\n`, carriage return
  `\r`, and any other control character (below U+0020, and U+007F) `\xHH` with two hex
  digits. No other escape is used; all other text is written unchanged.
- Exit status: `0` valid (table printed), `64` invalid file (table with error rows printed)
  or usage error (no table; message on standard error), `69` the file could not be checked
  (no table; a one-line message).

Subjects run one after another, as with `--config`. In MATLAB, `run_pseudo_CT('Profile', P,
'Subject', 'subjects.txt')` passes the file to the launcher, and `'Subject', {{MPRAGE, UMAP},
...}` writes the pairs to a temporary subjects file first.

Credentials are never accepted as command-line options or environment variables. For MLSC, the
launcher asks for the username and password at the terminal (with echo off), and then for the
account when `--group-account` is absent.

### Environment variable: `PSEUDOCT_AUTH_RETRY_LIMIT`

Limits the number of retries of the **terminal** login prompt in `run` for MLSC.

- Unset or empty (the default): no limit. After each rejected login, the launcher asks for the
  password again, and you cancel with an empty input.
- `N` (a non-negative integer): `N` retries after the first failed attempt. `0` means no retry. When
  the limit is exceeded, the run stops with exit `66` and no submission is attempted.
- Any other value exits `64` when the terminal prompt is used.

Only these authentication failures re-prompt: `AUTHENTICATION_FAILED`, and `INVALID_GROUP_ACCOUNT` when
the account was prompted. A host-key problem (`HOST_KEY_UNAVAILABLE`) and other errors are not retried:
the run stops with exit `66`. The window (GUI) retries in place: after a rejected login, the window
shows the failure and reopens the login dialog, without pressing Run again. Cancelling the dialog submits nothing.

## Validation and submission

- **Validate** (`validate`, the validation step of a window Run, or a `validate` request) resolves
  and checks the selected profile, inputs, outputs, dependencies and, for MLSC, the artifact integrity.
  It does not authenticate, contact remote services, or run scientific processing. The only exception
  is `--check-account` (see [Options](#options-validate-run)), which logs in and checks the account
  but still never submits. A successful validation reports `ready`; it is not a processing result.
- **Submit** (`run`, the submission step of a window Run, or a `submit` request) uses the resolved
  job bound by a successful validation and rechecks inputs and artifacts. Changed or stale inputs fail
  closed. Local submit runs synchronously in the current invocation. MLSC submit logs in (a terminal
  prompt, or the one-time credential file of the window), submits to Slurm and monitors the job until a
  verified or an unverified outcome (see [Cancellation and interruption](#cancellation-and-interruption)).
- **Window Run**: validates the profile, input files and options, then submits them when validation
  passes; a failed validation submits nothing. For MLSC, Run validates without logging in, then asks for
  the username, password and optional account in a dialog, and passes only a single-use credential file
  path to the launcher. A cancelled dialog submits nothing.

## Output, logs and progress

Each requested subject gets a set of files in its `MR_PET` folder. Their names share one stem,
`pseudoct-<kind>-<UTC>-<invocationUUID>`, where `<UTC>` is the start time (`YYYYMMDDTHHMMSSZ`) and
`<invocationUUID>` identifies the invocation.

- **Final outputs** (`<subject>/MR_PET/`): `att_map.nii` (attenuation map), the QC image
  `Fusion_MR_Pseudo_CT_validation.tiff` and the version record `Pseudo_CT_AC_Version.txt`. DICOM output
  goes to `<subject>/MR/pseudo_muMAP/` for the standard profiles only. Inspect the QC image before use
  (see [Scientific notes](scientific-notes.md#interpretation-and-quality-control)).
- **Run log** (`<subject>/MR_PET/pseudoct-run-<UTC>-<invocationUUID>.log`): the detailed run log, one
  owner-only file per subject. It is created after validation and output-location resolution, and the
  pipeline never deletes or prunes it. It contains the detailed line of each event, including heartbeat
  lines and the raw scientific and backend diagnostics. It is not a copy of the console table.
- **Structured record** (`<subject>/MR_PET/pseudoct-run-<UTC>-<invocationUUID>.jsonl`): one JSON object per
  line, with typed records: `stage` records (stage identifier, index of 10, status), `run` records (outcome
  `SUCCEEDED`, `FAILED` or `CANCELLED`) and `diagnostic` records (`warning`, `error` or `lifecycle`). It is
  written at phase boundaries, and it is kept after success, failure and cancellation. Heartbeats are not
  written to it. It is the canonical machine-readable record of the run.
- **Validation record** (`validate` only): one file, `<subject>/MR_PET/pseudoct-validate-<UTC>-<invocationUUID>.jsonl`,
  containing one result record. It is written only when the subject's `MR_PET` folder can be resolved. If it
  cannot be resolved, stderr says that no validation record file was written. No run log is created by
  validation.
- **Secrets**: passwords and login details are not written to any of these files.
- **Intermediates**: `<subject>/MR_PET/tmp/` holds per-subject working files. They are removed after
  successful promotion when `cleanup_on_success` is true, and kept when promotion fails or cleanup is off.
  The launcher's private invocation directory under `MR_PET/tmp/` (request and result MAT files, handoff
  path, captured MATLAB diagnostics) is removed when the launcher exits. The run log and the JSONL file
  are never removed by the launcher.

**Progress**:

- `--format text` (default): progress rows are printed to the console. Each stage row carries the subject
  index, the stage number `[n/10]` (printed once per stage) and the `STATUS`. Stages that did not run are
  shown as `SKIPPED` with the reason where known (MPRAGE-only profiles skip stages 9 and 10 by policy);
  otherwise the reason is `not run`. `WARN` and `ERROR` rows report problems. A `still running (elapsed …)`
  line shows that a long step is progressing. The final summary gives the outcome, the dispatch and
  submission status, the scientific completion status, the MLSC account and job IDs, and the run-log paths.
  - **Known limitation (MLSC):** post-processing for stage 5 is not reported as a numbered stage. Its work
    appears as `not reported`.
- `--format jsonl`: one JSON record per line on standard output, for progress and for the final result. The
  final result record carries `outcome`, `exit_code`, the submission and scientific completion fields and, for
  MLSC, the job IDs. It does not carry run-log paths; those are printed only in the text summary. Anything that
  is not a progress or result record goes to stderr. The field-by-field contract for external applications is in the
  [third-party integration guide](THIRD_PARTY_INTEGRATION.md).
- `--result-file PATH` writes the final result record as JSON to `PATH` in either format.

## Exit codes

`bin/pseudoct validate` and `bin/pseudoct run` return:

| Code | Meaning |
|---:|---|
| `0` | Validation passed, or the run completed with verified results. |
| `64` | Usage or configuration error. |
| `65` | Invalid request or validation failure. |
| `66` | Authentication failure. |
| `67` | Submission failure. |
| `68` | Scientific failure, or completion not verified. |
| `69` | Launcher or runtime failure. |
| `70` | MATLAB dispatch or runtime failure (listed in `--help`): the MATLAB CLI support, diagnostics or headless bootstrap could not start or returned no valid result. |
| `130` | `run` was cancelled (interrupt); the result record still lists every subject's outcome. |

A scheduler acceptance or a submitted job is not completion. Exit `0` for `run` requires verified
completion.

## Concurrent subjects

`--max-concurrent N` (MATLAB: `'MaxConcurrent', N`; window: **Subjects at once**) lets up to `N`
subjects of one request execute at the same time. One shared loop runs both backends: it starts
subjects in request order until `N` are active, polls them, finalizes each finished subject, and
starts the next one in the freed slot.

- **Local:** each active subject runs its own compiled worker (`pseudoct_pipeline` under the MATLAB
  Runtime, no MATLAB licence), with its own private temporary and Runtime cache folders.
- **MLSC:** each subject is its own Slurm job. A slot is held from submission until the job is
  terminal, so submitted, queued and running jobs all count against `N`. One login (one prompt or
  one handoff) and one SSH connection serve the whole request.
- Input preparation (stage 1) and finalization (stages 9 and 10: DICOM writing and promotion into
  `MR_PET`) stay serial, in the launcher's MATLAB process. The scientific pipeline is unchanged and
  every subject uses the same processing options.
- **Output folders:** every subject must resolve to its own `MR_PET` (and, for DICOM profiles, its
  own `MR/pseudo_muMAP`). Two subjects sharing one, after symbolic links are resolved, make
  `validate` and `run` fail with `OUTPUT_COLLISION` (exit `65`) before anything is created,
  authenticated or submitted. Outputs are never relocated. This applies with `N = 1` as well.
- **Failures:** one subject's failure does not stop the others. The run exits `0` only when every
  subject completed with verified results.
- **Result:** the `run` record carries `max_concurrent` and `subjects`, one entry per subject in
  request order: `index`, `subject_id` (the subjects-file `[SubjectID]`, else `subject-<n>`),
  `outcome` (`SUCCEEDED`, `FAILED`, `CANCELLED`, `TIMED_OUT` or `NOT_STARTED`), `job_id` (MLSC),
  `queue_seconds` (MLSC: time waiting in the Slurm queue), `execution_seconds` and `run_log`. The
  per-subject run logs and event files in each `MR_PET` are unchanged.

## Cancellation and interruption

- **Cancelling a run:** the first interrupt (Ctrl-C, or `SIGTERM`/`SIGHUP` sent to the launcher)
  during `run` requests a graceful cancellation: no further subject starts, active local workers
  are terminated, active Slurm jobs are cancelled with `scancel` over the existing connection,
  subjects not yet started are reported `NOT_STARTED`, and the launcher exits `130` after printing
  every subject's outcome. A second interrupt aborts at once and prints the `scancel` command for any
  Slurm job that may still be running.
- **Timeouts (MLSC):** queue waiting and execution are bounded separately. A job still pending after
  the queue timeout (unlimited by default; optional profile field `mlsc.queue_timeout_seconds`), or still running
  after the execution timeout measured from its first observed `RUNNING` state (default 7200 seconds,
  the profile's Slurm wall time), is cancelled with `scancel`; the outcome is then read from
  accounting. If terminal accounting is still unavailable, the result is a timeout failure, not a
  completion.
- **Interruption after submission:** a polling error or a lost connection after the Slurm job was accepted
  never cancels the job. The result is reported as unverified (exit `68`). The job ID and the command
  `scancel <job id>` are printed. The job keeps running until it is cancelled by hand. An error that
  stops the MATLAB process also stops its local workers and prints the `scancel` command for every
  Slurm job still active.
- **Before submission:** nothing was accepted by the scheduler, so there is nothing to cancel. Cancelling
  the MLSC login dialog submits nothing.
- **Window:** the window has no cancel control for a running request. **Close** and the window close button
  do not stop a running request; they are unavailable until the run finishes, and MATLAB stays busy while a
  synchronous request runs.

## Developer reference

This section is for developers and integrators. Users do not need it.

### MATLAB headless API

```matlab
pseudo_CT_headless(request_path, result_path)
```

`REQUEST.mat` must contain a single scalar variable named `request`, saved as MAT v5 (for example with
`save(..., '-v6')`). The result parent must already exist and be writable. Direct launcher result files must
be under the subject's `MR_PET/tmp/`; the private invocation directory there is removed on exit.

In a repository checkout, the headless bootstrap runs MATLAB. Its default executable is
`/usr/pubsw/common/matlab/7.11/bin/matlab`; set `PSEUDOCT_MATLAB` to use another executable. An installed
distribution runs its compiled engine with the selected MATLAB Runtime instead (see [Releases](releases.md)).

The request is a `pseudoCT.headless-request/v2` struct with exactly these fields:

| Field | Meaning |
|---|---|
| `schema` | `pseudoCT.headless-request/v2`. |
| `invocation_id` | UUID identifying the validate-then-submit workflow; reuse it for submit. |
| `action` | `validate` or `submit`. |
| `profile` | One of the four canonical profile keys. |
| `subjects` | Validate: MPRAGE path(s). Submit: empty. |
| `umap_files` | Validate: empty for discovery, or positionally paired path(s). Submit: empty. |
| `output_config` | Validate: empty or `struct('layout','profile-default')`. Submit: empty struct. |
| `options` | Validate: optional aliasing, recentering and cleanup booleans. Submit: empty struct. |
| `resolved_job` | Validate: empty struct. Submit: the `resolved_job` from a successful validation result. |
| `group_account` | Empty, except an optional MLSC account at submit. |
| `credential_handoff` | Empty for validate and local submit; remote submit uses a private single-use handoff path. |
| `host_key_file` | Optional MLSC host-key file path; never the file contents. |
| `current_artifact_root` | Optional development-only MLSC override; rejected for local profiles. |

Example local validation request:

```matlab
request = struct('schema', 'pseudoCT.headless-request/v2', ...
    'invocation_id', '01234567-89ab-cdef-0123-456789abcdef', ...
    'action', 'validate', 'profile', 'local', ...
    'subjects', {{'/subject/MR/MPRAGE/one.dcm'}}, ...
    'umap_files', {{'/subject/MR/UMAP/one.dcm'}}, ...
    'output_config', struct('layout', 'profile-default'), ...
    'options', struct('correct_aliasing', [], ...
        'recenter_before_normalization', [], 'cleanup_on_success', []), ...
    'resolved_job', struct(), 'group_account', '', ...
    'credential_handoff', '', 'host_key_file', '', ...
    'current_artifact_root', '');
save('validate.mat', 'request', '-v6');
pseudo_CT_headless('validate.mat', 'validate-result.mat');
```

Submit uses the bound resolved job and rechecks inputs and artifacts. Requests, results, command-line
arguments and environment variables must not contain passwords or other credential values; remote submit
uses a separate submit request and result pair and the one-time handoff path.

### Result and completion semantics

The result MAT contains one scalar `result` struct with schema `pseudoCT.headless-result/v2`. Its status is
`ready`, `submitted` or `failed`. The result separates dispatch, authentication, scheduler submission and
scientific completion evidence. A remote positive job ID and an accepted scheduler submission do not establish
scientific completion. MLSC `COMPLETED` is success only when required outputs and copy-back evidence have been
verified. A local submit reports success only after verified completion.

Use `pseudo_CT_validate_headless_result(RESULT_MAT, INVOCATION_ID, PROFILE)` to validate and bind a result to
its request. Inspect the bound status and completion fields rather than inferring completion from process exit
alone.

### `headless` and `resolve` operations

```sh
bin/pseudoct headless REQUEST.mat RESULT.mat [--mcr LABEL] [--mcr-root DIR]
bin/pseudoct resolve [--mcr LABEL] [--mcr-root DIR]
```

`headless` runs one v2 request MAT into one result MAT. It returns `0` for success; `2` for a rejected request
or profile; `3` for an authentication, account or submission failure, for any other failed headless result
(including validation failures), and for a submitted result whose scientific completion is not verified; `64`
to `66` for argument or path errors; `69` when MATLAB is unavailable; and `70` for bootstrap, dispatch, runtime
or invalid-result failures (not listed in `--help`).

`resolve` validates one MATLAB Runtime and prints single-quoted, sourceable `PSEUDOCT_EXE`, `PSEUDOCT_MCR_ROOT`,
`PSEUDOCT_RUNNER`, `PSEUDOCT_INSTALL_ROOT`, `PSEUDOCT_RUNTIME_RELEASE` and `PSEUDOCT_RUNTIME_MCR_ROOT` lines. It
requires an installed distribution.

### Related

- [README](../README.md): overview, profiles and the window and command-line steps.
- [Third-party integration guide](THIRD_PARTY_INTEGRATION.md): launching from another application and reading progress.
- [Installation](installation.md): installation, requirements and profiles.
- [Releases](releases.md): packaging, runtime identity and layout.
- [Scientific notes](scientific-notes.md): method and evidence limits.
- [Tests](../tests/README.md): offline checks.
