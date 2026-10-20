# MLSC/Slurm Execution Pipeline

This document describes the MLSC remote/cluster workflow that replaces the
historical Launchpad execution path. MLSC uses the existing compiled pseudoCT
runner, but changes the control, staging, and scheduling path to a shared
filesystem and Slurm. It uses the same username/password SSH workflow as
Launchpad. It does not claim that the workflow is production-ready: the
ordered live readiness checks below — remote `true` exit status, `sshare`
account discovery, a lightweight Slurm/`$TMPDIR` test, and one-subject
end-to-end processing — remain release blockers.

The examples use MATLAB R2010b-compatible character-array paths and profile
names. The compiled runner uses MATLAB Compiler Runtime (MCR) 7.11 terminology;
the current orchestration and verification seams remain compatible with MATLAB
R2010b.

## Profile contract

The MLSC column of the implementation x execution matrix
(see [pipeline-local.md](pipeline-local.md)) covers both the legacy v2.0 compiled
implementation (Aether lineage) run on the cluster via Slurm and the selectable
`mlsc-current` profile (current source MATLAB on MLSC, fail-closed before Gate-A;
see `src/config/profiles/mlsc_current.m`). The bare key
`mlsc` is only a deprecated alias for `mlsc-legacy` and creates no selector
row.

The profile selector separates the standard remote workflow from the specialized
MPRAGE-only workflow:

| Profile | Input/reference policy | Output policy | Use |
|---|---|---|---|
| `mlsc-legacy` | Standard MPRAGE + required UMAP reference | NIfTI and DICOM | Recommended remote/cluster profile |
| `mlsc-mprage-only` | MPRAGE with no reference required | NIfTI only | Specialized, not recommended for routine use |

`mlsc-legacy` uses the normal mMR GUI and discovers the UMAP from the subject's MR
directory. `mlsc-mprage-only` uses the MPRAGE-only GUI, does not require a UMAP,
and skips DICOM generation because there is no reference geometry. Both profiles
use the same MLSC/Slurm resources and node-local processing contract.

**Local MATLAB (Current)** remains the recommended routine profile while MLSC's
live readiness checks remain open. Other specialized profiles are retained for known
compatibility, validation, or development purposes; do not select one without a
specific reason.

**Launchpad is deprecated and not supported.** It will soon be discontinued/decommissioned
and is being replaced by MLSC. Its deprecated source and profile are retained only for
transitional/reference purposes and must not be treated as a recommended or
usable remote workflow.

## Prerequisites and connection model

The selected profile must resolve the externally provisioned MLSC runner, MCR,
defaults MAT, Batch_atlas templates, FreeSurfer environment, and `/bin/bash`.
The shared subject temporary directory must be readable and writable. The
configured MLSC host is:

```text
mlsc.nmr.mgh.harvard.edu
```

The SSH connection is a control path only. It runs account-discovery and Slurm
commands; it does not carry the MPRAGE, script, or output payload. The generated
script and subject files remain on the shared filesystem.

### Runtime credentials

The user is prompted at runtime with the existing modal
`passwordEntryDialog`-style username/password UX, exactly analogous to the
Launchpad login workflow. Username and password are held only in a transient
runtime closure, then cleared. They must not be stored in a profile, command
line, environment variable, script, log, or evidence record, and they must
never be printed.

After the dialog, MLSC authenticates over the bundled Ganymed SSH2 transport
with password authentication, then proceeds to account discovery and the
Slurm lifecycle. This is the normal operational path and requires no
host-key material, no `known_hosts` file, and no fingerprint input.

### Optional strict host-key verification (development/testing)

Strict pinned host-key verification is an optional development/testing
capability, not a prerequisite for normal use. It activates only when the
caller explicitly supplies the runtime-only `mlsc_host_key_provider`
argument to `run_pseudo_CT` (a known_hosts record or a zero-argument
provider handle). It is never a profile field, never read from source
control, and never logged. When supplied, `mlsc_host_key_trust.m` builds an
in-memory trusted `KnownHosts` database and a host/port-pinned strict
verifier, `ssh2_main.m` passes it to `Connection.connect(verifier)` before
authentication, and missing, malformed, new, changed, or mismatched key
material fails closed before any account query or submission. When not
supplied, the transport uses its existing password-authentication connect
branch and no strict verification is attempted.

