# Standalone headless CLI

`bin/pseudoct-headless REQUEST.mat RESULT.mat` runs the versioned MATLAB v5
Headless MAT v2 API through MATLAB R2010b. The public `bin/pseudoct` CLI builds
on this structured API through `bin/pseudoct-headless` and adds a shell-facing
contract for text/JSONL progress and exit codes. The launcher works from another
directory and derives the installation root from itself. It uses a fixed
`-nodesktop -nosplash -nodisplay` bootstrap, keeps Java enabled, and does not
interpolate request values into MATLAB code. The default executable is
`/usr/pubsw/common/matlab/7.11/bin/matlab`; set `PSEUDOCT_MATLAB` to select a
different executable.

```sh
/path/to/pseudoCT_standalone/bin/pseudoct-headless \
  /private/requests/validate.mat /private/results/validate.mat
```

Request and result paths are made absolute before MATLAB changes directory.
The request must be readable, the result parent must already exist and be
writable, and the paths must not identify the same file. Credential values are
never command-line arguments or environment values.

## Request v2 and validate→submit

The request MAT file must contain exactly one scalar `request` struct saved
with `-v6` (MAT v5-compatible). Schema `pseudoCT.headless-request/v2` has
exactly these 13 fields:

| Field | Contract |
|---|---|
| `schema` | Character row `pseudoCT.headless-request/v2`. |
| `invocation_id` | UUID character row (`8-4-4-4-12` hexadecimal digits); create one per validate→submit workflow and reuse it for submit. |
| `action` | `validate` or `submit`. There is no preflight action. |
| `profile` | Exact profile key `mlsc-current`, `mlsc-mprage-only`, `mlsc-legacy`, `launchpad-legacy`, `local-current`, `local-legacy`, or `local-mprage-only`. No aliases or fallback. |
| `subjects` | For validate, empty, one path, a cell array of paths, or a character matrix with one path per row. Submit requires an empty value and uses only `resolved_job`. |
| `umap_files` | For validate, omitted/empty means local autodiscovery; otherwise one path per subject, positionally paired. Empty cell entries request discovery for those subjects. An explicit path is preserved exactly and never replaced. Submit requires an empty value. |
| `output_config` | Scalar struct, empty or exactly `struct('layout','profile-default')` for validate. Submit requires an empty struct. |
| `options` | Scalar struct with optional `correct_aliasing`, `recenter_before_normalization`, and `cleanup_on_success`; each is empty or scalar numeric/logical `0` or `1`. Submit requires an empty struct. |
| `resolved_job` | Empty scalar struct for validate; the `result.resolved_job` returned by successful validate for submit. It uses `pseudoCT.resolved-job/v1` and carries bound MPRAGE/UMAP records, options, output paths, and artifact/input identities, but no credentials or live sessions. |
| `group_account` | Empty for validate, local profiles, and Launchpad. Optional free text for MLSC submit; empty selects the first account returned by MLSC, while a supplied value is trimmed and matched exactly. |
| `credential_handoff` | Empty for validate and local submit; required path to a private, single-use handoff for remote submit. The request contains only this path, never credential values. |
| `host_key_file` | Empty unless MLSC submit opts into strict host-key verification with a known-hosts record. Must be empty for Launchpad. |
| `current_artifact_root` | Optional override for `mlsc-current` and `mlsc-mprage-only` validation only; a non-empty value is rejected for local profiles. Existing artifact integrity checks remain authoritative. |

`validate` is local-only: it checks the selected profile, explicit inputs,
positionally paired UMAPs, output locations, runtime dependencies and applicable
current-artifact integrity. It does not authenticate, read credentials, contact
remote services, create output directories, or run scientific processing. An
empty subject list validates configuration/dependencies only. Standard profiles
require a readable UMAP: omitted or empty entries are discovered locally;
explicit paths are never substituted. MPRAGE-only profiles reject UMAP paths.

The validated job is the handoff between the two operations. Submit repeats the
local input and artifact checks, compares the resolved identities, and fails
closed if inputs or artifacts changed. It does not rediscover a missing UMAP.
Local profiles execute synchronously without credentials or scheduler submission.
Authentication occurs only during remote submit. MLSC uses one authenticated session
for exact account selection and submission/monitoring; invalid account text
stops before submission. Launchpad retains its existing SSH/PBS behavior and
does not perform MLSC account discovery. Validation disallows credential fields;
remote submit requires the separate handoff, which is single-use and private.
The MATLAB handoff is stored under `/dev/shm` (tmpfs, owner-only) and consumed on
read. Replay and unsafe storage fail closed.

