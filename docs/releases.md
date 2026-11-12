# Release catalog, packaging and runtime identity

This document owns packaging, the MATLAB release catalog, runtime identity and
the layout of the standalone distribution. The machine-readable catalog is
`config/releases.json`; the table below mirrors it, and that JSON file is
authoritative. Installation steps are in [Installation](installation.md); CLI
options are in [Headless API and CLI](headless-cli.md).

## Supported exact release labels

Each `--mcr` value must be one of these exact labels.

| Release label | MATLAB version | MCR version | Architecture | Runtime library |
|---|---|---|---|---|
| R2010b (default) | 7.11 | 7.14 | glnxa64 | `libmwmclmcrrt.so.7.14` |
| R2014a | 8.3 | 8.3 | glnxa64 | `libmwmclmcrrt.so.8.3` |
| R2014b | 8.4 | 8.4 | glnxa64 | `libmwmclmcrrt.so.8.4` |
| R2019a | 9.6.0.1072779 | 9.6 | glnxa64 | `libmwmclmcrrt.so.9.6` |
| R2019b | 9.7.0.1190202 | 9.7 | glnxa64 | `libmwmclmcrrt.so.9.7` |
| R2022a | 9.12.0.2039608 | 9.12 | glnxa64 | `libmwmclmcrrt.so.9.12` |
| R2022b | 9.13.0.2049777 | 9.13 | glnxa64 | `libmwmclmcrrt.so.9.13` |
| R2026a | 26.1.0.3251617 | 26.1 | glnxa64 | `libmwmclmcrrt.so.26.1` |

- The default release is **R2010b**: MATLAB 7.11 is its build provenance, and
  MATLAB Runtime 7.14 is the runtime identity checked at execution.
- **R2010a** and **R2026b** are not in the catalog because they are not installed
  on the inspected workstation. Do not add them without inspecting an installation.