### Current SSH2 transport status

Crypto/transport compatibility is **PROVEN**: a successful out-of-band manual
diagnostic used the bundled Ganymed library to authenticate to MLSC and
execute `hostname; whoami`, returning the login hostname
`mlsc-login.nmr.mgh.harvard.edu`; the `whoami` result confirmed the
authenticated operator account (its exact identity is deliberately not
published in committed content). Negotiation, authentication, and command
execution through the bundled Ganymed transport are therefore proven.

The command wrapper collects the numeric exit status through a bounded
`EXIT_STATUS`/`CLOSED` wait before `Session.getExitStatus()`; only `0` maps
to success and stdout never overrides the status. The remaining open items
are the four ordered live readiness checks at the end of this document:
the live `true` exit-status check, `sshare` account discovery, a lightweight
Slurm/`$TMPDIR` test, and a one-subject end-to-end run. These are operator
live checks, not trusted-material blockers. If a live check finds an SSH
incompatibility, it must report the exact blocker and stop pending an
approved transport decision; it must not weaken authentication handling,
downgrade algorithms, or silently replace the transport.

## Runtime account discovery and selection

After authentication succeeds, the authenticated user’s available accounts
are queried at runtime with:

```text
sshare -U -u $USER
```

The account is never a profile setting or a persisted caller override:

- **Zero accounts:** fail before submission; no Slurm job is submitted.
- **One account:** select it automatically for this run.
- **Multiple accounts:** show a single-selection MATLAB dialog and use the
  selected account for this run only.
- **Cancel:** stop MLSC submission; no Slurm job is submitted.

The selected account may be recorded as non-secret lifecycle evidence, but it is
not saved as configuration or reused by a later run.

## Stage 1 — Shared input preparation

MATLAB creates the usual subject directories and converts or stages the selected
MPRAGE into the existing shared subject temporary directory:

```text
<subject_root>/MR_PET/tmp/mprage.nii
```

For the standard `mlsc-legacy` profile, the MPRAGE and its UMAP reference are collected
using the normal input rules. For `mlsc-mprage-only`, an MPRAGE NIfTI or converted
DICOM input is sufficient and no UMAP is required.

The shared temporary directory is the control and staging location. Before a
job is submitted, MLSC preflight verifies the top-level shared input, shared
directory readability/writability, configured resource paths, and transient
submission values. Invalid or unsafe paths fail before submission.

## Stage 2 — Script generation and Slurm request

One shell script is generated per subject on the shared filesystem. Every path,
account, runner argument, and configurable value is safely quoted for the POSIX
shell. The script contains no credentials and no SCP/network payload operation.

The current request is exactly:

```text
partition:     basic
nodes:         1
tasks:         1
CPUs per task: 4
memory:        8G
time:          02:00:00 (2 hours)
```

The runtime account is applied only to the submission command:

```text
sbatch --parsable --account <runtime-account> -- <shared-script-path>
```

`--parsable` is required so the lifecycle can accept one numeric job ID rather
than parsing human-oriented output. The generated script directs ordinary Slurm
stdout/stderr away; subject-level operational details are retained in the
MATLAB log and lifecycle record described below.

## Stage 3 — Node-local processing

The batch shell must receive a writable, node-local `$TMPDIR`. It rejects an
empty, unavailable, unwritable, or shared-subject `$TMPDIR` before processing.
The heavy processing sequence is:

```text
shared subject temp/mprage.nii
        │  normal filesystem cp
        ▼
node-local $TMPDIR/mprage.nii
        │
        ├─ source FreeSurfer environment in the batch shell
        ├─ env -u LD_LIBRARY_PATH mri_normalize ...   (when needed)
        └─ unchanged compiled pseudoCT runner in $TMPDIR
```

The input is copied with normal filesystem `cp` from shared storage to
`$TMPDIR`, and the batch shell changes directory to `$TMPDIR` before running
FreeSurfer or the compiled runner. No heavy MLSC processing runs in the shared
working directory.

