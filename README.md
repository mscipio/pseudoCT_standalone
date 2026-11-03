# pseudoCT_standalone

Atlas-based pseudoCT generation for PET/MR attenuation correction from a T1-weighted MPRAGE, using the SPM8-based method of Izquierdo-Garcia et al. (*Journal of Nuclear Medicine*, 2014;55(11):1825–1830).

For Martinos users, use the centrally deployed version and the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/) for the complete workflow. For external installation requirements and configuration, see [Installation](docs/installation.md). Method, evidence, and limitations are summarized in [Scientific notes](docs/scientific-notes.md).

## Quick start (Martinos)

Use the deployed version under `/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/`. Add the installation root to MATLAB's path:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
% To pin an installed numbered release, replace <version> with its number:
% addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-<version>')
run_pseudo_CT
```

Select **PseudoCT v3 — MLSC** for routine remote processing, or **PseudoCT v3 — Local** to process locally. Both use the current-lineage compiled payload. Legacy Aether choices are retained for historical compatibility. See [Profiles and release](#profiles-and-release) for profile details.

## Choosing an execution method

The project has four interfaces. Choose the GUI for a person at MATLAB, MATLAB scripting for MATLAB-driven workflows, the MAT v2 API for MATLAB-native integrations, or the terminal CLI for process-based integrations such as PIANO Hub.

| Interface | Intended audience / use case | Interactive or noninteractive | Runtime requirements | Configuration / input | Authentication | Progress and results | External application integration |
|---|---|---|---|---|---|---|---|
| MATLAB GUI (`run_pseudo_CT()` with no arguments / `load_mr_4_AC`) | A user selecting a profile and files in MATLAB | Interactive | MATLAB R2010b or later | Profile dialog and GUI file selectors | Local profiles do not authenticate; remote MLSC or Launchpad runs can prompt for login | MATLAB progress/log messages; outputs are written beside the input subject as described below | Not recommended as an application boundary; it requires GUI interaction |
| MATLAB scripting (`run_pseudo_CT` with named arguments) | MATLAB scripts or MATLAB-hosted automation | Depends on arguments: explicit subjects use list mode, but omitted/empty subjects open the GUI. Remote non-headless runs may prompt for MLSC login. | MATLAB R2010b or later | Name/value arguments, including profile, subject paths, options, and optional resolved jobs | Validation does not authenticate; remote non-headless execution may prompt. Headless use has separate credential handling. | Returns a MATLAB report; generated files use the same subject-relative output locations | Useful from MATLAB; not a generic process protocol for external applications |
| Headless MATLAB API v2 (`pseudo_CT_headless(request_path, result_path)`) | MATLAB-native callers needing the MAT-file validate/submit contract | Noninteractive | MATLAB R2010b or later | MAT v5 request and result files using the v2 schemas | Validation is local-only; remote submit requires a credential handoff | Writes a v2 result MAT file at the requested path, including status and completion fields | Suitable for MATLAB-based integrations; other applications should generally use the CLI |
| Public terminal CLI (`bin/pseudoct`) | Shell users and applications invoking a process | `validate` is noninteractive; remote `run` prompts on `/dev/tty` unless given an authorized handoff | Shell launcher and a usable MATLAB R2010b runtime; defaults to `/usr/pubsw/common/matlab/7.11/bin/matlab`, overridable with `PSEUDOCT_MATLAB` | `--profile`, single-subject `--mprage` / optional `--umap`, or multi-subject `--config` JSON | Validation does not authenticate; remote `run` prompts or consumes an existing authorized single-use handoff | Text or JSONL records on stdout; CLI scratch request/result/summary/diagnostic files are under `<install-root>/scratch/...` | Recommended public boundary for external application integration |

### MATLAB GUI

Launch with no arguments:

```matlab
run_pseudo_CT
```

The profile dialog is titled **Pseudo-CT Profile** and has **Run Selected** and **Cancel** actions. Choose a profile and click **Run Selected**. The GUI opens for the selected profile. Use **Browse MPRAGE...** to choose an MPRAGE (DICOM or NIfTI); the GUI attempts local UMAP discovery. If discovery does not find the desired reference, use **Browse UMAP...** to select one explicitly. The **Run pseudoCT** action performs local validation and then submission; it is not a separate visible Validate action. A remote MLSC run can show the **MLSC submit login** dialog.

Outputs are resolved relative to the subject: the processing/output directory is `<subject-root>/MR_PET`, temporary files use `<subject-root>/MR_PET/tmp`, and DICOM output uses `<MR>/pseudo_muMAP`. Final NIfTI, QC, and version outputs are in `MR_PET`. The GUI does not provide a separate output-location widget.

### MATLAB scripting

`run_pseudo_CT` accepts name/value arguments. For example:

```matlab
run_pseudo_CT( ...
    'profile', 'local-current', ...
    'subjects', {'/path/to/MPRAGE.dcm'}, ...
    'umap_files', {'/path/to/UMAP.dcm'});