Create the request with all exact fields. Example for one standard-profile
subject with an explicit reference:

```matlab
request = struct();
request.schema = 'pseudoCT.headless-request/v2';
request.invocation_id = '01234567-89ab-cdef-0123-456789abcdef';
request.action = 'validate';
request.profile = 'mlsc-current';
request.subjects = {'/subject/MR/MPRAGE/one.dcm'};
request.umap_files = {'/subject/MR/UMAP/one.dcm'};
request.output_config = struct('layout', 'profile-default');
request.options = struct('correct_aliasing', [], ...
    'recenter_before_normalization', []);
request.resolved_job = struct();
request.group_account = '';
request.credential_handoff = '';
request.host_key_file = '';
request.current_artifact_root = '';
save('/private/requests/validate.mat', 'request', '-v6');
```

After successful validation, load the resolved job and prepare the separate
single-use handoff. Keep the same invocation ID and profile for submit:

```matlab
loaded = load('/private/results/validate.mat', 'result');
assert(strcmp(loaded.result.status, 'ready'));
resolved_job = loaded.result.resolved_job;
credential_handoff = pseudo_CT_credentials('store');

request.action = 'submit';
request.subjects = {};
request.umap_files = {};
request.output_config = struct();
request.options = struct();
request.resolved_job = resolved_job;
request.group_account = 'exact-mlsc-account'; % or '' for first returned account
request.credential_handoff = credential_handoff;
request.current_artifact_root = '';
save('/private/requests/submit.mat', 'request', '-v6');
```

Use a new request/result file for submit. A failed or stale validate result must
not be submitted. For `launchpad-legacy`, leave `group_account` and
`host_key_file` empty. Never put credential values or host-key contents in the
request, result, command line, environment, or logs; the request carries only a
handoff path.

## Result v2

The result MAT contains exactly one scalar `result` struct saved as `-v6`. Schema
`pseudoCT.headless-result/v2` has exactly these 17 fields:
`schema`, `invocation_id`, `action`, `profile`, `status`,
`error_code`, `error_message`, `authentication_status`, `submission_status`,
`backend`, `group_account`, `job_ids`, `scientific_completion`,
`dispatch_status`, `resolved_job`, `evidence`, and `diagnostics`. The MATLAB
validator `pseudo_CT_validate_headless_result` checks the exact field/type
contract and binds the result and resolved job to the invocation and profile.

| Field | Meaning |
|---|---|
| `status` | `ready`, `submitted`, or `failed`. `ready` means validation succeeded; `submitted` means the submit dispatcher returned without a reported operation error. A local submit is successful only when scientific completion is `completed`. Status alone does not prove remote acceptance or scientific completion. |
| `error_code` | Empty or a fixed code such as `INVALID_REQUEST`, `PROFILE_NOT_ALLOWED`, `INVALID_GROUP_ACCOUNT`, `AUTHENTICATION_FAILED`, `STALE_RESOLVED_JOB`, `HOST_KEY_UNAVAILABLE`, or `SUBMIT_FAILED`. |
| `error_message` | Fixed generic, non-secret message; exception text and credentials are not returned. |
| `authentication_status` | `not_attempted`, `authenticated`, `failed`, `not_observed`, or `not_applicable`. |
| `submission_status` | `not_attempted`, `accepted`, `rejected`, `unresolved`, or `not_observed`. MLSC acceptance requires backend acknowledgement with a positive job ID; uncertain submission is not retried outside existing reconciliation. |
| `backend` | `local`, `mlsc`, or `launchpad`, bound to the selected profile. |
| `group_account` | The exact selected MLSC account or empty when not applicable. |
| `job_ids` | Empty or positive integer scheduler IDs actually reported by the backend. |
| `scientific_completion` | `not_applicable`, `not_observed`, `completed`, or `failed`, based only on existing workflow/output-verification/finalization evidence. Authentication, dispatcher return, and scheduler exit alone do not establish science outcome. |
| `dispatch_status` | `not_dispatched`, `dispatched`, or `failed`; distinct from scheduler acknowledgement and scientific completion. |
| `resolved_job` | Bound resolved job, or an empty struct when validation/submit failed before one was available. |
| `evidence` | Non-secret validation and backend evidence. |
| `diagnostics` | Exact `code` and generic `message` fields, consistent with the result error fields. |

The exact enums are: `status` = `ready|submitted|failed`;
`authentication_status` = `not_attempted|authenticated|failed|not_observed|not_applicable`;
`submission_status` = `not_attempted|accepted|rejected|unresolved|not_observed`;
`backend` = `local|mlsc|launchpad`;
`scientific_completion` = `not_applicable|not_observed|completed|failed`; and
`dispatch_status` = `not_dispatched|dispatched|failed`.

