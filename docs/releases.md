# pseudoCT release catalog and standalone layout

This document records the MATLAB release catalog used by the multi-release standalone
workflow. The machine-readable source is `config/releases.json`; this file explains it.
Values here must match that file.

## Supported exact release labels

Each `--mcr` value must be one of these exact labels.

| Release label | MATLAB version      | MCR version | Architecture | Runtime library                 |
|---------------|---------------------|-------------|--------------|---------------------------------|
| R2010b (default) | 7.11           | 7.14        | glnxa64      | `libmwmclmcrrt.so.7.14`         |
| R2014a        | 8.3                 | 8.3         | glnxa64      | `libmwmclmcrrt.so.8.3`          |
| R2014b        | 8.4                 | 8.4         | glnxa64      | `libmwmclmcrrt.so.8.4`          |
| R2019a        | 9.6.0.1072779       | 9.6         | glnxa64      | `libmwmclmcrrt.so.9.6`          |
| R2019b        | 9.7.0.1190202       | 9.7         | glnxa64      | `libmwmclmcrrt.so.9.7`          |
| R2022a        | 9.12.0.2039608      | 9.12        | glnxa64      | `libmwmclmcrrt.so.9.12`         |
| R2022b        | 9.13.0.2049777      | 9.13        | glnxa64      | `libmwmclmcrrt.so.9.13`         |
| R2026a        | 26.1.0.3251617      | 26.1        | glnxa64      | `libmwmclmcrrt.so.26.1`         |

- The default release is **R2010b**.
- **R2010a** and **R2026b** are not in the catalog because they are not installed
  on the inspected workstation. Do not add them without inspecting an installation.