- Identity terms are defined in [Version and identity terminology](#version-and-identity-terminology).

## Selecting a release

- `--mcr <label>` (or `resolve --mcr <label>`) accepts an exact label from the table
  only, for example `--mcr R2019b`. Year-only shorthand such as `2014` is rejected
  because it is ambiguous (2014 maps to both R2014a and R2014b).
- Without `--mcr`, the catalog default (R2010b) is used.
- Unknown or malformed labels fail before any execution. There is no fallback to
  another release. A label whose release is not built into the distribution also fails
  before execution.
- `--list-releases` needs no MATLAB or MCR. In an installed distribution it prints one
  line per installed (complete) release, in catalog order:
  `<label><TAB><mcr_version><TAB><default|->`.

## Build inputs

- The release driver `scripts/release_application.py` takes a required explicit
  `--version`. No `VERSION` file or `git describe` is inferred. The driver's
  examples use the placeholder `--version <VERSION>`; substitute the package
  version chosen by the user. The distribution package number is a user decision;
  this repository does not choose it.
- MATLAB installation roots are explicit build inputs supplied at build time
  (`--matlab-root LABEL=PATH`). They are not stored in `config/releases.json`.
- The default output directory is `<repository>/dist/`, derived from the location of
  the driver, not from the working directory. `--output DIR` overrides it.
- Each release is built by `scripts/build_application.m`, which refuses a dirty git
  tree. Commit or otherwise clean the tree before a real build; this guard is
  intentional and must not be bypassed.
- The intended RC7 release matrix is **R2010b, R2019b, R2022a and R2026a**; select it
  explicitly with `--releases R2010b,R2019b,R2022a,R2026a`. R2014b and R2022b are
  excluded from this release matrix, not removed from the supported catalog. The
  default selection remains R2010b.

## Distribution layout

```
pseudoct-<version>/
  bin/pseudoct                                       the only public launcher (copied)
  run_pseudo_CT.m                                    MATLAB frontend (copied from the repository)
  frontend/                                          MATLAB frontend files (copied verbatim)
  help/index.html, help/style.css                    help documents from docs/help (docs/help/assets/ is never shipped)
  runtimes/<LABEL>/pseudoct_pipeline                   compiled science pipeline (shared by local and MLSC)
  runtimes/<LABEL>/run_pseudoct_pipeline.sh            pipeline runner (copy of scripts/run_pseudoct_pipeline.sh)
  runtimes/<LABEL>/pseudoct_job_manager               compiled job manager (dispatcher)
  external/ssh2_v2_m1_r5/                            Ganymed JAR and two licence notices (no loose SSH2 .m files)
  resources/                                         atlas and template files, and SPM's DICOM dictionary (spm_dicom_dict.mat, copied unchanged)
  manifest.json                                      catalog manifest read by bin/pseudoct (embeds the release catalog)
  SHA256SUMS                                         sorted checksums, includes manifest.json
```

- `frontend/` holds the window, its profile selector, the request bridge and the
  profile table. The credential store and the password dialog (with its tools) are
  shipped from their `src/` originals, which the compiled CLI and the lifecycle also
  use. The driver's `FRONTEND_OWN` and `FRONTEND_FROM_SRC` lists are the complete
  allowlist; nothing else is shipped beside them.
- The inventory skips Python bytecode under `frontend/` (`*.pyc`/`*.pyo`, including in
  `__pycache__/`). Python regenerates it and git ignores it, so it is not frontend
  content. The release check does not depend on whether a checkout has it; any other
  extra file in `frontend/` still fails.
- The distribution contains no `src/`, no tests, no build tools, no logs and no `app/`
  GUI executable. Under `external/` it contains only the three files in the driver's
  `SSH2_FILES`: the Ganymed JAR (`external/ssh2_v2_m1_r5/ssh2_v2_m1_r5/ganymed-ssh2-m1/ganymed-ssh2-m1.jar`),
  the SSH2 `license.txt` and the Ganymed `LICENSE.txt`. No loose SSH2 `.m` files are installed.
  The 19 root SSH2 wrappers are compiled into `pseudoct_job_manager` only, with the JAR as an
  `-a` input; the pipeline does not reach SSH2. Loading the JAR and wrappers from the compiled
  job manager is **not yet verified** and awaits an approved RC6 build. No other `external/` content
  is shipped. `--verify DIR` of the driver refuses anything outside the allowlist.
- The dicom2nifti `VERSION` file (`external/dicom2nifti-1.2.5/VERSION`) is an explicit `-a`
  compile input of `pseudoct_job_manager` only, intended to sit at the CTF root beside
  `+dicom2nifti`, where `readVersion` looks for it. Third-party `readVersion.m` is unchanged.
  Its placement in the compiled job manager is **unverified** until an approved RC6 build.
- **No build or resource manifest is shipped.** The compiled-current build and resource
  manifests (`mlsc_current_build.mat` and `mlsc_current_resources.mat`) belong to source
  checkouts only. `manifest.json` is the release catalog, not a build manifest.
- Paths inside the distribution are relative to the installed location, so the tree
  works after it is moved or reached through a symlink.

## Runtime identity

- A runtime's identity is validated from its contents, not from directory names. A
  runtime is accepted only if:
  - `runtime/glnxa64/libmwmclmcrrt.so.<mcr_version>` is present and matches the catalog
    entry, and
  - `toolbox/compiler/mcrversion.ver` content matches the catalog `mcr_version`.
- `appdata/version.txt` and `appdata/version.xml` are **not** identity evidence.
- A directory name that looks like a release is not evidence. A matching runtime under
  a misleading name is accepted; a mismatching runtime under a plausible name is
  rejected before execution.

## The launcher: `bin/pseudoct`

`bin/pseudoct` is the single public launcher in both layouts. In an installed
distribution it selects a release and dispatches to its compiled executables. A
repository checkout (`src/` present) keeps its licensed MATLAB behaviour; `--mcr` and
`--mcr-root` are errors there, and `resolve` requires an installed distribution.

```
pseudoct run      [--mcr LABEL] [--mcr-root DIR] <CLI options>
pseudoct validate [--mcr LABEL] [--mcr-root DIR] <CLI options>
pseudoct headless REQUEST.mat RESULT.mat [--mcr LABEL] [--mcr-root DIR]
pseudoct resolve  [--mcr LABEL] [--mcr-root DIR]
pseudoct --list-releases
pseudoct --help
```

- There is no GUI operation in the launcher. The MATLAB window is `run_pseudo_CT`
  (see below). `gui` and `run --orchestrate` were removed; both are refused as unknown
  operations with exit `64`.
- `validate` (validate only) and `run` (validates, then submits in the same invocation) are the CLI with the same
  options, text/JSONL output and exit codes as in [Headless API and CLI](headless-cli.md).
- `headless` keeps the two-positional contract and runs `runtimes/<LABEL>/pseudoct_job_manager
  headless` with `PSEUDOCT_REQUEST_MAT` and `PSEUDOCT_RESULT_MAT`.
- `resolve` validates one release and prints single-quoted, sourceable lines:
  `PSEUDOCT_EXE='...'` (the job-manager dispatcher), `PSEUDOCT_MCR_ROOT='...'`,
  `PSEUDOCT_RUNNER='...'` (`runtimes/<LABEL>/run_pseudoct_pipeline.sh`),
  `PSEUDOCT_INSTALL_ROOT='...'` and `PSEUDOCT_RUNTIME_RELEASE='<LABEL>'`. This is the one
  runtime-selection mechanism; MATLAB callers use it.
- Every installed operation that runs a release (`run`, `headless`)
  exports `PSEUDOCT_INSTALL_ROOT` and `PSEUDOCT_RUNTIME_RELEASE`
  (the resolved label) before it runs the compiled executable, so the dispatcher binds
  the selected release and not the catalog default. A repository checkout unsets
  `PSEUDOCT_RUNTIME_RELEASE`.
- Each operation sets `LD_LIBRARY_PATH` to the MCR `runtime/glnxa64`, `bin/glnxa64` and
  `sys/os/glnxa64` directories and applies no licensed MATLAB.
- The package root is the parent of the real directory of `bin/pseudoct` (symlinks are
  resolved). Nothing is resolved from the working directory or from `scratch/`.

### Release and MATLAB Runtime root selection

- A release is complete only when all three artifacts exist and are executable, each
  directly in `runtimes/<LABEL>/`: `pseudoct_pipeline`, `run_pseudoct_pipeline.sh` and
  `pseudoct_job_manager`.
- The MATLAB Runtime root is `--mcr-root <dir>` when given; otherwise the catalog
  location `/usr/pubsw/common/matlab/<D>` of the selected release, where `<D>` is the
  first two dotted components of its `matlab_version` (`9.6.0.1072779` → `9.6`,
  `26.1.0.3251617` → `26.1`, `7.11` → `7.11`). Every catalog release is discovered this
  way. No environment variable takes part in discovery. A catalog location that is absent
  or fails identity validation stops the run and names the candidate, the missing item and
  `--mcr-root`; an explicit `--mcr-root` always takes precedence.
- A root only selects a directory. It never bypasses identity validation: the library
  and `mcrversion.ver` evidence must match the selected label, or nothing runs.
- In an installed distribution the catalog is the copy embedded under `catalog` in
  `manifest.json`. A repository checkout reads `config/releases.json`.

### Pipeline runner and installed-direct identity

`runtimes/<LABEL>/run_pseudoct_pipeline.sh` is installed beside `pseudoct_pipeline` and
`pseudoct_job_manager`. It takes
`<mcr_root> <phase> <job_manifest> [<resource_manifest>]`, sets the Runtime library
path from `mcr_root` and execs the compiled pipeline from its own directory. The
repository source of this runner is `scripts/run_pseudoct_pipeline.sh`; its v3.2.0
predecessor was renamed from the former MLSC payload runner name.

Installed runs (local and MLSC) use **installed-direct** mode, because no build or
resource manifest is shipped. Direct mode uses the two-argument pipeline call (phase
and job manifest, with no resource manifest). The pipeline checks the packaged
`resources/` files itself, and the MLSC generator fails closed when a required
resource is missing.

Installed-direct identity is a packaged-layout trust model:

- the runner is pinned by SHA-256 (`runner_path` and `runner_sha256` in the
  `artifact_identity` of the run), and the runtime checks in
  [Runtime identity](#runtime-identity) apply;
- the compiled pipeline (`pseudoct_pipeline`) and job manager (`pseudoct_job_manager`) are
  also hashed into that identity, beside the runner: `payload_path` and
  `payload_sha256` for the pipeline, and `standalone_path` and `standalone_sha256` for
  the job manager. Both are taken from the runner's directory. The manifest fields
  (`build_manifest_*` and `resource_manifest_*`) are empty in this mode.

Source checkouts keep manifest mode (`mlsc_current_build.mat` and
`mlsc_current_resources.mat`, or their text forms), with full SHA-256 checks of the
build and resource manifests and the runner.

## MATLAB frontend: `run_pseudo_CT.m` and `frontend/`

`run_pseudo_CT.m` ships unchanged from the repository, beside `bin/pseudoct`, with the
`frontend/` files it needs. Argument mode and the window both call the launcher through
`frontend/pseudo_CT_launch_request.m`: MATLAB parses the parameters, writes the launcher
arguments (POSIX single-quoted; no secret ever appears on a command line), runs
`bin/pseudoct validate|run ... --format jsonl` in a child environment without MATLAB's
library and path variables, and displays the result. No validation or science runs in
MATLAB.

`run_pseudo_CT.m` delegates only to `bin/pseudoct`, for argument mode and for the window's
Run action. The packaged frontend contains GUI and launch-bridge files, plus the
credential helpers (`pseudo_CT_credentials.m`, the password entry dialog and `passwordTools/`)
only. None of them is a scientific or SSH2 backend.

- `run_pseudo_CT('Profile', P, 'MPRAGE', FILE, ...)` validates by default; `'Action',
  'submit'` runs the launcher's `run` action. `'Runtime'` and `'McrRoot'` select the
  installed release and its MATLAB Runtime root. An installed distribution always runs the
  `bin/pseudoct` beside `run_pseudo_CT.m`; a `'Launcher'` naming any other file is refused
  (`run_pseudo_CT:LauncherOverrideDevelopmentOnly`) and `PSEUDOCT_LAUNCHER` is ignored. In a
  source checkout, `'Launcher'` or `PSEUDOCT_LAUNCHER` names the development or test launcher.
- `run_pseudo_CT()` (no arguments) opens the profile selector, then the MPRAGE/UMAP
  window. Run uses the same bridge and the same validation and submission rules described in
  [Validation and submission](headless-cli.md#validation-and-submission).
- The MATLAB Runtime root is the catalog location of the selected release (or the
  `--mcr-root` override); the window never asks for a folder.
- MLSC submission creates one single-use credential handoff with the existing
  `pseudo_CT_credentials('store', ...)` format and passes only its path to the launcher.
- The frontend needs `python3` to read the launcher's result record.

## Publication

`scripts/release_application.py` assembles the distribution in a staging directory in
the output directory and validates it. Publication is non-overwriting:

1. After each release's runtime and the resources are staged, the driver copies the
   release executables and runner. No build or resource manifest is generated: installed
   resources are verified by file name at setup by the job manager and at run time by the pipeline, and integrity is
   covered by `SHA256SUMS` and `--verify`.
2. An exclusive lock file `.pseudoct-release.lock` is created with `O_EXCL` in the
   output directory; a held or stale lock is refused and never removed automatically.
3. The destination is rechecked under the lock.
4. The fully validated staging directory is renamed to `pseudoct-<version>`.
5. The lock is removed on exit, success or failure.

A failed or incomplete build publishes nothing, and no staging directory or lock is left
behind after a normal failure. Residual limits: the lock is advisory and only protects
against other cooperating release runs; a process that creates the destination without
taking the lock between the recheck and the rename can still be overwritten by an empty
directory (POSIX `rename` replaces an empty directory), and a crash leaves the lock file
behind, which must then be removed by hand after confirming that no release is running.

**Publication status:** assembling a package is a separate, approved action. The
redistribution gate in [`dependencies.lock.json`](../dependencies.lock.json) blocks
public packaging until dependency provenance, notices and rights are cleared.

## Version and identity terminology

- `--version` is required for release builds. Accepted syntax:
  `^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$`.
- Marketed MATLAB release (for example R2010b): the selector label.
- MATLAB product version (for example 7.11): the installation's version.
- MATLAB Compiler version (for example 4.14 for R2010b, from
  `toolbox/compiler/Contents.m`): build provenance only, not runtime identity.
- Deployed MCR version (for example 7.14 for R2010b): the runtime identity, checked
  through `runtime/glnxa64/libmwmclmcrrt.so.<mcr>` and `toolbox/compiler/mcrversion.ver`.

## Verification status

What the evidence does and does not establish for the current source. Scientific
evidence is in [Scientific notes](scientific-notes.md#bounded-comparison-evidence).

| Area | Status |
|---|---|
| Offline release and launcher checks | Synthetic only: `tests/test_release_application.py` and `tests/test_standalone_release.py` use fake MATLAB roots, fake executables and fake runtime evidence. Passing them is not certification or deployment. See [tests](../tests/README.md). |
| Installed-direct MLSC generation and staging | Offline regression coverage only (`tests/test_mlsc_installed_direct.m`), with fixtures and no scheduler contact. |
| MLSC installed submit | Implemented and offline-tested. **Not independently verified** against a live scheduler or cluster. |
| Compiled R2010b local run | Maintainer-reported comparison against v3.0.2; see [Scientific notes](scientific-notes.md#bounded-comparison-evidence). The comparison record is not included in this repository. |
| Changed sources (v3.2.0) | Not built. The `compiled/` tree is obsolete and its executables still carry the pre-rename names. Source checkouts do not resolve it: an application run from a checkout is refused with a message to install the distribution. Rebuilding `compiled/` is not a fix. See [tests](../tests/README.md#source-checkouts-are-development-only). |
| RC6 packaging and runtime changes (flat `runtimes/<LABEL>/`, SSH2 closure, dicom2nifti `VERSION`) | Not built. Compiled-engine behaviour is **unverified**: SSH2 JAR and wrapper loading, JVM use and `VERSION` placement in the CTF. These need an approved RC6 build. |
| `build_application` real builds and packaged distribution | Not verified in this audit. No package has been assembled or verified for v3.2.0. |

### Staging path and temporary directories

The driver stages in a short `.s<random>` directory inside `--output`. Before MATLAB
runs, it refuses a build whose staged executable path would exceed 240 characters.
Choose a short `--output` when needed; the staging layout is unchanged.

For each selected release, the driver creates a private `/tmp/pct-<LABEL>-<random>/`
directory and overrides the child MATLAB environment with short subdirectories:

- `TMPDIR`: `t/` (MATLAB temporary files),
- `MATLAB_PREFDIR`: `p/` (isolated MATLAB preferences),
- `MCR_CACHE_ROOT`: `c/` (compiled-executable CTF extraction).

For releases after R2010b, `p/javaclasspath.txt` contains the absolute path to the
existing bundled Ganymed SSH2 JAR. It is present before MATLAB starts and supplements,
not replaces, the existing `mcc -a` JAR inclusion. R2010b retains its existing Java
loading procedure, without this static classpath file.

Each invocation gets fresh directories, even for repeated builds of the same release.
Only the driver-created private environment directory is removed on exit (success or
failure); inherited environment paths, user preferences and shared MATLAB installations
are never modified. MATLAB output and compiler logs remain in their existing locations.
An abrupt process kill can leave a private temporary directory behind. `--dry-run`
prints the environment preparation without creating directories or starting MATLAB.
