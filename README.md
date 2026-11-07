# pseudoCT standalone

Atlas-based pseudoCT generation for PET/MR attenuation correction from a
T1-weighted MPRAGE, following the SPM8-based method of Izquierdo-Garcia et al.
(*Journal of Nuclear Medicine*, 2014;55(11):1825–1830).

Martinos users should use the [deployed application](#quick-start-martinos) and
the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/).
External installation and dependency requirements are in
[Installation](docs/installation.md); method and bounded evidence are in
[Scientific notes](docs/scientific-notes.md).

## Quick start (Martinos)

Add the deployed installation root to the MATLAB path and launch the selector:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
run_pseudo_CT
```

Keep MATLAB open during local processing and, for MLSC, until monitoring and
output finalization finish. Inspect the generated QC before using an output.

## Supported profiles

Only these four canonical profile keys are supported:

| Profile | Execution | Inputs | Outputs |
|---|---|---|---|
| `local` | Local MATLAB | MPRAGE and UMAP reference | NIfTI, QC, version record, and DICOM |
| `mlsc` | MLSC | MPRAGE and UMAP reference | NIfTI, QC, version record, and DICOM |
| `local-mprage-only` | Local MATLAB | MPRAGE only | NIfTI, QC, and version record |
| `mlsc-mprage-only` | MLSC | MPRAGE only | NIfTI, QC, and version record |

The MPRAGE-only profiles omit UMAP selection and DICOM output. Local and MLSC
profiles share the same scientific payload; the execution environment and
input/output policy differ.

## Interfaces

| Entry point | Use |
|---|---|
| MATLAB GUI and scripting: `run_pseudo_CT` | Interactive profile/file selection, or MATLAB-hosted parameterized runs. With no arguments, opens the GUI. |
| MATLAB headless API: `pseudo_CT_headless(request_path, result_path)` | Versioned MAT v5 request/result interface with separate local validation and submission. |
| Terminal CLI: `bin/pseudoct` | Shell and application integration; supports `validate` and `run`, text or JSONL progress, and stable exit codes. |

The CLI launches the headless API through `bin/pseudoct headless`. Its request
and result schemas, credential handoff, JSONL records, and exit codes are
documented in [Headless CLI](docs/headless-cli.md). Use `bin/pseudoct --help`
for the installed command's options.

## Inputs and outputs

Provide a DICOM or NIfTI MPRAGE. Standard profiles also require a matched UMAP;
an omitted reference may be discovered from the subject layout. MPRAGE-only
profiles do not accept a UMAP. Standard output is written under
`<subject>/MR_PET/`, with DICOM output under `<subject>/MR/pseudo_muMAP/`.
MPRAGE-only output is NIfTI-only. See the User Guide for supported layouts,
workflow steps, and QC review.

## Validation and scientific evidence

The standalone source supports MATLAB R2010b. The build/runtime and external
dependency requirements are environment-specific; a source checkout or local
dependency copy does not itself establish a supported installation or
redistribution rights. See [Installation](docs/installation.md) and
[`dependencies.lock.json`](dependencies.lock.json).

Existing reference comparisons are limited to particular datasets, software
artifacts, and environments; they do not establish universal equivalence,
clinical correctness, or accuracy superiority. Preserve and inspect the QC
image and final map for each use. See [Scientific notes](docs/scientific-notes.md)
and the repository's [release history](CHANGELOG.md).
