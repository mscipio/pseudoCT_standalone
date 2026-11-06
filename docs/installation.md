# Installation and requirements

## Martinos deployment

Use the centrally provisioned installation at
`/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/`. Add its installation
root to the MATLAB path and run the GUI entry point:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
run_pseudo_CT
```

Keep MATLAB open while a run is active and until MLSC monitoring and local
finalization complete. The [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/)
covers subject layout, input selection, workflow, outputs, and QC.

## External installation

Install the standalone distribution for which you have been given access, then
add its installation root to MATLAB's path and run `run_pseudo_CT`. The
standalone code is not a self-contained scientific environment. It requires
MATLAB R2010b-compatible operation and site-appropriate processing resources;
do not invent fallback resource paths. Configure supported resources in the
selected profile under `src/config/profiles/` when an external installation
requires different paths.

The runtime depends on the following resources and services, as applicable to
the selected profile and input:

- SPM8 and the pseudoCT atlas images/batch templates.
- The DICOM-to-NIfTI converter for DICOM MPRAGE inputs.
- The configured aliasing/recentering tool when those operations are enabled.
- FreeSurfer normalization tools and their site environment.
- For MLSC profiles, access to the configured shared filesystem, supported
  cluster services, and a valid MLSC account. MATLAB remains open during
  monitoring and output verification.
- MATLAB/Java and the compatible compiled runtime used by the installed
  scientific payload.

Some dependency copies may be present in a development checkout. Their
presence and recorded hashes do not establish complete provenance,
compatibility, or redistribution rights. Preserve the supplied licenses and
notices; public packaging remains subject to dependency-specific licensing and
redistribution review. See [`dependencies.lock.json`](../dependencies.lock.json)
for the recorded dependency boundary and integrity evidence.

## Supported profiles

| Canonical profile | Execution | Reference policy | Output policy |
|---|---|---|---|
| `local` | Local MATLAB | MPRAGE plus UMAP | NIfTI and DICOM |
| `mlsc` | MLSC | MPRAGE plus UMAP | NIfTI and DICOM |
| `local-mprage-only` | Local MATLAB | MPRAGE only | NIfTI only |
| `mlsc-mprage-only` | MLSC | MPRAGE only | NIfTI only |

The selector and APIs expose only these four profiles. The MPRAGE-only choices
do not require a UMAP and do not create DICOM output. Missing or invalid MLSC
artifact requirements fail closed; no alternate science implementation is
selected.

## Interfaces and files

The supported entry points are the MATLAB GUI/scripting dispatcher
`run_pseudo_CT`, the MATLAB headless MAT v5 API `pseudo_CT_headless`, and the
terminal CLI `bin/pseudoct`. See [Headless CLI](headless-cli.md) for API
schemas, CLI options, credential handling, and exit semantics.

MPRAGE and standard-profile UMAP inputs may be DICOM or NIfTI where supported
by the selected workflow. Standard outputs are written under
`<subject>/MR_PET/`; DICOM output is written under
`<subject>/MR/pseudo_muMAP/`. MPRAGE-only output is NIfTI-only. Inspect the QC
image and final attenuation map before use.

For the scientific method, historical comparisons, and evidence limitations,
see [Scientific notes](scientific-notes.md). No new scientific validation or
deployment is implied by these installation instructions.

## Build and packaging

`scripts/build_application.m` is the single build entry point. The MATLAB
release is an explicit argument with no default, and the procedure contains no
supported-release table. The executing MATLAB must report that same release.
Run it from MATLAB with `<release>` set to the release you intend to build,
for example `R2010b` for MATLAB 7.11:

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

`<output-root>` must be outside `src/`, `external/` and `compiled/`. A package
is written to `<output-root>/<release>/` and is never overwritten. The package
mirrors an install root so the launchers resolve their siblings by relative
path: `bin/` (`pseudoct`, `pseudoct-headless`, `run_mlsc_current_payload.sh`),
`src/` (interpreted runtime source that the CLI and headless bootstrap need),
`app/` (the `run_pseudo_CT` GUI/CLI build), `payload/` (`mlsc_current_payload`),
`resources/` (atlas and template files), `application_manifest.txt` (release,
MATLAB and Compiler identity, source commit, lock hash, and inputs) and
`SHA256SUMS`. An independent check is
`cd <output-root>/<release> && sha256sum -c SHA256SUMS`.

Compile support is unverified. The procedure has not been run as a real build
for any release, and the compiled application, runtime behavior, launchers and
deployment are unverified until a real build is run and tested. Dependency
tree digests are checked by `tests/test_dependency_lock.py`, not by the build
preflight.
