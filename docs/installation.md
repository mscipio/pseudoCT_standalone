# Installation and requirements

This page owns installation, MATLAB and MATLAB Runtime requirements, external
dependencies, the supported profiles and the build entry point. CLI and API
usage is in [Headless API and CLI](headless-cli.md); packaging, runtime identity
and layout are in [Release catalog and layout](releases.md); method and evidence
are in [Scientific notes](scientific-notes.md). Researcher workflow and QC are in
the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/).

## Martinos deployment

Use the centrally provisioned installation at
`/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/`. Add its installation root to
the MATLAB path and launch the window:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
run_pseudo_CT
```

Keep MATLAB open while a request is running and, for MLSC, until monitoring and
local finalization complete. See [Validate and submit](headless-cli.md#validate-and-submit)
for the Validate and Submit gate.

## External installation

Install the standalone distribution for which you have been given access, add its
installation root to MATLAB's path and run `run_pseudo_CT`. The standalone code is
not a self-contained scientific environment: it needs site-appropriate processing
resources. Do not invent fallback resource paths. When an installation needs
different paths, configure them in the selected profile under `src/config/profiles/`.

### MATLAB and MATLAB Runtime requirements

- **Source checkout (MATLAB interpreter):** R2010b-compatible MATLAB, the
  supported minimum for this source (MATLAB 7.11).
- **Installed distribution (MATLAB Runtime):** each installed release runs on its
  own MATLAB Runtime (MCR), not on the interpreter. The default release, R2010b,
  was built with MATLAB 7.11 (build provenance) and runs on MATLAB Runtime **7.14**.
  The other labels (R2014a through R2026a) and their MCR versions are listed in
  [Supported exact release labels](releases.md#supported-exact-release-labels),
  which mirrors `config/releases.json`.
- The MATLAB Runtime root is the catalog location `/usr/pubsw/common/matlab/<D>` of the
  selected release, where `<D>` is the first two dotted components of its `matlab_version`
  (for example `9.6` for `9.6.0.1072779`); `--mcr-root DIR` selects another installation. No environment
  variable or folder picker is needed, and identity is always checked against the catalog.
  See [Release selection](releases.md#selecting-a-release).

### Dependencies

The runtime depends on the following resources and services, as applicable to the
selected profile and input:

- SPM8 and the pseudoCT atlas images and batch templates.
- The DICOM-to-NIfTI converter for DICOM MPRAGE inputs.
- The configured aliasing and recentering tool, when those operations are enabled.
- FreeSurfer normalization tools and their site environment.
- For MLSC profiles: access to the configured shared filesystem, the supported
  cluster services and a valid MLSC account.
- MATLAB/Java and the compatible compiled runtime used by the installed shared
  compiled pipeline.

A development checkout may contain dependency copies. Their presence and recorded
hashes do not establish provenance, compatibility or redistribution rights; see
[`dependencies.lock.json`](../dependencies.lock.json) and the
[publication status](releases.md#publication) in the release documentation.

## Supported profiles

Only these four canonical profile keys are supported by the selector, the CLI and
the API.

| Canonical profile | Execution | Reference policy | Output policy |
|---|---|---|---|
| `local` | Local MATLAB | MPRAGE plus UMAP | NIfTI and DICOM |
| `mlsc` | MLSC (Slurm) | MPRAGE plus UMAP | NIfTI and DICOM |
| `local-mprage-only` | Local MATLAB | MPRAGE only | NIfTI only |
| `mlsc-mprage-only` | MLSC (Slurm) | MPRAGE only | NIfTI only |

The MPRAGE-only profiles do not require a UMAP and do not create DICOM output.
`local` and `mlsc` run the same shared compiled pipeline; the profile chooses the
execution location and the input/output policy, not a different algorithm. Missing
or invalid MLSC artifact requirements fail closed.

Profile defaults (source of truth: `src/config/profiles/*.m` and
`src/config/pseudo_CT_profile_registry.m`):

| Setting | Default |
|---|---|
| Nose/back aliasing correction | On (`aliasing_default = 1`); override with `--correct-aliasing`. |
| Recentering before normalization | `Yes`; override with `--recenter-before-normalization`. |
| Zero background | `No`. |
| Bone-segmentation cleanup | On. |
| Cleanup of intermediates after success | On (`cleanup_on_success = true`). |
| PCA implementations, in order | `callable_pca`, then `repo_legacy`. |
| MLSC Slurm request | 1 node, 1 task, 4 CPUs, 8 GB memory, 02:00:00 time limit. |

Local profiles run on this computer. MLSC profiles submit to Slurm after a
successful validation of the same inputs (see [Validate and submit](headless-cli.md#validate-and-submit))
and require a valid account, configured host and shared filesystem. To check the
account without submitting, use `bin/pseudoct run validate --check-account` with an
MLSC profile (MLSC only; it authenticates and never calls `sbatch`; see
[Options](headless-cli.md#options-run-validaterun)). MLSC submit is
implemented and offline-tested, but it has **not** been independently verified
against a live scheduler; see [Verification status](releases.md#verification-status).

## Interfaces and files

The supported entry points are the MATLAB window and scripting entry point
`run_pseudo_CT`, the MATLAB headless API `pseudo_CT_headless` and the terminal CLI
`bin/pseudoct`. See [Headless API and CLI](headless-cli.md) for schemas, options,
logs and exit codes. Console stage rows, including SKIPPED stages, are described in
[Output, logs and progress](headless-cli.md#output-logs-and-progress).

Standard outputs are written under `<subject>/MR_PET/`; DICOM output is written under
`<subject>/MR/pseudo_muMAP/`. MPRAGE-only output is NIfTI-only. Inspect the QC image
and the final attenuation map before use.

## Build and packaging

`scripts/build_application.m` is the single build entry point. The MATLAB release is
an explicit argument with no default, and the procedure contains no supported-release
table. The executing MATLAB must report that same release. Run it from MATLAB, with
`<release>` set to the release you intend to build (for example `R2010b` for MATLAB 7.11):

```matlab
cd('<repo-root>')
addpath('scripts')

% Dry run (default). Checks the MATLAB release and Compiler, the source
% revision, the dependency roots and lock file, and lists the application
% file set. It never calls mcc and writes nothing.
build_application('<release>', 'OutputRoot', '<output-root>')

% Build (explicit only). Requires a clean git tree and the MATLAB Runtime root.
build_application('<release>', 'Mode', 'build', ...
    'OutputRoot', '<output-root>', 'McrRoot', '<mcr-root>')

% Recompute SHA-256 and check the manifest against the inventory.
verify_application_package('<output-root>/<release>')
```

`<output-root>` must be outside `src/`, `external/` and `compiled/`. A build refuses a
dirty git tree by design; commit or clean the tree before building. The build compiles
exactly two targets: the job manager `pseudoct_job_manager` and the science pipeline
`pseudoct_pipeline`. Each is written to a build-private folder (`standalone/` and `payload/`
under the build output). The installed layout is flat under `runtimes/<LABEL>/`
([Distribution layout](releases.md#distribution-layout)). Only the job-manager target compiles
the SSH2 closure and the dicom2nifti `VERSION` file.

Distribution assembly is `scripts/release_application.py` (see
[Release catalog and layout](releases.md)). It runs `build_application` once per selected
release and writes `pseudoct-<version>/`. The package contains no `src/` or GUI
executable. Its only `external/` content is the Ganymed JAR and the two SSH2 licence notices
under `external/ssh2_v2_m1_r5/`; no loose SSH2 `.m` files are installed. Loading the JAR and
wrappers from the compiled job manager is not yet verified until an approved RC6 build.
`--verify <dir>` checks the package. Python bytecode (`*.pyc`, `*.pyo`) in
`frontend/` is excluded from the frontend inventory, so a checkout that has it still
passes.

**Verification status.** The build procedure has not been run as a real build for any
release in this audit. The executables under `compiled/` predate the v3.2.0 renames, and
no package has been assembled or verified for this version. See
[Verification status](releases.md#verification-status).
