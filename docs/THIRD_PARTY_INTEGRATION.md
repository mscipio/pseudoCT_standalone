# Third-party integration guide

This guide is for developers who launch pseudoCT from another application, such as
PIANO Hub. It describes the contract that the source implements: how to start the
launcher as a subprocess, how to read its structured progress, how to interpret
completion and failure, and where the outputs are. You do not need the internal
implementation to use it.

It is not a deployment, certification or clinical-validity statement. Scientific use still
requires QC of the QC image and the final map (see [Scientific notes](scientific-notes.md)).
The command-line reference is [Headless API and CLI](headless-cli.md); this guide does not
repeat every option.

Placeholders are written in `<ANGLE_BRACKETS>` or as `/path/to/...`. Field names, file
names and exit codes below follow the source contract; descriptive values may change.

## Contract at a glance

Rely on these:

- **Entry point:** `<install>/bin/pseudoct` in an installed distribution. Use the absolute path.
  A source checkout is development-only and must not be used by an integrator.
- **Operations:** `run` validates and submits in one invocation; no separate `validate` is needed
  before it. `validate` is an optional check that submits nothing. `authenticate` is an optional
  MLSC login check (see [A.5](#a5-authentication-and-credentials)).
- **Exit code** is the process exit status and equals `exit_code` in the result record.
  Exit `0` from `run` means verified scientific completion.
- **Three output channels** (see [B.1](#b1-three-output-channels)): stdout progress records,
  one final result record, and the on-disk workflow JSONL per subject.
- **Result record** (stdout and `--result-file`): contains `invocation_id`, `outcome`,
  `exit_code`, the scientific-completion fields and, for MLSC, `job_ids`.
- **MLSC without a terminal:** possible with a single-use credential handoff provisioned in MATLAB
  on the same host (see [A.5](#a5-authentication-and-credentials)).

Do not rely on: the wording of `message` and `error_message` text, the text output format,
the exact set of optional fields in stdout progress records, the timing or cadence of
progress, or the presence of a result line if the launcher is killed (see
[Known limits](#known-limits)).

---

## A. Launching pseudoCT

### A.1 Entry points

```text
bin/pseudoct run          --profile PROFILE (--mprage FILE [--umap FILE] | --config JOB.json) [options]
bin/pseudoct validate     --profile PROFILE (--mprage FILE [--umap FILE] | --config JOB.json) [options]
bin/pseudoct authenticate --profile MLSC_PROFILE --credential-handoff FILE [options]
bin/pseudoct --list-releases
bin/pseudoct --help
```

`authenticate` is MLSC only. It logs in with a handoff, selects the account and stops. It processes
no inputs and never submits. It is optional: `run` with a handoff performs its own login.
`headless` and `resolve` exist for the window and for developers; an integrator should not use them.

### A.2 Arguments

| Argument | Required | Meaning |
|---|---|---|
| `--profile NAME` | yes | One of `local`, `local-mprage-only`, `mlsc`, `mlsc-mprage-only`. |
| `--mprage FILE` | one input form | One subject's MPRAGE (DICOM or NIfTI). Cannot be combined with `--config`. |
| `--umap FILE` | no | UMAP reference for `local` and `mlsc`. Omitted, the launcher tries to discover it from the subject layout. Rejected by the `*-mprage-only` profiles. |
| `--config JOB.json` | one input form | Several subjects: `{"mprage": [...], "umap": [...]}`. `umap` is optional but, if present, must be paired by position with `mprage`. No other keys are accepted. |
| `--correct-aliasing yes\|no` | no | Overrides the profile default. |
| `--recenter-before-normalization yes\|no` | no | Overrides the profile default. |
| `--cleanup-on-success yes\|no` | no | Overrides the profile default. |
| `--format jsonl` | recommended | Machine-readable stdout (default is `text`). |
| `--result-file PATH` | recommended | Also writes the final result record to `PATH`, atomically. The directory must exist and be writable. Written in both formats. |
| `--credential-handoff FILE` | MLSC `run` and `authenticate` | Path of an existing single-use credential handoff. Consumed on use. See [A.5](#a5-authentication-and-credentials). Not accepted for `validate` or local profiles. |
| `--group-account ACCOUNT` | MLSC only | Account. Blank or omitted: the first discovered account. |
| `--host-key-file FILE` | MLSC only | Strict host-key input for the cluster connection. |
| `--check-account` | no | MLSC, `validate` only. Logs in and checks the account, never submits. |
| `--mcr LABEL` | no | Installed release, an exact catalog label (default `R2010b`). Use `--list-releases` to see the installed labels. |
| `--mcr-root DIR` | no | MATLAB Runtime root, only if the runtime is not at the catalog location. |

Do not use `--current-artifact-root` (development only). Passwords are never accepted as options
or environment variables.

### A.3 Exit codes

| Code | Meaning for `run` |
|---:|---|
| `0` | Completed with verified results (`scientific_completion` is `completed`). For `validate`, the request is `ready`. For `authenticate`, the login succeeded. |
| `64` | Usage or configuration error. |
| `65` | Invalid request, or validation failure. |
| `66` | Authentication failure, or authentication required but not possible (see [A.5](#a5-authentication-and-credentials)). |
| `67` | Submission failure (scheduler rejected or unresolved). |
| `68` | Scientific failure, or completion not verified. An accepted job without verified completion is also `68`. |
| `69` | Launcher or runtime failure, or an unreadable release catalog. |
| `70` | MATLAB dispatch or runtime failure. |

`0` is the only success code for `run`. Do not treat any other code as success, and do not treat a
scheduler acceptance or a process that merely returned as completion.

### A.4 Working directory and environment

- **Working directory:** the launcher does not depend on it. Relative paths are resolved
  against the directory you launch from, so pass **absolute paths** for `--mprage`, `--umap`,
  `--config`, `--credential-handoff`, `--result-file` and the job file.
- **Environment the caller should not set:**
  - `LD_LIBRARY_PATH` and MATLAB variables: the launcher sets `LD_LIBRARY_PATH` itself for the
    compiled steps and sets its own `TMPDIR` under the subject's `MR_PET/tmp`.
  - `PSEUDOCT_MATLAB`, `PSEUDOCT_LAUNCHER`, `PSEUDOCT_CLI_*`, `PSEUDOCT_REQUEST_MAT`,
    `PSEUDOCT_RESULT_MAT`, `PSEUDOCT_INSTALL_ROOT`, `PSEUDOCT_RUNTIME_*`: internal or
    source-checkout only. Do not set them.
- **Environment the caller may set:** `PSEUDOCT_AUTH_RETRY_LIMIT` (MLSC terminal prompt only;
  empty means unlimited retries, `N` means `N` retries, `0` means none).
- **Tools the launcher needs:** `python3`, `uuidgen`, `readlink`, and standard coreutils.
- Do not start a second run for the same subject while one is in progress.

### A.5 Authentication and credentials

Local profiles need no credentials.

MLSC profiles accept two mechanisms. Choose one per call.

1. **Credential handoff (non-interactive).** Pass `--credential-handoff PATH` to `run` or to
   `authenticate`. `PATH` must name an existing single-use credential file. With a handoff, `run`
   does not prompt and does not need a terminal: the handoff travels with the submit request, and
   the login happens in that step.
   - **Provisioning.** The file is created in MATLAB by `pseudo_CT_credentials('store', USERNAME,
     PASSWORD)`, which returns its path (source: `src/api/pseudo_CT_credentials.m`). It must be
     created on the **same host**, as the **same operating-system user** that runs the launcher,
     because it lives in a private per-user directory on the memory-backed `/dev/shm` filesystem.
     The launcher rejects any path that is not a file in that form.
   - **Single use.** When the launcher consumes a handoff it overwrites the file, deletes it and
     removes its directory, whether or not the login succeeds. A handoff cannot be reused. Each
     `authenticate` or `run` call needs its own newly created handoff. If a call stops before
     consuming it, the launcher erases the named handoff during cleanup.
   - **Secrets.** Take the username and password from your own secret store at run time. Do not
     put them on a command line, in environment variables, in logs or in a job file. Never write
     them to the job JSON.
   - **Failure.** A rejected login with a handoff ends the call with exit `66`. There is no
     re-prompt, because the handoff has been consumed.
2. **Terminal prompt (interactive).** Without `--credential-handoff`, `run` asks for the username,
   then the password (echo off) and, if `--group-account` is absent, the account. It reads from
   `/dev/tty`. Without a terminal it exits `66` with `error_code` `AUTHENTICATION_REQUIRED` and
   submits nothing. A rejected login re-prompts; `PSEUDOCT_AUTH_RETRY_LIMIT` limits the retries.

`authenticate` takes only `--profile` (an MLSC profile), `--credential-handoff`, `--group-account`,
`--host-key-file`, `--format` and `--result-file`. It logs in, selects the account and stops. Its
handoff is consumed, so a `run` afterwards needs a second handoff.

**Consequence:** local profiles can be fully automated. MLSC profiles can be automated without a
terminal, provided a MATLAB session on the same host provisions one handoff per call. A
non-MATLAB integrator cannot create the handoff itself. The MLSC path has been checked against the
source only; it has not been verified end to end against a scheduler.

### A.6 Complete working examples

Placeholder paths; replace them with your own.

Local profile:

```sh
PSEUDOCT=/path/to/pseudoct-<VERSION>/bin/pseudoct
JOB_DIR=/path/to/piano/jobs/<JOB_ID>
mkdir -p "$JOB_DIR"

"$PSEUDOCT" run \
  --profile local \
  --mprage /path/to/study/sub-001/MR/MPRAGE/<MPRAGE_FILE>.dcm \
  --umap /path/to/study/sub-001/MR/UMAP/<UMAP_FILE>.dcm \
  --format jsonl \
  --result-file "$JOB_DIR/pseudoct-result.json"
echo "exit=$?"
```

MLSC profile, with a handoff that was provisioned in MATLAB just before this call (one handoff per call):

```sh
HANDOFF=<PATH_RETURNED_BY_pseudo_CT_credentials_store>   # single-use; obtained by your MATLAB step

"$PSEUDOCT" run \
  --profile mlsc \
  --mprage /path/to/study/sub-001/MR/MPRAGE/<MPRAGE_FILE>.dcm \
  --umap /path/to/study/sub-001/MR/UMAP/<UMAP_FILE>.dcm \
  --credential-handoff "$HANDOFF" \
  --format jsonl \
  --result-file "$JOB_DIR/pseudoct-result.json"
echo "exit=$?"
```

Stdout carries progress and then the result. The same result is in the `--result-file` path. Interpret
the exit code and the result as described in
[Completion, failure and output verification](#b8-completion-failure-and-output-verification).

---

## B. Structured progress and JSONL logging

### B.1 Three output channels

Keep these three channels separate. They have different schemas and different guarantees.

1. **Stdout progress records** (`--format jsonl`): one `{"type":"progress",...}` line per
   presented event while the run proceeds. This is a presentation stream. Its wording and optional
   fields can change. It is not the canonical record.
2. **Final result record**: one `{"type":"result",...}` line, normally the last stdout line. It has
   the same content as the `--result-file` file. It carries the outcome, the exit code and the
   submission and scientific-completion fields. Use it for the final decision.
3. **On-disk workflow JSONL**, one file per subject:
   `<subject>/MR_PET/pseudoct-run-<UTC>-<invocation_id>.jsonl`. It holds the canonical stage and
   run records, with a fixed schema. It is written best-effort (see [B.4](#b4-on-disk-record-canonical)).

Anything that is not a progress or result record goes to stderr. Do not derive state from stderr.

`validate` writes one result record to `<subject>/MR_PET/pseudoct-validate-<UTC>-<invocation_id>.jsonl`
and creates no run file. `authenticate` writes no workflow file.

### B.2 Where the files are and how to find them

- **Subject folder.** The launcher walks up from the MPRAGE's folder to the nearest folder named
  `MR`; the subject folder is its parent. In the standard layout (`<subject>/MR/MPRAGE/<file>`),
  `MR_PET` is `<subject>/MR_PET`. The launcher creates `MR_PET` (and `MR_PET/tmp`) if it is missing.
- **File name.** `pseudoct-run-<UTC>-<invocation_id>.jsonl`:
  - `<UTC>` is `YYYYMMDDTHHMMSSZ`, taken when the run file is created (after input and output
    resolution, before processing).
  - `<invocation_id>` is a lowercase UUID. **It equals the `invocation_id` in the result record.**
    Each record's `run_id` is `<UTC>-<invocation_id>`.
  - For multi-subject jobs, one file is created per subject. Its records carry `subject`
    `subject-<n>`, where `<n>` is the 1-based position in the job.
- **Finding the file during a run.** The invocation ID is not announced until the end, and the
  stdout stream does not carry the file path. Use a before/after snapshot per subject `MR_PET`:
  1. Before launch, list `MR_PET/pseudoct-run-*.jsonl`.
  2. After launch, the file that is new in that list is this run's file for that subject.
  3. Record the path, then tail it.
- **Finding the file after the run.** Use the `invocation_id` from the result record and match
  `MR_PET/pseudoct-run-*-<invocation_id>.jsonl`.

### B.3 Stdout progress records

Read only the fields below and treat missing ones as unknown.

| Field | Presence | Meaning |
|---|---|---|
| `type` | always | `"progress"` |
| `timestamp` | always (may be `null`) | Local wall-clock text, `YYYY-MM-DD HH:MM:SS`, with **no time zone**. For ordering use the on-disk `timestamp_utc`. |
| `level` | always | Short upper-case word such as `INFO`, `SUCCESS`, `WARN`, `ERROR`. |
| `message` | always | Sanitized human text. Do not parse it. |
| `subject` | optional | `S01`-style subject label. Omitted for run-level rows. |
| `stage` | optional | `[n/10]`, present only for numbered stages. |
| `stage_number`, `stage_total` | optional | Integers (`stage_total` is `10`). `null` if not numbered. |
| `status` | optional | `ACTIVE`, `DONE`, `SKIPPED`, `VERIFIED`, `INFO`, `WARN`, `ERROR`, `CANCELLED`. |
| `job` | optional | Scheduler job number (MLSC), when known. |
| `schema_version`, `profile`, `backend`, `event_kind`, `operation_id`, `event_category`, `stage_id`, `stage_span`, `operation_ids`, `live`, `reason`, `original_timestamp`, `source`, `source_file`, `source_lines` | optional | Additional context. Present when the presenter knows it. |

Status mapping for stdout: `ACTIVE` is the on-disk `STARTED`; `DONE` is the on-disk `COMPLETED`.

### B.4 On-disk record (canonical)

Every line is one complete JSON object with all of these keys. Optional values are `null`.

| Field | Type | Values |
|---|---|---|
| `schema` | string | `pseudoct.scientific_event` |
| `schema_version` | integer | `1` |
| `run_id` | string | `<UTC>-<invocation_id>` |
| `subject` | string | `subject-<n>` |
| `profile` | string | Canonical profile key |
| `seq` | integer | Strictly increasing within the file. Gaps can occur. |
| `timestamp_utc` | string | `YYYY-MM-DDTHH:MM:SS.mmmZ` (UTC) |
| `event_type` | string | `stage`, `run` or `diagnostic` |
| `stage_id` | string or null | Workflow identifier (see B.5) for stage records |
| `stage_index` | integer or null | 1 to 10 for stage records |
| `stage_count` | integer or null | `10` for stage records |
| `status` | string or null | Stage records: `STARTED`, `COMPLETED`, `FAILED`, `SKIPPED` |
| `outcome` | string or null | Run records: `SUCCEEDED`, `FAILED`, `CANCELLED` |
| `message` | string | Redacted, at most 240 characters |
| `source` | string | `local-orchestrator`, `payload` or `mlsc-lifecycle` |
| `job_id` | string or null | Scheduler job number (digits) |
| `error_identifier`, `error_message` | string or null | Error details when applicable |
| `level` | string or null | Diagnostic records only: `INFO`, `WARN`, `ERROR` |
| `kind` | string or null | Diagnostic records only: `warning`, `error`, `lifecycle` |

Diagnostic records carry no stage identity (`stage_id`, `stage_index`, `status` and `outcome` are `null`).

**Best effort.** The writer appends one line per record and does not retry a failed write. A
missing record in this file is therefore not proof that an event did not happen. The result record
and the exit code are the authoritative outcome; use the file for progress and for diagnosis.

Representative lines (illustrative placeholders; the field set and value types follow the schema
above, and the message text is an example only):

```json
{"schema":"pseudoct.scientific_event","schema_version":1,"run_id":"20261111T162003Z-<invocation_id>","subject":"subject-1","profile":"local","seq":4,"timestamp_utc":"2026-11-11T16:20:41.512Z","event_type":"stage","stage_id":"workflow.recenter","stage_index":2,"stage_count":10,"status":"STARTED","outcome":null,"message":"MPRAGE recentering started.","source":"local-orchestrator","job_id":null,"error_identifier":null,"error_message":null}
{"schema":"pseudoct.scientific_event","schema_version":1,"run_id":"20261111T162003Z-<invocation_id>","subject":"subject-1","profile":"local-mprage-only","seq":9,"timestamp_utc":"2026-11-11T16:31:10.004Z","event_type":"stage","stage_id":"workflow.dicom_output","stage_index":9,"stage_count":10,"status":"SKIPPED","outcome":null,"message":"DICOM output skipped by MPRAGE-only policy (profile_policy:mprage_only).","source":"local-orchestrator","job_id":null,"error_identifier":null,"error_message":null}
{"schema":"pseudoct.scientific_event","schema_version":1,"run_id":"20261111T162003Z-<invocation_id>","subject":"subject-1","profile":"local","seq":21,"timestamp_utc":"2026-11-11T16:58:37.330Z","event_type":"run","stage_id":null,"stage_index":null,"stage_count":null,"status":null,"outcome":"SUCCEEDED","message":"Run finished.","source":"local-orchestrator","job_id":null,"error_identifier":null,"error_message":null}
```

Stdout progress example (illustrative placeholders):

```json
{"type":"progress","timestamp":"2026-11-11 16:21:02","level":"SUCCESS","subject":"S01","stage":"[2/10]","stage_number":2,"stage_total":10,"status":"DONE","message":"MPRAGE recentering completed."}
```

The final result record (stdout last line and `--result-file`) for a validate call, illustrative:

```json
{"type":"result","invocation_id":"<invocation_id>","action":"validate","profile":"local","outcome":"validation_succeeded","headless_dispatch_returned":true,"dispatch_status":"<dispatch_status>","scheduler_submission_accepted":false,"submission_status":"not_attempted","authentication_status":"<authentication_status>","scientific_completion":null,"scientific_completion_status":"<status>","scientific_completion_reason":"Validation does not execute scientific processing.","backend":"local","job_ids":[],"group_account":null,"group_account_reason":"No MLSC account was selected by this invocation.","error_code":null,"error_message":null,"exit_code":0}
```

Some values in the result record are internal status strings (`dispatch_status`,
`submission_status`, `authentication_status`, `scientific_completion_status`); treat them as
descriptive, and key your logic on the fields in
[Completion, failure and output verification](#b8-completion-failure-and-output-verification).

### B.5 Stage numbering and identifiers

The public workflow has ten logical stages. The total is always `10`, for every profile.

| Index | `stage_id` | Title |
|---:|---|---|
| 1 | `workflow.input_prepare` | Input MPRAGE preparation |
| 2 | `workflow.recenter` | MPRAGE recentering |
| 3 | `workflow.alias_correct` | Aliasing correction |
| 4 | `workflow.normalize` | FreeSurfer MPRAGE normalization |
| 5 | `workflow.align_mask` | MPRAGE alignment and masking |
| 6 | `workflow.segment` | SPM New Segment |
| 7 | `workflow.dartel` | DARTEL atlas registration |
| 8 | `workflow.attenuation_qc` | Attenuation-map and QC generation |
| 9 | `workflow.dicom_output` | Writing DICOM output |
| 10 | `workflow.full_output_finalize` | Output promotion (full profiles) |

Key on `stage_index`; use `stage_id` for display only.

- **MPRAGE-only profiles** (`local-mprage-only`, `mlsc-mprage-only`): the finalizer records stage 9
  and stage 10 as `SKIPPED`, with the policy reason `profile_policy:mprage_only`. The on-disk
  `SKIPPED` records are the intended record; they are written best-effort (see B.4). The same
  `SKIPPED` event also reaches the text table and stdout progress. Stage 10 does not mean that no
  promotion happened: NIfTI promotion still runs for these profiles and is reported as
  `VERIFIED` or as the run result. Do not wait for stage 9 or 10 to become `DONE`.
- **Stages 2 and 3** may be `SKIPPED` with a reason (see B.6). A `SKIPPED` stage is not a failure.
- **MLSC profiles:** the stage map numbers only some of the work (stages 1, 9 and 10 for the
  standard MLSC profile). Remote processing that is not numbered arrives without a stage number.
  Treat unnumbered rows as informational, not as missing stages. See [Known limits](#known-limits).

### B.6 Stages 2 and 3 are not live before they run

For stages 2 (recentering) and 3 (aliasing correction), the launcher reports `ACTIVE`
(on-disk `STARTED`) only after the correction operation has been confirmed to run. If the
operation is not required, or is turned off, the stage is reported as `SKIPPED` with a reason and
no `ACTIVE` row is emitted. A consumer must not show a stage 2 or 3 "running" state before it
sees `ACTIVE`.

### B.7 Failure, cancellation, skipped stages and heartbeats

- **Stage failure:** on-disk `status` `FAILED` for that `stage_index`; on stdout `status` `ERROR`.
- **Run outcome** (on-disk run record): `SUCCEEDED`, `FAILED` or `CANCELLED`.
- **Cancellation:** `CANCELLED` appears when a scheduled job is cancelled by the timeout path. An
  interrupted launcher does not cancel an accepted Slurm job (see [Cancellation](#cancellation-and-interruption)).
- **Progress cancellation:** a subject that has stopped after a user cancellation request is reported with progress
  `status` `CANCELLED`. The request itself is a `WARN` record, and it does not mark the subject cancelled.
- **Skipped:** `SKIPPED` carries the reason in `message` (on disk) and in `reason` or `message` (stdout).
- **Heartbeats:** text output shows `still running` lines. The on-disk file has no heartbeat
  records. Do not use progress frequency as evidence of progress.

### B.8 Completion, failure and output verification

The result record separates these facts. Use them in this order:

1. **Process exit code** (`$?`): `0` means completed and verified (for `run`).
2. **Result record** `exit_code` (identical to step 1) and `outcome`:
   - `scientific_completed`: completed.
   - `scientific_failed`: failed.
   - `scientific_completion_unverified`, `submission_accepted_completion_unverified`:
     unverified; exit `68`.
   - `submission_failed`: exit `67`.
   - `authentication_failed`: exit `66`.
   - `validation_failed`: exit `65`.
   - `failed` (error record): a usage or runtime error before processing; see `error_code`.
3. **`scientific_completion`**: `completed`, `failed`, or `null`. A scheduler acceptance,
   `dispatch_status` or `submission_status` never establishes completion.

**Completion versus finalization.** `scientific_completion: completed` is returned only after
verified completion, which includes the required outputs (and, for MLSC, copy-back verification).
The result record has no separate "promoted" flag. For full profiles, the on-disk
`workflow.full_output_finalize` (stage 10) record reaches `COMPLETED` only after promotion succeeds;
`FAILED` means the output could not be promoted and temporary files are preserved. For
MPRAGE-only profiles, stage 10 is `SKIPPED` by policy (see B.5).

**Output verification.** Verification of individual outputs is reported as progress (`VERIFIED`)
and inside the run; it is not a separate result field.

---

## C. Building an independent progress display

### C.1 Launch and monitor

Start the launcher with `stdout` and `stderr` as pipes. Drain **both** concurrently, for example
one reader thread per pipe, so a full pipe cannot stall the process. Do not parse `stderr` for
state.

### C.2 Tail the on-disk file

- Read from the last byte offset. Keep the trailing bytes after the last `\n` as a partial line.
- A line that fails JSON parsing is skipped. The writer closes a partial fragment with a newline
  and keeps its `seq` slot, so the next record starts cleanly.
- Accept only records with `schema == "pseudoct.scientific_event"`.
- Use `seq` to drop duplicates and replays: ignore any record whose `seq` is not greater than the
  last accepted `seq`.

### C.3 Grouping

- Group stage records by `(subject, stage_index)`. The latest record for that key is its state.
- A run record (`event_type == "run"`) gives the run outcome for that subject.
- Diagnostic records have no stage. Show them in a log panel, not in the stage grid.

### C.4 Detecting completion and failure

- A result with `exit_code` `0`, `scientific_completion` `completed` and `outcome`
  `scientific_completed` is success.
- For a multi-subject run, also require a `SUCCEEDED` run record for every subject and every
  output in C.5. A missing record or output after exit `0` is an inconsistent result, not success.
- Any other exit status, or a result with `outcome` other than `scientific_completed`, is not
  success. Map it to the failure in [Completion, failure and output verification](#b8-completion-failure-and-output-verification).
- **No result line:** treat the outcome as unknown, whatever the exit status, and do not mark the
  job as complete. For MLSC, check the scheduler before reporting anything.

### C.5 Locating and consuming outputs

Read outputs only after a successful exit (`0`). The result record does **not** list output paths.
For each subject, in `<subject>/MR_PET/` (and `<subject>/MR/pseudo_muMAP/` for DICOM):

| File or folder | Profiles | Notes |
|---|---|---|
| `att_map.nii` | all | Attenuation map (NIfTI). |
| `Fusion_MR_Pseudo_CT_validation.tiff` | all | MPRAGE/pseudoCT fusion QC image. |
| `Pseudo_CT_AC_Version.txt` | all | Version record. |
| `<subject>/MR/pseudo_muMAP/` | `local`, `mlsc` | DICOM series. Not written for `*-mprage-only`. |

Check that each file exists and is non-empty before use. Do not read from `MR_PET/tmp`; it holds
working files and is removed after promotion when cleanup is on. Inspect the QC image before using
the map (see [Scientific notes](scientific-notes.md#interpretation-and-quality-control)).

### C.6 Python starting point (multi-subject)

The example below was run against a stand-in launcher (scratch only, not pseudoCT) for five
scenarios: success, scientific failure (exit 68), missing result (exit 70), MPRAGE-only, and two
subjects. It exercises the process handling, the tailing, the classification and the output
checks. It does not exercise pseudoCT processing, and the MLSC credential path is not covered.
Run it with `python3 -I -B`. Replace the placeholders with your paths. It uses only the Python
standard library.

```python
#!/usr/bin/env python3
"""Starting point for launching pseudoCT from another application (e.g. PIANO).

Runs `bin/pseudoct run --format jsonl` for one or more subjects, follows each
subject's on-disk run file, and classifies the outcome from the process exit
status, the final result record, each run record and the final outputs.
It never handles a password: for MLSC it only passes the PATH of an existing
single-use credential handoff that the caller provisions (see the guide).
Assumes the standard layout <subject>/MR/<series>/<file> for each MPRAGE.
"""
import argparse
import glob
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading

SCHEMA = "pseudoct.scientific_event"
EXIT_MEANING = {
    0: "completed", 64: "usage or configuration error", 65: "invalid request",
    66: "authentication failed or not possible", 67: "submission failed",
    68: "scientific failure or completion not verified",
    69: "launcher or runtime failure", 70: "MATLAB dispatch or runtime failure",
}
OUTPUTS = ("att_map.nii", "Fusion_MR_Pseudo_CT_validation.tiff", "Pseudo_CT_AC_Version.txt")


def subject_root(mprage):
    """Parent of the nearest folder named MR above the MPRAGE."""
    folder = os.path.dirname(os.path.abspath(mprage))
    while True:
        parent, name = os.path.split(folder)
        if name.lower() == "mr":
            return parent
        if parent == folder:
            raise ValueError("no MR folder above %s" % mprage)
        folder = parent


class RunFileTailer:
    """Incremental reader of one pseudoct-run-*.jsonl file."""

    def __init__(self, path):
        self.path, self.offset, self.pending, self.last_seq = path, 0, b"", 0

    def poll(self):
        try:
            with open(self.path, "rb") as handle:
                handle.seek(self.offset)
                data = handle.read()
        except OSError:
            return []
        self.offset += len(data)
        *lines, self.pending = (self.pending + data).split(b"\n")  # keep a partial tail
        events = []
        for raw in lines:
            try:
                rec = json.loads(raw.decode("utf-8"))
            except ValueError:  # partial or closed fragment
                continue
            if not isinstance(rec, dict) or rec.get("schema") != SCHEMA:
                continue
            seq = rec.get("seq")
            if not isinstance(seq, int) or seq <= self.last_seq:
                continue  # duplicate or replayed record
            self.last_seq = seq
            events.append(rec)
        return events


def pump(stream, sink):
    for line in iter(stream.readline, ""):
        sink.put(line)
    sink.put(None)


def classify(returncode, result, consistent):
    if result is None:
        return "unknown", "no result record; launcher exit %s (%s)" % (
            returncode, EXIT_MEANING.get(returncode, "unexpected exit"))
    if returncode == 0 and result.get("exit_code") == 0 and \
            result.get("scientific_completion") == "completed":
        if consistent:
            return "completed", "verified completion; run records and outputs present"
        return "inconsistent", "exit 0 but a run record or an output is missing"
    return "not completed", "exit %s: %s (outcome %s)" % (
        returncode, EXIT_MEANING.get(returncode, "unexpected exit"), result.get("outcome"))


def main(argv):
    ap = argparse.ArgumentParser(description="Run pseudoCT for one or more subjects.")
    ap.add_argument("pseudoct", help="absolute path of bin/pseudoct")
    ap.add_argument("--profile", required=True,
                    choices=["local", "local-mprage-only", "mlsc", "mlsc-mprage-only"])
    ap.add_argument("--mprage", required=True, nargs="+", help="one MPRAGE per subject")
    ap.add_argument("--umap", nargs="+", default=[], help="one UMAP per subject, same order")
    ap.add_argument("--credential-handoff",
                    help="path of an existing single-use handoff (MLSC profiles only)")
    args = ap.parse_args(argv[1:])
    if args.umap and len(args.umap) != len(args.mprage):
        ap.error("--umap needs one path per --mprage, in the same order")

    mprages = [os.path.abspath(p) for p in args.mprage]
    umaps = [os.path.abspath(p) for p in args.umap]
    roots = [subject_root(p) for p in mprages]
    mr_pets = [os.path.join(r, "MR_PET") for r in roots]
    before = {d: set(glob.glob(os.path.join(d, "pseudoct-run-*.jsonl"))) for d in mr_pets}

    with tempfile.TemporaryDirectory() as work:
        result_path = os.path.join(work, "result.json")
        cmd = [os.path.abspath(args.pseudoct), "run", "--profile", args.profile]
        if len(mprages) == 1:
            cmd += ["--mprage", mprages[0]]
            if umaps:
                cmd += ["--umap", umaps[0]]
        else:
            job = {"mprage": mprages}
            if umaps:
                job["umap"] = umaps
            config = os.path.join(work, "job.json")
            with open(config, "w", encoding="utf-8") as handle:
                json.dump(job, handle)
            cmd += ["--config", config]
        if args.credential_handoff:
            cmd += ["--credential-handoff", os.path.abspath(args.credential_handoff)]
        cmd += ["--format", "jsonl", "--result-file", result_path]

        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, universal_newlines=True, bufsize=1)
        out_q, err_q = queue.Queue(), queue.Queue()
        out_t = threading.Thread(target=pump, args=(proc.stdout, out_q), daemon=True)
        err_t = threading.Thread(target=pump, args=(proc.stderr, err_q), daemon=True)
        out_t.start()
        err_t.start()

        tailers, stage_seen, run_outcome, run_files = {}, {}, {}, {}

        def sweep():
            for d in mr_pets:
                if d not in tailers:
                    new = sorted(set(glob.glob(os.path.join(d, "pseudoct-run-*.jsonl"))) - before[d])
                    if new:
                        tailers[d] = RunFileTailer(new[0])
                        run_files[d] = new[0]
                if d in tailers:
                    for rec in tailers[d].poll():
                        etype = rec.get("event_type")
                        if etype == "stage" and isinstance(rec.get("stage_index"), int):
                            key = (d, rec["stage_index"])
                            if stage_seen.get(key) != rec.get("status"):
                                stage_seen[key] = rec.get("status")
                                print("%s stage %d %s" % (rec.get("subject"),
                                                          rec["stage_index"], rec.get("status")))
                        elif etype == "run":
                            run_outcome[d] = rec.get("outcome")
                            print("%s run outcome %s" % (rec.get("subject"), rec.get("outcome")))

        result = None
        while True:
            try:
                line = out_q.get(timeout=0.5)
            except queue.Empty:
                line = ""
            if line is None:  # stdout closed: the launcher is ending
                break
            if not line.strip():
                sweep()
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                rec = None  # not JSON: stdout carries only JSONL in this mode
            if isinstance(rec, dict) and rec.get("type") == "result":
                result = rec
            sweep()
        returncode = proc.wait()
        out_t.join(timeout=5)
        err_t.join(timeout=5)
        sweep()  # final catch-up after exit

        if result is None and os.path.exists(result_path):
            try:
                with open(result_path, encoding="utf-8") as handle:
                    result = json.load(handle)
            except (OSError, ValueError):
                result = None
        err_lines = []
        while not err_q.empty():
            item = err_q.get_nowait()
            if item:
                err_lines.append(item)

    consistent = True
    if returncode == 0:
        for d in mr_pets:
            if run_outcome.get(d) != "SUCCEEDED":
                consistent = False
                print("no SUCCEEDED run record for %s" % d)
        for root in roots:
            for name in OUTPUTS:
                p = os.path.join(root, "MR_PET", name)
                if not (os.path.isfile(p) and os.path.getsize(p) > 0):
                    consistent = False
                    print("missing or empty output: %s" % p)
    state, why = classify(returncode, result, consistent)
    print("classification: %s (%s)" % (state, why))
    if state != "completed" and err_lines:
        print("stderr (last lines):", "".join(err_lines[-5:]).rstrip(), file=sys.stderr)
    return 0 if state == "completed" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

Notes on the example:

- It finds each subject's run file by snapshot, so it handles several subjects in one call.
- It decides success only from exit `0`, the result record, a `SUCCEEDED` run record for each
  subject, and the presence of the outputs in C.5. Any gap is reported as `inconsistent`.
- With no result record, it reports `unknown` and the launcher's exit code, and does not assume success.
- It does not render stage state; it prints changes only. A consumer that needs the stage grid
  should keep the latest status per `(subject, stage_index)`.
- The `--credential-handoff` option only passes a path. Provisioning and single-use handling are
  described in [A.5](#a5-authentication-and-credentials).

---

## Cancellation and interruption

- **Before submission:** nothing has been accepted, so there is nothing to cancel.
- **After an accepted Slurm job:** a lost connection, a polling error or an interruption of the
  launcher (including Ctrl-C) does **not** cancel the job. The result is unverified (exit `68`), and
  the job ID and `scancel <job id>` are printed. Cancel the job yourself if it must stop.
- **Timeouts:** when polling reaches the configured timeout, the launcher requests cancellation and
  then reports the outcome from scheduler accounting. If accounting is still unavailable, the
  result is a timeout failure, not a completion.
- **Killing the launcher from your application** is not a cancellation. Read the job ID from the
  stdout `job` field if you need it, and cancel the job explicitly.

## Known limits

These are facts of the current implementation that an integrator must plan around. They are not
changed by this guide.

1. **MLSC without a terminal needs a MATLAB-provisioned handoff.** Without one, `run` needs a
   terminal (see [A.5](#a5-authentication-and-credentials)). A handoff is single-use and must be
   created on the same host and operating-system user as the launcher.
2. **The run file is not announced before the run.** Use the snapshot method in
   [B.2](#b2-where-the-files-are-and-how-to-find-them).
3. **The result record does not list run-log or output paths.** Run-log paths appear only in the
   text summary; output files must be located by the names in [C.5](#c5-locating-and-consuming-outputs).
4. **If the launcher is killed, no result record is written.** The outcome is then unknown; check
   the on-disk run file and, for MLSC, the scheduler.
5. **The on-disk record is best-effort.** A failed write is not retried. The result record and the
   exit code are authoritative (see [B.4](#b4-on-disk-record-canonical)).
6. **MLSC progress is sparse.** Only some stages are numbered; see [B.5](#b5-stage-numbering-and-identifiers).
7. **Stdout timestamps are local wall-clock text without a time zone**; on-disk `timestamp_utc` is UTC.
8. **Source checkouts** (development only) use a different launcher path and must not be used by an integrator.
9. **The MLSC handoff path is verified against the source only**, not against a live scheduler.

## Versioning

The on-disk schema is `pseudoct.scientific_event` version `1`. Check `schema` and `schema_version`
and refuse unknown versions. The stdout progress schema is a presentation contract and can gain
fields; ignore unknown fields.

## Related

- [Headless API and CLI](headless-cli.md): full option, output and exit-code reference.
- [Installation](installation.md): supported profiles, requirements and installed layout.
- [Release catalog and layout](releases.md): releases, `--list-releases` and runtime identity.
- [Scientific notes](scientific-notes.md): method and interpretation limits.
- [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/): the researcher workflow.