```

Accepted named arguments and types:

| Argument | Accepted type |
|---|---|
| `profile` | Character vector |
| `subjects` | Character vector or cell array |
| `umap_files` | Empty, character vector, or cell array |
| `correct_aliasing` | Empty or scalar numeric/logical `0` or `1` |
| `recenter_before_normalization` | Empty or scalar numeric/logical `0` or `1` |
| `cleanup_on_success` | Empty or scalar logical/numeric `0` or `1` |
| `group_account` | Character vector |
| `mlsc_current_artifact_root` | Character vector |
| `headless_mode` | Scalar logical |
| `headless_credentials` | Scalar struct |
| `mlsc_host_key_provider` | Empty, character vector, or function handle |
| `resolved_jobs` | Struct |

MATLAB R2010b is the minimum. MATLAB scripting does **not** by itself make execution noninteractive: if `subjects` is omitted or empty, the collection GUI opens. Remote non-headless execution may prompt for MLSC login. `headless_credentials` is for scripting-based headless use; do not embed passwords in scripts.

### Headless MATLAB API v2

The exact API is `pseudo_CT_headless(request_path, result_path)`. It accepts a MAT v5 request using the `pseudoCT.headless-request/v2` schema and writes a `pseudoCT.headless-result/v2` MAT result at `result_path`. The intended flow is `validate`, then `submit` using the `resolved_job` returned by validation. Validation is local-only; remote submission requires a credential handoff. See [Headless CLI and API reference](docs/headless-cli.md) for the full request/result schemas and constraints. The shell launcher for this API is separate from the public `bin/pseudoct` CLI and has the exact invocation `pseudoct-headless REQUEST.mat RESULT.mat`.

### Public terminal CLI

Use `bin/pseudoct --help` to see the supported options. The CLI supports `validate` and `run`; both validate first, while `run` then submits the resolved job. For a single subject, UMAP may be omitted to allow local discovery:

The CLI builds on the structured Headless MAT v2 API through `bin/pseudoct-headless` and adds a shell-friendly contract with progress events and exit codes.

```sh
bin/pseudoct validate --profile local-current --mprage /path/to/MPRAGE.dcm --umap /path/to/UMAP.dcm --format jsonl
bin/pseudoct run --profile local-current --mprage /path/to/MPRAGE.dcm --umap /path/to/UMAP.dcm --format jsonl
```

Or supply a multi-subject JSON file. It must contain a non-empty `mprage` string array and may contain a positional `umap` string array of equal length. These are the only allowed keys:

```json
{
  "mprage": ["/data/subject-1/MPRAGE.dcm"],
  "umap": ["/data/subject-1/UMAP.dcm"]
}
```

```sh
bin/pseudoct validate --profile local-current --config job.json --format jsonl
bin/pseudoct run --profile local-current --config job.json --format jsonl
```

`--format` accepts `text` or `jsonl`. JSONL progress records can include a subject, stage, status, and job identifier; the final record has `type=result`. Remote `run` prompts for credentials on `/dev/tty`. `--credential-handoff FILE` consumes an existing authorized single-use handoff; it is not a password-file option. CLI request/result/summary/diagnostic scratch files are created under `<install-root>/scratch/YYYY-MM-DD/<time>-pseudoct-cli.XXXXXX` and removed on exit.

CLI exit codes:

| Code | Meaning |
|---:|---|
| `0` | Validated successfully or run completed with verified completion |
| `64` | Usage or configuration error |
| `65` | Invalid request or validation failure |
| `66` | Authentication failure |
| `67` | Submission failure |
| `68` | Scientific failure or completion unverified |
| `69` | Launcher/runtime failure |

Lower-level headless launcher exit codes (`bin/pseudoct-headless`):

| Code | `pseudoct-headless` meaning |
|---:|---|
| `0`, `2`, `3` | Pass through the MATLAB operation status only when a usable result MAT is present. |
| `64` | Wrong number of command-line arguments. |
| `65` | Request MAT missing or unreadable. |
| `66` | Invalid result path. |
| `69` | MATLAB executable unavailable. |
| `70` | Runtime, bootstrap, or unexpected startup failure. |

### CLI/headless-supported profiles

These are the seven profile keys accepted by the CLI and headless API:

| Key | Environment / lineage | MPRAGE-only? | Output policy |
|---|---|---:|---|
| `local-current` | Local / current compiled payload | No | NIfTI + DICOM |
| `local-legacy` | Local / legacy-v2 (Aether) | No | NIfTI + DICOM |
| `local-mprage-only` | Local / current | Yes | NIfTI only |
| `mlsc-current` | MLSC / current compiled payload | No | NIfTI + DICOM |
| `mlsc-legacy` | MLSC / legacy-v2 (Aether) | No | NIfTI + DICOM |
| `mlsc-mprage-only` | MLSC / inherits current | Yes | NIfTI only |
| `launchpad-legacy` | Launchpad / legacy-v2 (Aether) | No | NIfTI + DICOM |

Profile discovery also discovers `devel`, but routine GUI choices omit it and it is **not** one of the seven CLI/headless profile keys.

## Profiles and release

The selector groups choices under **Standard Processing**, **MPRAGE-only Processing**, and **Legacy Processing**. Standard choices are **PseudoCT v3 — Local** (`local-current`) and **PseudoCT v3 — MLSC** (`mlsc-current`); MPRAGE-only choices are **MPRAGE-only — Local** and **MPRAGE-only — MLSC**. The MPRAGE-only MLSC profile inherits the current lineage and uses NIfTI-only output. The three historical choices are **PseudoCT v2 (Aether) — Local**, **PseudoCT v2 (Aether) — MLSC**, and **PseudoCT v2 (Aether) — Launchpad**. Legacy profiles require a MATLAB R2010b host and are retained for historical compatibility. See [Installation](docs/installation.md) for profile descriptions, availability, and requirements.

### Profile selector screenshots

![Current MATLAB selector with the recommended PseudoCT v3 — MLSC choice selected](docs/help/assets/profile-selector.png)

*Figure 1. Standard Processing in the current installed MATLAB selector (R2026a Update 2), before processing starts.*

![Current MATLAB selector with Standard Processing, MPRAGE-only Processing, and Legacy Processing expanded](docs/help/assets/profile-selector-all-groups.png)

*Figure 2. All selector groups expanded, showing both MPRAGE-only choices and the three historical Aether choices.*

The source version metadata is **3.2.0** (current candidate v3.2.0-rc2); no production deployment is claimed. v3.0.2 is the previous published archive in the preserved [release history](CHANGELOG.md); v3.0.0 and v3.0.1 remain withdrawn. The accepted job 10515471 result is dataset-specific, its association with the cited executable is unverified, and the original dirty-source fingerprint was not independently reconstructed. v3.2.0-rc2 changes profile selection/dispatch only: the R2010b compiled payload is reused unchanged and no new scientific processing is claimed. Always inspect generated QC before using an attenuation map.

The shared orchestration API separates local `validate` from `submit`. Validation resolves each MPRAGE and its positionally paired UMAP without login; submit rechecks the resolved inputs/artifacts. Remote submission handles authentication for its backend, while local submission is synchronous and does not require remote authentication. The standalone MAT v5 API uses request/result v2 schemas; see [Headless CLI](docs/headless-cli.md) for the validate→submit contract and examples.

## PIANO Hub integration

Use `bin/pseudoct` with `--format jsonl` as the PIANO Hub integration boundary. Do not invoke the MATLAB GUI directly or reimplement pseudoCT orchestration in PIANO. The intended flow is:

1. PIANO collects the profile, inputs, and processing options.
2. PIANO invokes `validate` before enabling submission.
3. For remote profiles, PIANO obtains credentials through its own login dialog.
4. The backend securely creates the CLI-supported single-use credential handoff.
5. PIANO runs the CLI with `--format jsonl`.
6. PIANO parses progress and result records.
7. PIANO presents subject, stage, status, scheduler job IDs, and errors.
8. PIANO distinguishes accepted submissions from verified scientific completion.

The PIANO backend credential-handoff adapter and end-to-end integration are **not yet implemented or verified**. The [Headless CLI and API reference](docs/headless-cli.md) is the developer reference for the contracts.

## Known limitations

Local Current console progress now uses a ten-stage model (nine for NIfTI-only output; heartbeats are `INFO` rows naming the active operation; `WAIT` is MLSC/Launchpad only; see the [stage model](docs/headless-cli.md#public-stage-model)). On 2026-11-03, a real scientific Local Current CLI run completed one subject (1 succeeded, 0 failed; CLI exit code 0, recorded as `PSEUDOCT_EXIT_CODE=0`) and presented `[1/10]` through `[10/10]` once each on entry. This real run—not offline replay—is the basis for the presentation claim; offline replay of recorded formatter inputs remains a separate supporting check. See [Local Current logging verification](docs/headless-cli.md#local-current-logging-verification) for the run evidence and limits. Earlier real MLSC Current runs (2026-11-01/02) and Launchpad Legacy run (2026-11-02) predate the finalized logging contract and used an eight-stage presentation; they establish scientific execution only, not acceptance of the new presentation.

## Development and distribution boundary

The agreed package architecture has one interpreted MATLAB orchestration layer shared by the GUI and headless CLI, one shared compiled current-science payload for local-current and MLSC-current, and an isolated immutable historical payload. Its package-root layout is exactly:

The source-only QC colormap resolver correction points to `src/qc/`; it was not rebuilt into the existing `compiled/current/` artifact, which remains the recorded T032 payload.

- `bin/`
- `orchestration/`
- `compiled/legacy-v2.0.0/`
- `compiled/current/`
- `external/`
- `manifests/`
- `README.md`

This is the distribution target, distinct from the development checkout. The checkout keeps API, CLI, GUI, orchestration, backend, configuration, I/O, QC, and scientific build-source ownership under `src/`; build/install/maintenance tools are in `scripts/`, and tests/manual tools are in `tests/`. `run_pseudo_CT.m` is a thin public dispatcher. Scientific source under `src/science/` is compiler input, not an interpreted current-science fallback; local-current and MLSC-current execute the identical `compiled/current/` payload. The current payload was rebuilt after the shared-orchestration changes with MATLAB R2010b/Compiler 4.14; its build/resource manifests are paired with the payload, and this cleanup does not rebuild it. SSH2 is at `external/ssh2_v2_m1_r5/`, the source tree invoked by MLSC/Launchpad transport; its identity/hash is unchanged. DICOM input conversion is a separate interpreted orchestration need: the existing lifecycle calls the staged `external/dicom2nifti-1.2.5/` `dcm2nii` facade before backend processing. Only DICOM conversion requires SPM8 r6313 at runtime. Setup initially adds the three `src/science/overrides/` files first, preserving the historical path order; during DICOM conversion the pinned converter API adds configured SPM8 at path-begin, so SPM8 `spm_dicom_convert` remains effective. `correct_aliasing` v0.4.0, selected SPM sources, and the overrides remain pinned build inputs; compiled current execution neither requires nor adds interpreted `correct_aliasing` or science source paths. The file contents of the unused root smoothing candidate and legacy override directory were removed after caller/path verification; empty directory shells may remain in this shared development checkout. Superseded root build-output contents were removed; the canonical `compiled/current/` and historical `compiled/legacy-v2.0.0/` payloads remain.

`Batch_atlas` is a compiled-science runtime resource consumed by the current payload; the legacy payload keeps its distinct legacy `Batch_atlas/`. FreeSurfer (`mri_normalize`) and MATLAB/MCR, MATLAB Java, Slurm/PBS, shells, and other site tools are external system/runtime requirements, not vendored processing sources. The repository's local staged copies and hashes do not grant redistribution rights: unresolved provenance, complete notices, compatibility, and license questions remain no-public-packaging gates. See [Installation and requirements](docs/installation.md) and [`dependencies.lock.json`](dependencies.lock.json) for source evidence, exact invocation boundaries, and current artifact hashes.
