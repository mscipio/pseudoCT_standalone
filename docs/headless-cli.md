# Standalone headless CLI

`bin/pseudoct-headless REQUEST.mat RESULT.mat` runs the versioned MATLAB v5
headless interface through MATLAB R2010b. The launcher works from another
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
with `-v6` (MAT v5-compatible). Its exact fields are:

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
| `resolved_job` | Empty scalar struct for validate; the `result.resolved_job` returned by successful validate for submit. It carries bound MPRAGE/UMAP records, options, output paths, and artifact/input identities, but no credentials or live sessions. |
| `group_account` | Empty for validate, local profiles, and Launchpad. Optional free text for MLSC submit; empty selects the first account returned by MLSC, while a supplied value is trimmed and matched exactly. |
| `credential_handoff` | Empty for validate and local submit; required path to a private, single-use handoff MAT for remote submit. Never embed username/password values in the request. |
| `host_key_file` | Empty unless MLSC submit opts into strict host-key verification with a known-hosts record. Must be empty for Launchpad. |
| `current_artifact_root` | Optional override for `mlsc-current` and `mlsc-mprage-only` validation only; empty otherwise. Existing artifact integrity checks remain authoritative. |

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
does not perform MLSC account discovery. A credential handoff is consumed and
removed before authentication; replay and unsafe storage fail closed.

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
`host_key_file` empty. Never put credentials, host-key contents, or secrets in
MAT files other than the protected handoff, shell text, logs, source, results,
or environment variables.

## Result v2

The result MAT contains exactly one scalar `result` struct saved as `-v6`. Its
exact fields are `schema`, `invocation_id`, `action`, `profile`, `status`,
`error_code`, `error_message`, `authentication_status`, `submission_status`,
`backend`, `group_account`, `job_ids`, `scientific_completion`,
`dispatch_status`, `resolved_job`, `evidence`, and `diagnostics`. The schema is
`pseudoCT.headless-result/v2`; the MATLAB validator
`pseudo_CT_validate_headless_result` checks the exact field/type contract and
binds the result and resolved job to the invocation and profile.

| Field | Meaning |
|---|---|
| `status` | `ready` for successful validation; `submitted` when the submit dispatcher returned without a reported operation error; otherwise `failed`. A local submit is `submitted` only when scientific completion is `completed`. Inspect evidence fields; status alone does not prove remote acceptance or scientific completion. |
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

The API validator is also available directly as
`pseudo_CT_validate_headless_result(RESULT_MAT, INVOCATION_ID, PROFILE)`.
Treat its bound fields—not the CLI exit status—as authoritative for completion.
For a local submit, scientific success requires `status='submitted'`,
`dispatch_status='dispatched'`, `scientific_completion='completed'`, and an empty
`error_code`. A remote dispatch or accepted scheduler ID does not prove
scientific success.

## Exit codes

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
they map to the corresponding v2 request options. Current profiles also accept
`--current-artifact-root PATH`. `run` always validates first and reuses that
invocation UUID and bound resolved job for submit. Remote profiles accept an
authorized `--credential-handoff PATH`, or prompt for a username and
non-echoed password on a terminal and create the existing single-use handoff.
Passwords are never CLI arguments, environment values, JSON, or logs.

`--format text` (default) uses the shared progress formatter. `--format jsonl`
emits JSON progress records and one final result record on stdout; diagnostics
remain on stderr. Result records report dispatch, scheduler acknowledgement,
and scientific completion independently. For remote jobs, an accepted
submission without completion evidence exits 68 (unverified), not 0. Exit 0
means validation succeeded or scientific completion was verified; codes 64-69
distinguish usage/configuration, invalid request, authentication, submission,
scientific failure/unverified completion, and CLI runtime failure respectively.

Each JSONL progress record requires `type` (`progress`), `timestamp`, `level`,
and `message`. `subject`, `stage`, `status`, and `job` are included only when
known; absent context is omitted rather than emitted as `null` with a reason.
Subject values are run-local labels such as `S01`, not patient-identifying
filenames. `stage` uses the explicit `[n/m]` label when available, and `job`
contains the accepted scheduler job ID when known. Consumers should treat these
context fields as optional and must not infer missing values.
