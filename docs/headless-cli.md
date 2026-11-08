# Headless API and CLI

This page is the authoritative reference for the terminal CLI (`bin/pseudoct`)
and the MATLAB headless API (`pseudo_CT_headless`): options, validate and submit
semantics, logs and progress, exit codes, and cancellation. Installation is in
[Installation](installation.md); packaging and runtime selection are in
[Release catalog and layout](releases.md). Run `bin/pseudoct --help` for the
installed usage text.

## Entry points

```sh
bin/pseudoct run validate --profile local \
  --mprage /subject/MR/MPRAGE/one.dcm \
  --umap /subject/MR/UMAP/one.dcm --format jsonl
bin/pseudoct run run --profile local \
  --mprage /subject/MR/MPRAGE/one.dcm \
  --umap /subject/MR/UMAP/one.dcm --format jsonl
```

`run validate` checks a request. `run run` validates the same request and then
submits it; see [Validate and submit](#validate-and-submit).

The lower-level operation takes one request MAT file and writes one result MAT file:

```sh
bin/pseudoct headless REQUEST.mat RESULT.mat [--mcr LABEL] [--mcr-root DIR]
```

`--mcr` and `--mcr-root` apply to an installed distribution only; see
[Release selection](#release-selection-installed-distribution).

```matlab
pseudo_CT_headless(request_path, result_path)
```

`REQUEST.mat` must contain a single scalar variable named `request`, saved as
MAT v5 (for example with `save(..., '-v6')`). The result parent must already
exist and be writable. Direct launcher result files must be under the subject's
`MR_PET/tmp/`; the private invocation directory there is removed on exit.

In a repository checkout, the headless bootstrap runs MATLAB. Its default
executable is `/usr/pubsw/common/matlab/7.11/bin/matlab`; set `PSEUDOCT_MATLAB`
to use another executable. An installed distribution runs its compiled engine
with the selected MATLAB Runtime instead (see [Releases](releases.md)).

## Release selection (installed distribution)

An installed distribution (`runtimes/` beside `bin/`) ships one compiled release per
MATLAB Runtime. `bin/pseudoct` selects one of them for `run`, `headless` and `resolve`.
A repository checkout refuses `--mcr` and `--mcr-root`, and `resolve` requires an
installed distribution.

- `--mcr LABEL`: the release, as an exact catalog label such as `R2019b`. The default is
  the catalog default, R2010b.
- `--mcr-root DIR`: the MATLAB Runtime root. Without it, the root is the catalog location
  `/usr/pubsw/common/matlab/<D>` of the release, where `<D>` is the first two dotted
  components of its `matlab_version`. The runtime identity is always
  validated against the catalog, so a root never bypasses that check.
- `--list-releases`: prints one line per installed release, as
  `label<TAB>mcr_version<TAB>default|-`. It needs no MATLAB or MCR. In a repository
  checkout it lists every entry in `config/releases.json`.
- `resolve [--mcr LABEL] [--mcr-root DIR]`: validates one MATLAB Runtime and prints
  single-quoted, sourceable `PSEUDOCT_EXE`, `PSEUDOCT_MCR_ROOT`, `PSEUDOCT_RUNNER`,
  `PSEUDOCT_INSTALL_ROOT`, `PSEUDOCT_RUNTIME_RELEASE` and `PSEUDOCT_RUNTIME_MCR_ROOT` lines.

An unknown label, a bad `--mcr-root` value or a usage error exits `64`. An incomplete
release, an unsupported architecture, or a missing or mismatched MATLAB Runtime exits
`69`. Details are in [Releases](releases.md#release-and-matlab-runtime-root-selection).

## Options (`run validate|run`)

- `--profile NAME`: one of the four canonical profiles (`local`, `mlsc`,
  `local-mprage-only`, `mlsc-mprage-only`); see [Installation](installation.md#supported-profiles).
- `--mprage FILE [--umap FILE]`: one subject. The UMAP may be omitted for local
  discovery on standard profiles. MPRAGE-only profiles reject `--umap`.
- `--config job.json`: several subjects. The JSON object has a non-empty `mprage`
  string array and an optional positionally paired `umap` string array:

  ```json
  {"mprage":["/data/one/MPRAGE.dcm","/data/two/MPRAGE.dcm"],
   "umap":["/data/one/UMAP.dcm","/data/two/UMAP.dcm"]}
  ```

- `--correct-aliasing yes|no`, `--recenter-before-normalization yes|no`,
  `--cleanup-on-success yes|no`: override the profile defaults.
- `--current-artifact-root PATH`: development-only override. It is accepted only
  by the MLSC profiles (`mlsc`, `mlsc-mprage-only`); the local profiles reject it
  with exit `64` (the same rule applies to the MATLAB frontend and the headless
  API, which return the identifier `run_pseudo_CT:InvalidMlscCurrentOverride`).
  An installed distribution does not need it. No other artifact-root or
  Gate-A-record override is exposed.
- `--group-account ACCOUNT`, `--host-key-file FILE`, `--credential-handoff FILE`:
  MLSC inputs. The handoff is an existing single-use credential file created for
  the submit step. Secrets are never accepted on the command line.
- `--format text|jsonl`: output format (default `text`).

## Validate and submit

This is the single authoritative description of validation and submission.

- **Validate** (`run validate`, the GUI Validate button, or a `validate` request)
  resolves and checks the selected profile, inputs, outputs, dependencies and,
  for MLSC, the applicable artifact integrity. It does not authenticate, contact
  remote services, or run scientific processing. A successful validation reports
  `ready`; it is not a processing result.
- **Submit** (`run run`, the GUI Submit button, or a `submit` request) uses the
  resolved job bound by a successful validation and rechecks inputs and artifacts;
  changed or stale inputs fail closed. Local submit runs synchronously in the
  current invocation. MLSC submit authenticates (a terminal prompt, or the
  one-time `--credential-handoff` file), submits to Slurm and monitors the job
  until a verified outcome or an unverified one (see [Cancellation](#cancellation-and-interruption)).
- **GUI gate** (`run_pseudo_CT`): Submit is enabled only after a successful
  Validate of exactly the current profile, input files and options. Changing any
  input, option or input file disables Submit until Validate runs again. A
  submission consumes its validation, so each Submit needs a new Validate. For
  MLSC, Submit asks for the login in a dialog and passes only a single-use
  credential handoff path to the launcher.

## Output, logs and progress

- **Final outputs** are written under `<subject>/MR_PET/` (NIfTI, QC TIFF and
  version text). DICOM output goes to `<subject>/MR/pseudo_muMAP/` for the
  `nifti-and-dicom` profiles only. Inspect the QC image before use (see
  [Scientific notes](scientific-notes.md#interpretation-and-quality-control)).
- **Run log**: each requested subject gets one owner-only log,
  `<subject>/MR_PET/pseudoct-run-<UTC>-<invocationUUID>.log`. It is created only
  after validation and output-location resolution, and the pipeline never deletes
  or prunes it.
- **Structured events**: scientific and MLSC lifecycle events are appended as
  JSONL to `<subject>/MR_PET/pseudoct-run-<UTC>-<invocationUUID>.jsonl`, retained
  after success, failure and cancellation.
- **Progress**: `--format text` prints progress to the console; `--format jsonl`
  emits one JSON record per line (progress and final result records). The result
  record carries the exit code and, for MLSC, the job IDs and run-log paths.
- **Intermediates**: `<subject>/MR_PET/tmp/` holds per-subject working files. They
  are removed after successful promotion when `cleanup_on_success` is true, and
  kept when promotion fails or cleanup is off. The CLI's private invocation
  directory under `MR_PET/tmp/` (request/result MAT files, handoff path, captured
  MATLAB diagnostics) is removed when the launcher exits.
- **Window output**: the MATLAB window stays open after a request, but MATLAB is
  busy while Validate or Submit runs, because the launcher runs synchronously.

## MATLAB request (v2): validate, then submit

The `request` variable must be a scalar struct with exactly these fields:

| Field | Meaning |
|---|---|
| `schema` | `pseudoCT.headless-request/v2`. |
| `invocation_id` | UUID identifying the validate→submit workflow; reuse it for submit. |
| `action` | `validate` or `submit`. |
| `profile` | One of the four canonical profile keys. |
| `subjects` | Validate: MPRAGE path(s). Submit: empty. |
| `umap_files` | Validate: empty for discovery or positionally paired path(s). Submit: empty. |
| `output_config` | Validate: empty or `struct('layout','profile-default')`. Submit: empty struct. |
| `options` | Validate: optional aliasing, recentering and cleanup booleans. Submit: empty struct. |
| `resolved_job` | Validate: empty struct. Submit: the `resolved_job` from a successful validation result. |
| `group_account` | Empty except optional MLSC account selection at submit. |
| `credential_handoff` | Empty for validate and local submit; remote submit uses a private single-use handoff path. |
| `host_key_file` | Optional MLSC host-key file path; do not include host-key contents. |
| `current_artifact_root` | Optional development-only MLSC artifact-validation override; rejected for local profiles. |

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

Submit uses the bound resolved job and rechecks inputs and artifacts. Requests,
results, command-line arguments and environment variables must not contain
passwords or other credential values; remote submit uses a separate submit
request/result pair and the one-time handoff path.

## Result and completion semantics

The result MAT contains one scalar `result` struct with schema
`pseudoCT.headless-result/v2`. Its status is `ready`, `submitted` or `failed`.
The result separates dispatch, authentication, scheduler submission and
scientific completion evidence. A remote positive job ID and an accepted
scheduler submission do not establish scientific completion. MLSC `COMPLETED` is
success only when required outputs and copy-back evidence have been verified.
A local submit reports success only after verified completion.

Use `pseudo_CT_validate_headless_result(RESULT_MAT, INVOCATION_ID, PROFILE)` to
validate and bind a result to its request. Inspect the bound status and
completion fields rather than inferring completion from process exit alone.

## Exit codes

`bin/pseudoct run validate|run` returns:

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

`bin/pseudoct headless` returns `0` for success; `2` for a rejected request or
profile; `3` for an authentication, account or submission failure, for any other
failed headless result (including validation failures), and for a submitted
result whose scientific completion is not verified (dispatch or scheduler
acceptance alone is not completion evidence); `64`–`66` for argument or path
errors; `69` when MATLAB is unavailable; and `70` for bootstrap, dispatch,
runtime or invalid-result failures (not listed in `--help`).

## Cancellation and interruption

- **Timeout:** when polling reaches the configured timeout before terminal
  accounting, the lifecycle requests cancellation (`scancel`), then reports the
  outcome from accounting. If terminal accounting is still unavailable, the
  result is a timeout failure, not a completion.
- **Interruption after submission:** a polling error or a lost connection after
  the Slurm job was accepted never cancels the job. The result is reported as
  unverified (`bin/pseudoct run`: exit `68`; raw `headless`: exit `3`). The job ID
  and the manual command `scancel <job id>` are printed. The job keeps running
  until it is cancelled by hand. Interrupting the launcher (for example Ctrl-C)
  is not a cancellation: the launcher does not call `scancel`.
- **Before submission:** nothing was accepted by the scheduler, so there is
  nothing to cancel. Cancelling the MLSC login dialog stops before submission
  ("no Slurm job was submitted").
- **No in-application cancel control:** the window's Close button closes the
  window only. It does not stop a running request, and a synchronous request
  keeps MATLAB busy.

## Related

- [README](../README.md): overview and profile summary.
- [Installation](installation.md): installation, requirements and profiles.
- [Releases](releases.md): packaging, runtime identity and layout.
- [Scientific notes](scientific-notes.md): method and evidence limits.
- [Tests](../tests/README.md): offline checks.
