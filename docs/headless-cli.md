# Headless API and CLI

The MATLAB headless API and terminal CLI provide non-GUI entry points for
validation and execution. The API uses versioned MATLAB v5 MAT files; the
public shell command adds text/JSONL progress and exit codes.

## Entry points

```matlab
pseudo_CT_headless(request_path, result_path)
```

The lower-level operation accepts a request and result path:

```sh
bin/pseudoct headless REQUEST.mat RESULT.mat
```

`REQUEST.mat` must contain a single scalar variable named `request`, saved as
MAT v5 (for example with `save(..., '-v6')`). The result parent must already
exist and be writable. Direct launcher result files must be under the subject's
`MR_PET/tmp/`; its private invocation directory is removed on exit. The default
MATLAB executable is `/usr/pubsw/common/matlab/7.11/bin/matlab`; set
`PSEUDOCT_MATLAB` to use another executable.

For shell and application callers, use `bin/pseudoct`:

```sh
bin/pseudoct validate --profile local \
  --mprage /subject/MR/MPRAGE/one.dcm \
  --umap /subject/MR/UMAP/one.dcm --format jsonl
bin/pseudoct run --profile local \
  --mprage /subject/MR/MPRAGE/one.dcm \
  --umap /subject/MR/UMAP/one.dcm --format jsonl
```

The four accepted profiles are `local`, `mlsc`, `local-mprage-only`, and
`mlsc-mprage-only`. Standard profiles require a UMAP reference; an omitted UMAP
may be discovered locally. MPRAGE-only profiles reject UMAP inputs. For a
multi-subject request, `--config` accepts a JSON object with a non-empty
`mprage` string array and an optional positionally paired `umap` string array:

```json
{"mprage":["/data/one/MPRAGE.dcm","/data/two/MPRAGE.dcm"],
 "umap":["/data/one/UMAP.dcm","/data/two/UMAP.dcm"]}
```

Options include `--correct-aliasing yes|no`,
`--recenter-before-normalization yes|no`, `--cleanup-on-success yes|no`,
`--current-artifact-root PATH`, `--group-account ACCOUNT`,
`--host-key-file FILE`, `--credential-handoff FILE`, and
`--format text|jsonl`. Run `bin/pseudoct --help` for the complete installed
usage. The CLI creates private request/result/runtime files under the selected
subject's `MR_PET/tmp/` and removes its invocation directory on exit.

## MAT v2 request: validate, then submit

The `request` variable must be a scalar struct with exactly these fields:

| Field | Meaning |
|---|---|
| `schema` | `pseudoCT.headless-request/v2`. |
| `invocation_id` | UUID identifying the validate→submit workflow; reuse it for submit. |
| `action` | `validate` or `submit`. |
| `profile` | One of the four canonical profile keys above. |
| `subjects` | Validate: MPRAGE path(s). Submit: empty. |
| `umap_files` | Validate: empty for discovery or positionally paired path(s). Submit: empty. |
| `output_config` | Validate: empty or `struct('layout','profile-default')`. Submit: empty struct. |
| `options` | Validate: optional aliasing, recentering, and cleanup booleans. Submit: empty struct. |
| `resolved_job` | Validate: empty struct. Submit: the `resolved_job` from a successful validation result. |
| `group_account` | Empty except optional MLSC account selection at submit. |
| `credential_handoff` | Empty for validate and local submit; remote submit uses a private single-use handoff path. |
| `host_key_file` | Optional MLSC host-key file path; do not include host-key contents. |
| `current_artifact_root` | Optional MLSC artifact-validation override; not valid for local profiles. |

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

Validation resolves and checks the selected profile, inputs, outputs,
dependencies, and applicable MLSC artifact integrity. It does not authenticate,
contact remote services, or run scientific processing. Submit uses the bound
resolved job and rechecks inputs/artifacts; stale or changed inputs fail closed.
Local submit runs synchronously. MLSC submit uses the supported authentication
flow; request/result files, command-line arguments, and environment variables
must not contain passwords or other credential values. Use a separate submit
request/result file and the one-time handoff path when submitting remotely.

## Result and completion semantics

The result MAT contains one scalar `result` struct with schema
`pseudoCT.headless-result/v2`. Its status is `ready`, `submitted`, or `failed`.
The result also separates dispatch, authentication, scheduler submission, and
scientific completion evidence. A successful validation is `ready`; it is not
a processing result. A remote positive job ID and accepted scheduler
submission do not establish scientific completion. MLSC `COMPLETED` is success
only when required outputs and copy-back evidence have been verified. A local
submit is synchronous and reports success only after verified completion.

Use `pseudo_CT_validate_headless_result(RESULT_MAT, INVOCATION_ID, PROFILE)`
to validate and bind a result to its request. Inspect the bound status and
completion fields rather than inferring completion from process exit alone.

## Exit codes

`bin/pseudoct` returns:

| Code | Meaning |
|---:|---|
| `0` | Validation passed or the run completed with verified results. |
| `64` | Usage or configuration error. |
| `65` | Request or validation failure. |
| `66` | Authentication failure. |
| `67` | Submission failure. |
| `68` | Scientific failure or completion not verified. |
| `69` | Launcher or runtime failure. |

`bin/pseudoct headless` uses `0` for success, `2` for a rejected request/profile,
`3` for authentication/account/submission failure, for any other failed headless
result (including validation failures), and for a submitted result whose
scientific completion is not verified (dispatch or scheduler acceptance alone is
not completion evidence), `64`–`66` for argument or path errors, `69` when MATLAB
is unavailable, and `70` for bootstrap/runtime or invalid-result failures.

## Cancellation policy

- **Timeout:** when polling reaches the configured timeout before terminal
  accounting, the lifecycle requests cancellation (`scancel`) and reports the
  outcome from accounting.
- **Interruption after submission:** a polling error or a lost connection after
  the Slurm job was accepted never cancels the job. The result is reported as
  unverified (`bin/pseudoct run`: exit `68`; raw `headless`: exit `3`). The job
  ID and the manual command `scancel <job id>` are printed. The remote job keeps
  running until it is cancelled by hand.
- **Before submission:** nothing was accepted by the scheduler, so there is
  nothing to cancel.