For an input that is not already named as normalized, FreeSurfer is sourced and
`mri_normalize` runs in `$TMPDIR`. The command is invoked as:

```text
env -u LD_LIBRARY_PATH mri_normalize <local-input> <local-normalized-output>
```

Unsetting `LD_LIBRARY_PATH` for this child isolates FreeSurfer from MATLAB and
other local runtime libraries. The FreeSurfer environment is sourced only inside
the batch shell; it is not imported into the local MATLAB process.

The unchanged compiled runner then executes in `$TMPDIR` with the configured MCR,
defaults MAT, Batch_atlas directory, and remote aliasing flag. The job also sets:

```text
MCR_CACHE_ROOT=$TMPDIR/mcr_cache
OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
MKL_NUM_THREADS=$SLURM_CPUS_PER_TASK
```

With the current request, the OMP/MKL values are 4. The MCR cache is node-local
and is not mixed with the MATLAB installation or shared subject directory.

## Stage 4 — Required and optional output copy-back

The runner must first create a non-empty node-local:

```text
$TMPDIR/att_map.nii
```

The script copies it with normal filesystem `cp` to:

```text
<subject_root>/MR_PET/tmp/att_map.nii
```

It then verifies that the shared copy is present and non-empty. The job cannot
be considered a successful workflow, and local finalization cannot begin, until
this copy-back check passes. This is deliberately separate from the Slurm
scheduler’s `COMPLETED` state.

The following top-level files are useful optional copy-back outputs when present:

- `Fusion_MR_Pseudo_CT_validation.tiff` — QC fusion image;
- `Pseudo_CT_AC_Version.txt` — pseudoCT version record;
- the normalized MPRAGE produced by FreeSurfer.

The optional files are copied from `$TMPDIR` to the shared subject temporary
directory with normal `cp`. The finalizer can promote the available normalized
image to `MR_PET/MPRAGE_spm_normalized.nii`; it does not make optional output a
substitute for the required attenuation map.

There is no `scp_put`, `scp_get`, SCP staging, or network payload transfer in the
MLSC path. SSH is reserved for control commands and Slurm lifecycle operations.

## Stage 5 — Slurm lifecycle

After submission, the authenticated control connection polls stable machine
output rather than human-oriented scheduler output:

```text
squeue --noheader --jobs=JOBID --format=%T

sacct --allocations --noheader --parsable2 --jobs=JOBID \
  --format=JobIDRaw,State,ExitCode,Start,End,Elapsed
```

`squeue` provides the live pending/running view. The primary allocation record
from `sacct` is authoritative for terminal state and `ExitCode`, including when
accounting is delayed. The lifecycle normalizes pending, running, completed,
failed, cancelled, timeout, out-of-memory, node-failure, and unknown outcomes.

If polling reaches its bound, the lifecycle requests cancellation with
`scancel`, waits for bounded terminal accounting when possible, and otherwise
records timeout or unknown rather than claiming success. A non-zero exit code,
failed/cancelled/timeout/unknown state, unavailable terminal accounting, missing
node-local output, or failed copy-back prevents local finalization.

In particular, scheduler `COMPLETED` is not enough. Success additionally requires
the represented node-local/copy-back contract and a non-empty
`MR_PET/tmp/att_map.nii` in the exact shared temporary directory consumed by
local finalization.

## Stage 6 — Existing local finalization

Only an eligible MLSC lifecycle result proceeds to the existing mode-neutral
post-remote finalization path. It is reused rather than duplicated:

1. Apply the configured local background-mask step when requested.
2. For the standard `mlsc-legacy` profile, convert the shared `att_map.nii` to DICOM
   using the discovered UMAP geometry and write the series under
   `MR/pseudo_muMAP/`.
3. Use `pseudo_CT_promote_final_outputs` to stage and promote the required
   `MR_PET/att_map.nii` and available QC, version, seed, and normalized outputs.
4. On successful promotion, remove the shared `MR_PET/tmp/` directory when
   `cleanup_on_success` is enabled.

The `mlsc-mprage-only` profile skips DICOM output by policy and promotes the
NIfTI attenuation map plus any available optional outputs. If promotion fails,
the temporary files are preserved and the subject is reported as failed.