- Identity terms are defined in [Identity terminology](#identity-terminology).

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
  `--version`. No `VERSION` file or `git describe` is inferred.
- MATLAB installation roots are explicit build inputs supplied at build time
  (`--matlab-root LABEL=PATH`). They are not stored in `config/releases.json`.
- The default output directory is `<repository>/dist/`, derived from the location of
  the driver, not from the working directory. `--output DIR` overrides it.

## Distribution layout

```
pseudoct-<version>/
  bin/pseudoct                                          the only public launcher
  run_pseudo_CT.m                                       installed MATLAB wrapper (generated)
  runtimes/<LABEL>/app/run_pseudo_CT                    compiled GUI/application
  runtimes/<LABEL>/app/run_pseudo_CT.ctf                compiler sidecar (optional)
  runtimes/<LABEL>/payload/mlsc_current_payload         compiled MLSC payload
  runtimes/<LABEL>/payload/run_mlsc_current_payload.sh  payload runner (copy of scripts/)
  runtimes/<LABEL>/payload/build_manifest.mat           per-release build manifest (package-manifests)
  runtimes/<LABEL>/payload/resource_manifest.mat        per-release resource manifest (package-manifests)
  runtimes/<LABEL>/standalone/pseudoct_standalone       compiled CLI/headless/orchestration dispatcher
  runtimes/<LABEL>/standalone/pseudoct_standalone.ctf   compiler sidecar (optional)
  resources/                                            atlas and template files
  manifest.json                                         canonical; embeds the release catalog
  SHA256SUMS                                            sorted checksums, includes manifest.json
```

- `*.ctf` sidecars are kept only directly inside `app/`, `payload/` and `standalone/`.
- The distribution contains no `src/`, no tests, no build tools, no logs and no `cfggen/`.
  Its only launcher is `bin/pseudoct`. `--verify DIR` of the driver refuses anything else.
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
`--mcr-root` are errors there, and `gui`, `resolve` and `run --orchestrate` require an
installed distribution.

```
pseudoct gui      [--mcr LABEL] [--mcr-root DIR]
pseudoct run      [--mcr LABEL] [--mcr-root DIR] validate|run <CLI options>
pseudoct run      [--mcr LABEL] [--mcr-root DIR] --orchestrate REQUEST.mat REPORT.mat
pseudoct headless REQUEST.mat RESULT.mat [--mcr LABEL] [--mcr-root DIR]
pseudoct resolve  [--mcr LABEL] [--mcr-root DIR]
pseudoct --list-releases
pseudoct --help
```

- `gui` runs `runtimes/<LABEL>/app/run_pseudo_CT` with no arguments, in the background
  from the wrapper.
- `run validate|run` is the CLI (validate, or validate and submit) with the same
  options, text/JSONL output and exit codes as before. The action word follows `run`.
- `run --orchestrate` runs `standalone/pseudoct_standalone orchestrate REQUEST REPORT`
  and returns its exit status. The installed wrapper uses it.
- `headless` keeps the two-positional contract and runs `standalone/pseudoct_standalone
  headless` with `PSEUDOCT_REQUEST_MAT` and `PSEUDOCT_RESULT_MAT`.
- `resolve` validates one release and prints single-quoted, sourceable lines:
  `PSEUDOCT_EXE='...'` (the standalone dispatcher), `PSEUDOCT_MCR_ROOT='...'`,
  `PSEUDOCT_RUNNER='...'` (`runtimes/<LABEL>/payload/run_mlsc_current_payload.sh`),
  `PSEUDOCT_INSTALL_ROOT='...'` and `PSEUDOCT_RUNTIME_RELEASE='<LABEL>'`. This is the one
  runtime-selection mechanism; MATLAB callers use it.
- Every installed operation that runs a release (`gui`, `run`, `headless`,
  `run --orchestrate`) exports `PSEUDOCT_INSTALL_ROOT` and `PSEUDOCT_RUNTIME_RELEASE`
  (the resolved label) before it runs the compiled executable, so the dispatcher binds
  the selected release and not the catalog default. A repository checkout unsets
  `PSEUDOCT_RUNTIME_RELEASE`.
- Each operation sets `LD_LIBRARY_PATH` to the MCR `runtime/glnxa64`, `bin/glnxa64` and
  `sys/os/glnxa64` directories and applies no licensed MATLAB.
- The package root is the parent of the real directory of `bin/pseudoct` (symlinks are
  resolved). Nothing is resolved from the working directory or from `scratch/`.

### Release and MATLAB Runtime root selection

- A release is complete only when all four artifacts exist and are executable:
  `app/run_pseudo_CT`, `payload/mlsc_current_payload`,
  `payload/run_mlsc_current_payload.sh` and `standalone/pseudoct_standalone`.
- The MATLAB Runtime root precedence is:
  1. `--mcr-root <dir>`
  2. `PSEUDOCT_MCR_ROOT_<LABEL>`, for example `PSEUDOCT_MCR_ROOT_R2010b`
  3. `PSEUDOCT_MCR_ROOT`
- A root only selects a directory. It never bypasses identity validation: the library
  and `mcrversion.ver` evidence must match the selected label, or nothing runs.
- In an installed distribution the catalog is the copy embedded under `catalog` in
  `manifest.json`. A repository checkout reads `config/releases.json`.

### Payload runner

`payload/run_mlsc_current_payload.sh` is installed beside `mlsc_current_payload`. It
takes `<mcr_root> <phase> <job_manifest> <resource_manifest>`, sets the Runtime library
path from `mcr_root` and execs the compiled payload from its own directory. The
repository branch of `scripts/run_mlsc_current_payload.sh` is unchanged.

## Installed MATLAB wrapper: `run_pseudo_CT.m`

The package root contains a generated `run_pseudo_CT.m`. It never references `src/`.

- `run_pseudo_CT()` (no arguments) starts `bin/pseudoct gui` in the background and
  returns `report = []`.
- `report = run_pseudo_CT(...)` saves the arguments as variable `arguments` in a
  temporary request MAT, runs `bin/pseudoct run --orchestrate REQUEST RESULT`, raises an
  error with the captured output on a non-zero status, and returns the `report`
  variable of the result MAT. Temporary files are removed on exit.

Every path placed in a shell command (the launcher, the temporary request and report
MAT files) is passed through a POSIX single-quote helper, `shell_word`, so `$`, backticks,
quotes, spaces and parentheses in the install or temporary paths stay literal. The
generated text contains no double-quote character. The quoting rule is tested in
`tests/test_release_application.py`.

The repository `run_pseudo_CT.m` is not changed by this.

## Publication

`scripts/release_application.py` assembles the distribution in a staging directory in
the output directory and validates it. Publication is non-overwriting:

0. after each release's runtime and the resources are staged, the driver runs that
   release's `standalone/pseudoct_standalone package-manifests PAYLOAD RESOURCES PAYLOAD`
   under that release's MATLAB Runtime (`LD_LIBRARY_PATH` as the runner sets it). The
   environment carries `PSEUDOCT_RUNTIME_RELEASE`, `PSEUDOCT_INSTALL_ROOT` (the staging
   package) and `PSEUDOCT_RUNTIME_MCR_VERSION`, the catalog `mcr_version` of that label
   (for example `7.14` for R2010b), read from the catalog and not from MATLAB. It writes
   `build_manifest.mat` and `resource_manifest.mat` into the release payload
   directory; both must exist and be non-empty. They are listed in `manifest.json` and
   `SHA256SUMS` like every other file. Manifests must use paths relative to the package
   (the atlas directory is recorded as `../../../resources`, relative to the manifest
   folder `runtimes/<LABEL>/payload/`: three `..` steps reach the package root, so it
   resolves to `<package>/resources`). The driver fails if either
   file contains the staging directory, and nothing is published;
1. an exclusive lock file `.pseudoct-release.lock` is created with `O_EXCL` in the
   output directory; a held or stale lock is refused and never removed automatically;
2. the destination is rechecked under the lock;
3. the fully validated staging directory is renamed to `pseudoct-<version>`;
4. the lock is removed on exit, success or failure.

A failed or incomplete build publishes nothing, and no staging directory or lock is left
behind after a normal failure. Residual limits: the lock is advisory and only protects
against other cooperating release runs; a process that creates the destination without
taking the lock between the recheck and the rename can still be overwritten by an empty
directory (POSIX `rename` replaces an empty directory), and a crash leaves the lock file
behind, which must then be removed by hand after confirming that no release is running.

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

Synthetic tests in `tests/test_release_application.py` and
`tests/test_standalone_release.py` use fake MATLAB roots, fake compiled executables and
fake runtime evidence only. A real MATLAB Compiler build and real MCR loading have not
been qualified by these tests.
