# pseudoCT standalone

Atlas-based pseudoCT generation for PET/MR attenuation correction from a
T1-weighted MPRAGE, following the SPM8-based method of Izquierdo-Garcia et al.
(*Journal of Nuclear Medicine*, 2014;55(11):1825–1830).

Martinos users should use the deployed application and the
[PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/), which
covers the workflow, the outputs and quality control in detail. This README is the
short overview.

## Documentation

| Topic | Document |
|---|---|
| Running the application, outputs, QC and troubleshooting | [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/) |
| Installation, requirements and profiles | [Installation](docs/installation.md) |
| Command-line reference: options, output files, exit codes | [Headless API and CLI](docs/headless-cli.md) |
| Launching pseudoCT from another application (subprocess, JSONL progress, outputs) | [Third-party integration guide](docs/THIRD_PARTY_INTEGRATION.md) |
| Packaging, runtime identity and layout (developers) | [Release catalog and layout](docs/releases.md) |
| Method and interpretation limits | [Scientific notes](docs/scientific-notes.md) |
| Offline checks (developers) | [Tests](tests/README.md) |
| Version history | [CHANGELOG](CHANGELOG.md) |

## Installation and starting the application

Martinos users run the centrally installed application. Add its installation root
to the MATLAB path and open the window:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
run_pseudo_CT
```

With no arguments, `run_pseudo_CT` opens a profile selector, then the input window.

The installed application runs the compiled pipeline of the selected release through
its MATLAB Runtime. The default release, R2010b, uses MATLAB Runtime 7.14. Requirements
are in [Installation](docs/installation.md).

A source checkout is for development only. If the window reports that it is a source
checkout, start the installed application instead.

## Choosing a profile

| Profile | What it does | Inputs | Output | Needs a cluster account |
|---|---|---|---|---|
| `local` | Runs the processing on this computer | MPRAGE and UMAP | NIfTI attenuation map, QC image, version record and DICOM | No |
| `local-mprage-only` | Runs the processing on this computer, without a UMAP | MPRAGE only | NIfTI attenuation map, QC image and version record (no DICOM) | No |
| `mlsc` | Submits the processing to the MLSC cluster (Slurm), monitors it and finalizes the outputs locally | MPRAGE and UMAP | Same as `local` | Yes: you log in with your MLSC username and password |
| `mlsc-mprage-only` | Same as `mlsc`, without a UMAP | MPRAGE only | Same as `local-mprage-only` | Yes |

The local and MLSC profiles run the same compiled pipeline. The profile chooses where
it runs and which outputs are written, not a different algorithm.

## Required inputs

- **MPRAGE** (DICOM or NIfTI): required for every profile. Select one file per subject.
- **UMAP reference**: required for `local` and `mlsc`. The window looks for it beside
  the MPRAGE: it looks in the subject's `MR` folder for a sub-folder whose name
  contains `umap`, `ute`, `mu_map` or `mumap`, and uses the first file in that folder
  whose name contains `0001`. If none is found, the UMAP field says so and you select
  the UMAP yourself. On the command line, a standard profile also tries this discovery
  when `--umap` is omitted.
- The MPRAGE-only profiles do not accept a UMAP.

## Running from the GUI

The input window has a single action, **Run**.

1. Choose a profile and select the MPRAGE. For standard profiles, check the UMAP field.
2. Check the processing options. The defaults come from the profile.
3. Click **Run**. Run validates the profile, the inputs, the outputs and the
   dependencies. Validation does not log in, contact the cluster or process data.
   - For a local profile, Run submits the request as soon as validation passes.
   - For an MLSC profile, Run validates first and asks for the login only after
     validation passes. The login dialog asks for your username, your password and an
     optional group account. Nothing is submitted if validation fails or the login is
     cancelled.
4. The window stays open, but MATLAB is busy. Until the run finishes, the inputs, the
   options and **Close** are disabled, and the window close button is ignored. Do not
   close MATLAB during an MLSC run.
5. When the run finishes, a message box reports the result. A failure shows a warning
   with the error code and message. The status line at the bottom of the window also
   shows the outcome.

## Running from the command line

`bin/pseudoct` is the terminal entry point. `run` validates a request and then submits
it in one invocation. `validate` is an optional check that submits nothing; `run` does not
need a prior `validate`.

```sh
bin/pseudoct validate --profile local --mprage MPRAGE.dcm --umap UMAP.dcm
bin/pseudoct run      --profile local --mprage MPRAGE.dcm --umap UMAP.dcm

bin/pseudoct run --profile local-mprage-only --mprage MPRAGE.dcm --format jsonl

bin/pseudoct run --profile mlsc --mprage MPRAGE.dcm --umap UMAP.dcm \
  --group-account ACCOUNT --result-file result.json

bin/pseudoct validate --profile mlsc --mprage MPRAGE.dcm --umap UMAP.dcm \
  --check-account