Slurm owns cleanup of node-local `$TMPDIR` when the job exits. MLSC lifecycle
cleanup also removes the generated shared script when configured to do so. The
normal pseudoCT shared temporary cleanup remains profile-controlled: successful
promotion removes it when enabled, while failures or interruption retain it for
inspection.

## Logs and evidence

Each requested subject receives the usual local log under `MR_PET`, named in the
form:

```text
pseudo_CT_mlsc-legacy_<runid>.log
```

The log records the selected profile and mode, input and shared temporary paths,
stage messages, scheduler/failure messages, and final subject status. The
profile summary records the execution profile, relevant settings, and MATLAB
environment. Retain these with the final QC and version files when requesting
support.

The MLSC lifecycle also produces a credential-free
`pseudo-CT.mlsc-evidence/v1` record. When an evidence directory is configured,
it is written as:

```text
mlsc_evidence.mat
```

The record can contain the runtime account, numeric job ID, timestamps, state
history, `squeue`/`sacct` contracts, terminal state and exit code, node-local and
shared staging intent, no-SCP/network-payload status, copy-back verification,
cleanup result, and failure detail. It rejects username, password, SSH
internals, and other credential fields rather than serializing them.

## Failure handling

The workflow fails closed at each boundary:

- missing or unsafe configured resources, unreadable input, or unwritable shared
  temporary paths fail before submission;
- a failed connection or password authentication prevents account discovery
  and job submission (with the optional strict provider supplied, failed
  host-key verification additionally stops the connection before
  authentication);
- zero available accounts or a cancelled account dialog submits no job;
- a malformed `sbatch --parsable` response is rejected rather than assigned a
  guessed job ID;
- missing or empty node-local `att_map.nii` prevents copy-back;
- missing or empty shared `att_map.nii` prevents scheduler success from becoming
  workflow success;
- any non-success normalized Slurm result prevents local finalization;
- output-promotion or cleanup errors are reported, with temporary data retained
  where it is needed for diagnosis.

Expected runtime is approximately **1 hour per subject**, excluding queue wait.
MATLAB must remain open while the MLSC job is being monitored and while local
finalization is performed. Closing MATLAB can leave a scheduler job or shared
outputs without monitoring and finalization.

## Ordered live readiness checks

These checks must be completed in order. Credential-free smoke tests
demonstrate script and lifecycle behavior but do not replace the live checks.

- **A) Remote `true` exit status.** Using the normal provider-free MLSC
  connection — the existing `passwordEntryDialog`-style runtime credential
  prompt and Ganymed password authentication to
  `mlsc.nmr.mgh.harvard.edu` — run exactly the harmless command `true` and
  require a numeric SSH exit status of `0`. A TCP connection, authentication
  success, or empty stdout alone is insufficient.
- **B) `sshare` account discovery.** On the same authenticated connection, run
  `sshare -U -u $USER` and confirm that runtime account discovery returns at
  least one account and that the zero/one/multiple/cancel selection contract
  behaves as documented above.
- **C) Lightweight Slurm/`$TMPDIR` test.** Submit a minimal Slurm test with the
  exact basic/1-node/1-task/4-CPU/8G/2-hour resource contract and confirm
  that the batch shell receives a writable, node-local `$TMPDIR`, that
  `sbatch --parsable` returns one numeric job ID, and that the machine-
  readable `squeue`/`sacct` queries work. No pseudoCT processing is required
  in this step.
- **D) One-subject MLSC E2E.** Run one subject through the standard `mlsc-legacy`
  profile and verify node-local `mri_normalize` and compiled-runner execution,
  required and optional outputs, non-empty shared copy-back, lifecycle logs and
  evidence, existing local finalization, DICOM output, and cleanup of both
  node-local `$TMPDIR` and normal shared temporary data. A specialized
  MPRAGE-only check may additionally verify its no-reference/NIfTI-only policy.

**Production readiness is not claimed until readiness checks A–D all pass.**

## Related documentation

- [MATLAB SSH2 compatibility audit](mlsc-ssh2-compatibility.md)
- [Local execution pipeline](pipeline-local.md)
- [Historical Launchpad execution pipeline](pipeline-launchpad.md)
