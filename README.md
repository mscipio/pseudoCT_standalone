# pseudoCT standalone

Atlas-based pseudoCT generation for PET/MR attenuation correction from a
T1-weighted MPRAGE, following the SPM8-based method of Izquierdo-Garcia et al.
(*Journal of Nuclear Medicine*, 2014;55(11):1825–1830).

Martinos users should use the [deployed application](#quick-start-martinos) and the
[PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/).

## Documentation

| Topic | Document |
|---|---|
| Researcher workflow, subject layout and QC | [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/) |
| Installation, MATLAB and MATLAB Runtime requirements, profiles, build | [Installation](docs/installation.md) |
| CLI, headless API, validate and submit, logs, exit codes | [Headless API and CLI](docs/headless-cli.md) |
| Packaging, runtime identity, layout, verification status | [Release catalog and layout](docs/releases.md) |
| Method, bounded evidence and interpretation limits | [Scientific notes](docs/scientific-notes.md) |
| Offline checks | [Tests](tests/README.md) |
| Version history | [CHANGELOG](CHANGELOG.md) |

## Quick start (Martinos)

Add the deployed installation root to the MATLAB path and launch the window:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
run_pseudo_CT
```

Validate the inputs first; Submit becomes available only after a successful
Validate of the same inputs and options. Keep MATLAB open while a request runs,
and, for MLSC, until monitoring and output finalization finish. Inspect the QC
image before using an output. See [Validate and submit](docs/headless-cli.md#validate-and-submit).

The terminal CLI works the same way:

```sh
bin/pseudoct run validate --profile local --mprage MPRAGE.dcm --umap UMAP.dcm
bin/pseudoct run run --profile local --mprage MPRAGE.dcm --umap UMAP.dcm
```

## Supported profiles

Only these four canonical profile keys are supported. Defaults and requirements are in
[Installation](docs/installation.md#supported-profiles).

| Profile | Execution | Inputs | Outputs |
|---|---|---|---|
| `local` | Local MATLAB | MPRAGE and UMAP reference | NIfTI, QC, version record and DICOM |
| `mlsc` | MLSC (Slurm) | MPRAGE and UMAP reference | NIfTI, QC, version record and DICOM |
| `local-mprage-only` | Local MATLAB | MPRAGE only | NIfTI, QC and version record |
| `mlsc-mprage-only` | MLSC (Slurm) | MPRAGE only | NIfTI, QC and version record |

Local and MLSC profiles run the same scientific payload. The execution environment and
the input/output policy differ.

## Interfaces

| Entry point | Use |
|---|---|
| MATLAB window and scripting: `run_pseudo_CT` | Profile and file selection in a window, or parameterized runs. With no arguments it opens the window. |
| MATLAB headless API: `pseudo_CT_headless(request_path, result_path)` | Versioned MAT v5 request and result, with separate validation and submission. |
| Terminal CLI: `bin/pseudoct` | Shell and application integration: `run validate`, `run run`, text or JSONL output and stable exit codes. |

The window and the CLI both go through the launcher. Scientific computation runs in the
compiled `pseudoct_pipeline`; the compiled `pseudoct_job_manager` handles profile resolution, requests, input preparation, submission and finalization.
The package layout and runtime selection are in [Release catalog and layout](docs/releases.md).

## Inputs and outputs

Provide a DICOM or NIfTI MPRAGE. Standard profiles also require a matched UMAP; an
omitted reference may be discovered from the subject layout. MPRAGE-only profiles do not
accept a UMAP. Standard output is written under `<subject>/MR_PET/`, with DICOM output
under `<subject>/MR/pseudo_muMAP/`. MPRAGE-only output is NIfTI-only. Logs, progress,
temporary files and cancellation are described in
[Output, logs and progress](docs/headless-cli.md#output-logs-and-progress) and
[Cancellation and interruption](docs/headless-cli.md#cancellation-and-interruption).

## Requirements and evidence

The standalone source supports MATLAB R2010b. The compiled distribution runs on the
MATLAB Runtime of each release; the default release, R2010b, runs on MATLAB Runtime 7.14.
Dependency and external-service requirements are environment-specific. A source checkout
or a local dependency copy does not itself establish a supported installation or
redistribution rights. See [Installation](docs/installation.md) and
[`dependencies.lock.json`](dependencies.lock.json).

Existing reference comparisons are limited to particular datasets, software artifacts and
environments. They do not establish universal equivalence, clinical correctness or accuracy
superiority. Preserve and inspect the QC image and final map for each use. See
[Scientific notes](docs/scientific-notes.md) and the [release verification status](docs/releases.md#verification-status).