The API validator is also available directly as
`pseudo_CT_validate_headless_result(RESULT_MAT, INVOCATION_ID, PROFILE)`.
Treat its bound fields—not the CLI exit status—as authoritative for completion.
Dispatch return (`dispatch_status='dispatched'`) is not scheduler acceptance.
For remote work, a positive backend job ID together with
`submission_status='accepted'` represents scheduler acceptance; neither proves
scientific completion. For a local submit, the operation is synchronous and
successful only with `scientific_completion='completed'`; a successful result
also has `status='submitted'`, `dispatch_status='dispatched'`, and an empty
`error_code`.

## Exit codes

These are the exit codes of the lower-level `bin/pseudoct-headless` launcher.
The user-facing `bin/pseudoct` command uses a different set (`0`, `64`-`69`;
launcher/runtime failure is `69`), described under
[User-facing `pseudoct` command](#user-facing-pseudoct-command).

| Code | Meaning |
|---:|---|
| `0` | Result contract validated and operation succeeded: validation is `ready`; a local submit is scientifically `completed`; a remote submit returned without a reported operation error. Remote acceptance/completion still comes only from the bound result fields. |
| `2` | Request or profile rejected. |
| `3` | Authentication, account selection, credential handoff, or submit operation failed. |
| `64` | Wrong number of command-line arguments. |
| `65` | Request MAT is missing or unreadable. |
| `66` | Result path is invalid, unwritable, or aliases the request path. |
| `69` | MATLAB executable is unavailable. |
| `70` | Launcher/bootstrap/runtime failure, or a missing, invalid, or inconsistent result record. |

Validation never authenticates or contacts a remote service. The CLI does not
resubmit a request to reconcile a result; inspect the bound MAT result before
deciding whether any further action is safe.

## User-facing `pseudoct` command

`bin/pseudoct` accepts the same canonical profiles and builds each request MAT
with MATLAB `save -v6`; it does not implement MAT serialization itself. A
single subject uses `--mprage FILE` and optional `--umap FILE`. A multi-subject
job uses a JSON object with explicit, positionally paired arrays:

```json
{"mprage":["/data/one/MPRAGE.dcm","/data/two/MPRAGE.dcm"],
 "umap":["/data/one/UMAP.dcm","/data/two/UMAP.dcm"]}
```

The `umap` array may be omitted to request the existing local autodiscovery
behavior. MPRAGE-only profiles reject it. Example:

```sh
bin/pseudoct validate --profile local-current --mprage /data/one/MPRAGE.dcm
bin/pseudoct run --profile local-current --config job.json --format jsonl
```

Processing overrides are `--correct-aliasing yes|no`,
`--recenter-before-normalization yes|no`, and `--cleanup-on-success yes|no`;
they map to the corresponding v2 request options. `--current-artifact-root PATH`
is for `mlsc-current` and `mlsc-mprage-only` validation only; a non-empty root
is rejected for local profiles. `run` always validates first and reuses that
invocation UUID and bound resolved job for submit. Remote `run` can use an
authorized `--credential-handoff PATH` or prompt for a username and non-echoed
password on `/dev/tty`, then create the existing single-use handoff. The request
contains only the handoff path, never credential values; validation disallows
credential fields. Remote headless submit requires a supplied handoff. The
MATLAB handoff is stored under `/dev/shm` (tmpfs, owner-only) and consumed on
read. Local profiles do not authenticate. The GUI's MLSC submit flow uses the
`MLSC submit login` dialog.

`--format text` (default) uses the shared progress formatter. Help and normal
text/progress/final output, including JSONL records, go to stdout; CLI errors go
to stderr. **Child launcher stderr is captured into a private diagnostics file
and is not forwarded to stderr.** JSONL result records report dispatch,
scheduler acknowledgement, and scientific completion independently. A remote
dispatch return is not scheduler acceptance, and acceptance does not establish
scientific completion. An accepted remote submission without completion
evidence exits 68 (unverified), not 0. Exit 0 means validation succeeded or
scientific completion was verified.

Each JSONL progress record has `type` (`progress`), `timestamp`, `level`, and
`message`, with optional `subject`, `stage`, `status`, and `job` fields omitted
when unknown. Subject values are run-local labels such as `S01`, not
patient-identifying filenames. `stage` uses the explicit `[n/m]` label when
available, and `job` contains the accepted scheduler job ID when known.
Consumers should treat these context fields as optional and must not infer
missing values.

The normal final JSONL record has `type`=`result` and fields:
`invocation_id`, `action`, `profile`, `outcome`, `exit_code`,
`headless_dispatch_returned`, `dispatch_status`,
`scheduler_submission_accepted`, `submission_status`, `authentication_status`,
`scientific_completion`, `scientific_completion_status`,
`scientific_completion_reason`, `backend`, `job_ids`, `group_account`,
`group_account_reason`, `error_code`, and `error_message`. Early error records
also have `type`=`result` and use the smaller shape `invocation_id`, `action`,
`profile`, `outcome`, `exit_code`, `headless_dispatch_returned`, `dispatch_status`,
`submission_status`, `scheduler_submission_accepted`,
`scientific_completion`, `scientific_completion_reason`, `job_ids`,
`error_code`, and `error_message`. An error after submit may additionally carry
`dispatch_status_reason`, `submission_status_reason`, and
`scheduler_submission_accepted_reason` when the outcome is unknown.

The CLI exit codes are `0` (validated or verified-completed), `64`
(usage/configuration), `65` (invalid request), `66` (authentication), `67`
(submission failure), `68` (scientific failure or completion unverified), and
`69` (launcher/runtime failure). These are distinct from the lower-level
`bin/pseudoct-headless` shell codes:

| Code | `pseudoct-headless` meaning |
|---:|---|
| `0`, `2`, `3` | Pass through the MATLAB operation status only when a usable result MAT is present. |
| `64` | Wrong number of command-line arguments. |
| `65` | Request MAT missing or unreadable. |
| `66` | Invalid result path. |
| `69` | MATLAB executable unavailable. |
| `70` | Runtime, bootstrap, or unexpected startup failure. |

## PIANO integration developer reference

Use `bin/pseudoct` as the process boundary; do not invoke the GUI or recreate
orchestration in PIANO. Supported commands are `validate` and `run`. The CLI
options are `--profile`, `--mprage`, `--umap`, `--config`, `--correct-aliasing`,
`--recenter-before-normalization`, `--cleanup-on-success`,
`--current-artifact-root`, `--group-account`, `--host-key-file`,
`--credential-handoff`, `--format text|jsonl`, and `-h|--help`. See the CLI
examples above and run `bin/pseudoct --help` for usage. JSONL progress, normal
result, and early-error record structures are specified above. Records are on
stdout; CLI errors go to stderr, but child launcher stderr is privately captured
and **not** forwarded there. Use the CLI exit-code list above for
`bin/pseudoct`; use the separate shell-code table only when invoking
`bin/pseudoct-headless` directly.

Validation is local-only and does not authenticate. Local profiles do not
authenticate. Remote CLI `run` prompts on `/dev/tty` or consumes an authorized
single-use handoff; a headless remote submit cannot prompt and requires the
caller to supply credentials through a handoff. The GUI's MLSC submit flow uses
the `MLSC submit login` dialog. A
successful validation returns a `pseudoCT.resolved-job/v1` handoff for submit;
submit rechecks it and fails closed if its bound inputs/artifacts are stale.
Dispatch return, scheduler acceptance (positive job ID and
`submission_status='accepted'`), and verified scientific completion are
separate outcomes. Local submit is synchronous and succeeds only when
`scientific_completion='completed'`.

Scientific outputs are written to `<subject-root>/MR_PET`, temporary data to
`<subject-root>/MR_PET/tmp`, and DICOM output to `<MR>/pseudo_muMAP`. CLI
request/result/summary/diagnostic scratch is under
`<install-root>/scratch/YYYY-MM-DD/<time>-pseudoct-cli.XXXXXX` and is removed
on CLI exit by its cleanup handler. The `pseudoct-headless` result MAT is written
at the caller-chosen path. **No cancellation API is provided.**

The PIANO backend credential-handoff adapter and end-to-end integration are not
yet implemented or verified. The supported credential flow is single-use and
private; request files contain no credential values. Do not treat this
developer reference as evidence that PIANO integration or remote processing has
been tested.

## Persistent run log

Each processed subject gets exactly one run log in that subject's own `MR_PET`
directory:

```text
<subject-root>/MR_PET/pseudoct-run-<UTC-YYYYMMDDTHHMMSSZ>-<invocationUUID>.log
```

`<invocationUUID>` is the CLI invocation ID (a fresh UUID for direct MATLAB
callers). No CLI option controls the log.

- **Persistence:** the log is kept on success, failure, and interruption.
  `cleanup_on_success` and the CLI exit handler never delete it (they remove
  only temporary request/result/credential/handoff scratch and, when enabled,
  `MR_PET/tmp`). There is no pruning, retention quota, or automatic deletion;
  you may delete a log manually.
- **Permissions and safety:** files are created `0600`. A newly created `MR_PET`
  is `0700`; an existing `MR_PET` keeps its mode. Creation is exclusive: an
  existing file or symlink is never overwritten or followed.
- **When it is created:** only after the inputs are validated and the subject's
  destination is resolved. Only `MR_PET` (if missing) and the log are created
  first; `tmp/` and DICOM directories are created afterward.
- **Failure before output:** if the failure occurs before the destination is
  established (usage, validation, or the resolver), or the log cannot be
  created, no subject log exists and the failure is reported only in public CLI
  output. There is no fallback storage location.
- **Privacy:** the log may contain detailed filesystem paths, which can include
  patient-identifying directory names; that is allowed only inside the subject's
  own log. Public output shows only the relative path, for example
  `run log: MR_PET/pseudoct-run-20261102T154500Z-<uuid>.log` (text mode only). With
  several subjects each text entry is labeled by subject number. The JSONL
  schema above is unchanged and carries no log-path field; JSONL consumers
  find the log at the documented location in each subject's `MR_PET`.
- **Credentials** are never written to the log or to the CLI's private capture
  (redacted before persistence).
- **Output contract unchanged:** stdout carries progress and results; CLI
  errors go to stderr; child launcher stderr is privately captured and never
  forwarded.

### Public stage model

Local Current console progress uses a fixed ten-stage model (nine stages when
DICOM output is omitted, i.e. NIfTI-only; the numbering is then contiguous
over the stages that apply):

| Stage | Name |
|---:|---|
| 1 | Prepare input MPRAGE |
| 2 | MPRAGE recentering (`SKIPPED` or `DONE` only) |
| 3 | Aliasing correction (`SKIPPED` or `DONE` only) |
| 4 | FreeSurfer MPRAGE normalization |
| 5 | MPRAGE alignment and subject masking |
| 6 | SPM New Segment |
| 7 | DARTEL atlas registration and reslicing (inverse warp and reslicing are `INFO` sub-steps) |
| 8 | Attenuation-map and QC generation |
| 9 | DICOM output generation (omitted for NIfTI-only output) |
| 10 | Output promotion and cleanup |

The text console prints the stage number only on stage entry; continuation rows
leave the stage cell blank. Every row has a status: `ACTIVE`, `DONE`,
`SKIPPED`, `INFO`, `WARN`, `ERROR`, or `VERIFIED`. Long-running computation
heartbeats are `INFO` rows that name the active operation, for example
`SPM New Segment still running (elapsed 10:00).` The `WAIT` status is used only
by MLSC and Launchpad heartbeats, not by Local Current. A FreeSurfer
normalization failure is reported as a stage-4 `ERROR` with no stage-4 `DONE`.
Stage 10 reports `DONE` ("Outputs promoted") only after promotion succeeded; it
does not claim that cleanup completed, and a cleanup failure is a separate
`WARN` row.

In JSONL, every stage event carries the full label in `stage` (for example
`"[6/10]"`), with the same schema as before and no new fields. The per-subject
`MR_PET/pseudoct-run-*.log` keeps the complete raw diagnostics.

The real-run verification and its separate supporting offline replay are
documented in [Local Current logging verification](#local-current-logging-verification).

## Local Current logging verification

On 2026-11-03, a real scientific Local Current run was executed with the CLI;
the CLI exit code was 0 (recorded exit-code file: `PSEUDOCT_EXIT_CODE=0`), and
one subject completed (1 succeeded, 0 failed). The console presented
`[1/10]` through `[10/10]`, each once on entry. The per-subject persistent log
under `MR_PET/` was present with owner-only permissions (`0600`) and recorded
the warning summary. Warnings were grouped by occurrence (for example,
"(2 occurrences)"); the persistent log contains a `Warning summary` block.
The attenuation map `att_map.nii` has SHA-256
`1517efbe3fbb8e0f4df3fb3b2a4e40c387ba09fbcbac326496fe47cf8a6981ff`, which
matched the expected value exactly. Converter limit: no separate
converter-diagnostics section exists; `dcm2nii` input, output, and completion
lines are recorded in the run log. Offline replay of recorded formatter inputs
remains a separate supporting check and is not the basis of the claim. Earlier
real MLSC Current (2026-11-01/02) and Launchpad Legacy (2026-11-02) executions
predate the finalized logging contract and used an eight-stage presentation;
they establish scientific execution only and are not acceptance of the new
presentation. The persistent detailed log labels some compiled-stage messages
with an internal eight-stage counter (`[stage N/8]`) while the console uses ten
public stages; this is a provenance difference and is not corrected here.