```

- `--format text` (the default) prints readable progress to the terminal.
- `--format jsonl` prints one JSON record per line, for scripts and automation.
- `--result-file PATH` also writes the final result record to `PATH`, in either format.
- `--group-account ACCOUNT` selects the MLSC account. If it is omitted, the first
  discovered account is used.
- `--check-account` (MLSC, `validate` only) logs in, selects the account and stops.
  It never submits.
- Passwords are never accepted on the command line. For MLSC, the command line asks for
  the username and password at the terminal.
- `bin/pseudoct --help` prints the usage text. All options and exit codes are listed in
  the [CLI reference](docs/headless-cli.md#options-validate-run).

## What happens after Run

- **Validation** checks the request and reports `ready` or the first problem. It does
  not process data and, for local profiles, does not log in. On the command line, only
  `--check-account` (MLSC) logs in during validation.
- **Local processing** runs in the current session. Progress is shown stage by stage
  (stages 1 to 10). Stages that do not apply to the profile are shown as `SKIPPED`
  with a reason.
- **MLSC processing** is submitted to Slurm after login. The launcher monitors the job
  and reports its state and elapsed time. When the job ends, the outputs are copied
  back and checked, and then finalized locally.
- A submitted or scheduled job is not a result. A run is complete only when the result
  reports a completed, verified run (exit code `0`). A run that cannot be verified exits
  with `68`.

## Where outputs and logs are saved

For each subject, the outputs are written in the subject folder:

- `<subject>/MR_PET/`: the NIfTI attenuation map `att_map.nii`, the QC image
  `Fusion_MR_Pseudo_CT_validation.tiff` and the version record `Pseudo_CT_AC_Version.txt`.
- `<subject>/MR/pseudo_muMAP/`: DICOM output, for `local` and `mlsc` only.
- `<subject>/MR_PET/pseudoct-run-<UTC>-<invocation>.jsonl` and
  `<subject>/MR_PET/pseudoct-run-<UTC>-<invocation>.log`: the run's structured record and
  its detailed log.

The full list of files, what each one contains, and what the validation-only record
contains are in the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/#outputs).
Passwords and login details are never written to either file.

## Progress, warnings, errors and completion

- **Text output** shows one row per stage and per event. Stage rows carry the stage
  number (`[n/10]`) and its status (`ACTIVE`, `DONE`, `SKIPPED` or `ERROR`), and
  rows for multi-subject runs carry the subject number. `WARN` and `ERROR` rows report problems during the run. A `still running`
  line shows that a long step is progressing.
- **JSONL output** (`--format jsonl`) writes one progress record per line, then the final
  result record (outcome, exit code and, for MLSC, the job IDs). Run-log paths are printed in
  the text summary, not in the JSON result. Each run's structured record is the file
  `pseudoct-run-<UTC>-<invocation>.jsonl` in the subject's `MR_PET` folder. The
  [third-party integration guide](docs/THIRD_PARTY_INTEGRATION.md) describes the fields.
- The final summary states the outcome, the submission and dispatch status, the
  scientific completion status and, for MLSC, the job IDs.
- A run is complete when the summary reports scientific completion with exit code `0`.
  Check the QC image before using any map.

## Troubleshooting

| Symptom | What to do |
|---|---|
| Authentication failed (`AUTHENTICATION_FAILED`, exit `66`) | In the GUI, the login dialog reopens by itself after the rejection; enter the password again, or cancel to stop without submitting. On the command line, you are asked for the password again (and for the account if you did not give `--group-account`). Enter the password again. An empty input cancels the retry. Retries are unlimited by default. To limit them, set `PSEUDOCT_AUTH_RETRY_LIMIT=N`: `N` retries after the first failure, and `0` for no retry. The run then stops with exit `66`. The variable applies only to the terminal prompt. |
| Invalid group account (`INVALID_GROUP_ACCOUNT`) | Enter a valid account. On the command line, if you gave `--group-account`, the run stops with exit `66`; run it again with a valid account. |
| Host-key problem (`HOST_KEY_UNAVAILABLE`) | Not retried. The run stops with exit `66`. Check the host-key input and contact the application maintainer. |
| Source checkout message | You are running from a source checkout, which is for development only. Use the installed application. |
| "installation is incomplete" or `runtimes/` missing | The installation is damaged. Reinstall the distribution. |
| MATLAB Runtime not found or identity mismatch | The runtime root is taken from the release catalog. Use `--mcr-root DIR` on the command line only if the runtime is installed elsewhere. Do not substitute another runtime. |
| Input not found, or reference missing | Check the MPRAGE and UMAP paths. Choose the MPRAGE-only profile if no UMAP is available. |
| Run is disabled | The inputs cannot be read. Check the selected files. |
| Exit `68` after a submitted job | The outcome is unverified. Keep the run log and the JSONL file. If the job must stop, cancel it by hand with `scancel <job id>`. |
| MLSC still running | Leave MATLAB open. Do not submit a duplicate job. |

Further details are in the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/#troubleshooting).

## Live progress in the MATLAB Command Window

During a Run, progress text is sent to the MATLAB Command Window. Whether the lines
appear live while the run is in progress has not yet been confirmed on the installed
MATLAB. The run log and the JSONL file are the complete record in either case.

## Requirements and evidence

The standalone source supports MATLAB R2010b. The compiled distribution runs on the
MATLAB Runtime of each release; the default release, R2010b, runs on MATLAB Runtime 7.14.
Dependency and external-service requirements are environment-specific. See
[Installation](docs/installation.md) and [`dependencies.lock.json`](dependencies.lock.json).

Existing reference comparisons are limited to particular datasets, software artifacts and
environments. They do not establish universal equivalence, clinical correctness or accuracy
superiority. Inspect the QC image and the final map for each use. See
[Scientific notes](docs/scientific-notes.md) and the
[release verification status](docs/releases.md#verification-status).
