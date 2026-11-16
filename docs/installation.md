# Installation

This page covers installing and starting pseudoCT, its requirements and the supported
profiles. The command-line reference is [Headless API and CLI](headless-cli.md), and launching pseudoCT from another application is in the [Third-party integration guide](THIRD_PARTY_INTEGRATION.md). The
step-by-step workflow, outputs and QC are in the
[PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/). The build,
packaging and dependency details for developers are at the end of this page.

## Martinos deployment

Use the centrally installed application at
`/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/`. Add its installation root to the
MATLAB path and open the window:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
run_pseudo_CT
```

Keep MATLAB open while a request is running and, for MLSC, until monitoring and local
finalization complete. The run steps are in the README and the User Guide.

## Requirements

- **Installed distribution (users):** each installed release runs on its own MATLAB
  Runtime (MCR). The default release, R2010b, runs on MATLAB Runtime **7.14**. The other
  releases (R2014a to R2026a) and their runtime versions are listed in
  [Supported exact release labels](releases.md#supported-exact-release-labels).
- **Platform:** Linux x86_64 with glibc 2.17 or newer (for example RHEL/CentOS 7 or
  Rocky Linux 8), `bash` and the standard GNU command-line tools.
- **Python:** nothing to install. The distribution carries its own private Python runtime
  under `python/`, which the launcher and the window use for their helper steps. A system
  or Conda Python and `PYTHONPATH`/`PYTHONHOME` settings are ignored. See
  [Distribution layout](releases.md#distribution-layout).
- **Source checkout (developers):** R2010b-compatible MATLAB, the minimum for this source
  (MATLAB 7.11). A source checkout is for development only. Its launcher uses
  `PSEUDOCT_PYTHON`, else `python3` (3.6 or newer) from `PATH`.
- **Site resources:** the application needs the resources configured for the installation.
  Do not substitute fallback resource paths. Each profile's paths come from its profile file
  under `src/config/profiles/`.
- **MLSC profiles:** access to the configured shared filesystem, the cluster services and
  a valid MLSC account.

The MATLAB Runtime root is the catalog location `/usr/pubsw/common/matlab/<D>` of the
selected release, where `<D>` is the first two dotted components of its `matlab_version`
(for example `9.6` for `9.6.0.1072779`). `--mcr-root DIR` selects another installation.
The runtime identity is always checked against the release catalog. See
[Release selection](releases.md#selecting-a-release).

## Supported profiles

Only these four canonical profile keys are supported by the window, the command line and
the MATLAB API.

| Canonical profile | Execution | Reference | Output |
|---|---|---|---|
| `local` | Local MATLAB | MPRAGE plus UMAP | NIfTI and DICOM |
| `mlsc` | MLSC (Slurm) | MPRAGE plus UMAP | NIfTI and DICOM |
| `local-mprage-only` | Local MATLAB | MPRAGE only | NIfTI only |
| `mlsc-mprage-only` | MLSC (Slurm) | MPRAGE only | NIfTI only |

The MPRAGE-only profiles do not require a UMAP and create no DICOM output. `local` and
`mlsc` run the same compiled pipeline. The profile chooses the execution location and the
input and output policy, not a different algorithm.

Profile defaults: nose and back aliasing correction on, recentering before normalization
on, and cleanup of intermediate files after success on. The command line can override each
of them with the options listed in the [CLI reference](headless-cli.md#options-run-validaterun).

MLSC profiles submit to Slurm after a successful validation of the same inputs, and they
need a valid account, the configured host and the shared filesystem. MLSC submission is
implemented and tested offline. It has **not** been independently verified against a live
scheduler (see [Verification status](releases.md#verification-status)).

## Developer notes

The sections below are for developers and packagers. They are not needed to run the
application.

### Dependencies

The runtime depends on these resources and services, as applicable to the selected profile
and input:

- SPM8, and the pseudoCT atlas images and batch templates.
- The DICOM-to-NIfTI converter, for DICOM MPRAGE inputs.
- The configured aliasing and recentering tool, when those operations are enabled.
- FreeSurfer normalization tools and their site environment.
- For MLSC profiles: the configured shared filesystem, the cluster services and a valid
  MLSC account.
- MATLAB/Java and the compatible compiled runtime used by the installed shared pipeline.

A development checkout may contain dependency copies. Their presence and recorded hashes
do not establish provenance, compatibility or redistribution rights. See
[`dependencies.lock.json`](../dependencies.lock.json) and the
[publication status](releases.md#publication).

### Build and packaging

`scripts/build_application.m` is the single build entry point. The MATLAB release is an
explicit argument with no default. The executing MATLAB must report that same release. Run
it from MATLAB, with `<release>` set to the release you intend to build (for example
`R2010b` for MATLAB 7.11):

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

`<output-root>` must be outside `src/`, `external/` and `compiled/`. A build refuses a dirty
git tree. The build compiles two targets: the job manager `pseudoct_job_manager` and the
science pipeline `pseudoct_pipeline`. The installed layout is flat under
`runtimes/<LABEL>/` ([Distribution layout](releases.md#distribution-layout)). Only the
job-manager target compiles the SSH2 closure and the dicom2nifti `VERSION` file.

`scripts/release_application.py` assembles `pseudoct-<version>/` from one build per selected
release. The package contains no `src/` tree and no GUI executable. Its only `external/`
content is the Ganymed JAR and the two SSH2 licence notices under `external/ssh2_v2_m1_r5/`.
`--verify <dir>` checks an assembled package. Python bytecode (`*.pyc`, `*.pyo`) in
`frontend/` is excluded from the frontend inventory.

### Verification status

The build procedure has not been run as a real build for any release in the current audit,
and no package has been assembled or verified for this version. The executables under
`compiled/` predate the v3.2.0 renames. See [Verification status](releases.md#verification-status).
