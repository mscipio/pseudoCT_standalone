# MLSC MATLAB SSH2 Compatibility Audit

This is the credential-free, non-destructive compatibility audit for the
existing MATLAB SSH2 path used by MLSC. It targets
`mlsc.nmr.mgh.harvard.edu` on TCP port 22 and the harmless remote command
`true`. It does not submit a job, stage a file, modify a host-key file, or
replace the existing transport.

## Operational model

The normal MLSC workflow uses the existing username/password SSH workflow,
analogous to Launchpad: the `passwordEntryDialog`-style runtime prompt, the
bundled Ganymed password-authentication transport, runtime Slurm account
discovery via `sshare -U -u $USER`, and the Slurm lifecycle. A missing
host-key provider is **not** a blocker for this path; no `known_hosts` entry,
fingerprint, or other trust material is required to connect, discover
accounts, or submit jobs.

Strict pinned host-key verification is an **optional development/testing
opt-in** only. It activates when the caller explicitly supplies the runtime
argument `mlsc_host_key_provider` to `run_pseudo_CT`. It is never a profile
field, never read from source control, never logged, and never required for
normal operation.

## Current result

- Crypto/transport compatibility is **PROVEN** (negotiation, authentication,
  and command execution through the bundled Ganymed transport).
- The normal-path contract is **PROVIDER_FREE**: a missing provider selects
  the Launchpad-style dialog, Ganymed password authentication, `sshare`
  account discovery, and the Slurm lifecycle.
- Strict host-key verification is reported as **OPT_IN** (development/testing
  only).
- The live `true` exit-status validation, `sshare` discovery, the Slurm/
  `$TMPDIR` test, and the one-subject E2E run are operator live readiness
  checks performed out-of-band; this credential-free audit reports them as
  **NOT_ATTEMPTED** and never claims they completed.

The local audit result is `PASS_LOCAL_AUDIT` when the checked-in sources
implement the contract above. A passing audit is not evidence of a passed
live readiness check. Production readiness is claimed only when the four
ordered live readiness checks — A) remote `true` returns numeric exit status
`0`, B) `sshare` account discovery, C) a lightweight Slurm/`$TMPDIR` test,
and D) a one-subject MLSC E2E run — have each been completed successfully by
an operator.

Run the credential-free audit from MATLAB:

```matlab
root_dir = '/path/to/pseudoCT_standalone';
addpath(fullfile(root_dir, 'scripts'), '-begin');
report = run_mlsc_ssh2_compatibility();
```

The explicit `live` selector is accepted for symmetry, but the harness never
prompts for credentials, opens a network connection, or submits a Slurm job
in any mode:

```matlab
report = run_mlsc_ssh2_compatibility('live');
```

Neither invocation accepts credentials or host-key data as arguments.

## Manual transport diagnostic (crypto PROVEN)

A successful out-of-band manual diagnostic used the bundled MATLAB/Ganymed
SSH2 library to authenticate to `mlsc.nmr.mgh.harvard.edu` and execute
`hostname; whoami`. The output returned the login hostname
`mlsc-login.nmr.mgh.harvard.edu`, and the `whoami` result confirmed the
authenticated operator account. This proves that the bundled Ganymed
transport can negotiate, authenticate, and execute on MLSC, so the
`ssh-rsa`-based algorithm compatibility is proven.

- The exact operator identity from that diagnostic is deliberately **not**
  published in this document, in any committed test, or in any other public
  committed content; it exists only in local, non-committed handoff evidence.
- The diagnostic did **not** run the command `true` and is **not** a
  substitute for live readiness check A.
- The command of record for live readiness check A remains exactly `true`,
  and no successful `true` run has been claimed through this document.

## Runtime credentials

Enter the username and password at runtime through the existing Launchpad
dialog UX. The established shape is:

```matlab
[PASSWORD, USERNAME] = passwordEntryDialog( ...
    'enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
    'WindowName', 'Login for: mlsc.nmr.mgh.harvard.edu');
```

Do not pass passwords on a command line, put them in a file or environment
variable, store them in a profile, or print them. Clear transient variables
after use. This preserves the existing username/password dialog rather than
introducing a new credential UX.

Authentication failures are reported by the transport without any account
query or submission attempt; a wrong or rejected password simply fails the
connection step. Cancelling the credential dialog submits no job.

## Optional strict host-key opt-in (development/testing)

When — and only when — a developer or test harness deliberately supplies the
runtime-only `mlsc_host_key_provider` argument, `mlsc_host_key_trust.m`
builds an in-memory trusted `KnownHosts` database and a host/port-pinned
`MLSCStrictHostKeyVerifier` that accepts only `HOSTKEY_IS_OK`, and
`ssh2_main.m` passes it to `Connection.connect(verifier)` before
authentication. In that mode a missing, blank, malformed, unsupported, new,
changed, or mismatched key fails closed before authentication, account
discovery, or submission, and no host-key material is persisted or logged.

This opt-in path must not disable host-key checking, downgrade algorithms, or
silently switch to OpenSSH or another SSH dependency; it exists to exercise
strict verification, not to weaken the normal path. The normal provider-free
workflow never enters this branch.

## Command exit status

Race-safe numeric exit-status collection is implemented: `ssh2_main.m`
performs a bounded `waitForCondition` for `EXIT_STATUS`/`CLOSED` before
`Session.getExitStatus()`, maps numeric `0` to success, any other number to
failure, and an unavailable status to an explicit failure, and never infers
status from stdout. `ssh2_command` keeps its one- and two-output legacy
callers compatible and exposes the numeric (or unavailable) status as the
optional third output. Live readiness check A validates this path against
the real server by requiring `true` to return numeric status `0`.

## Credential-free verification

Run the focused test without network access or credentials:

```matlab
addpath(fullfile(root_dir, 'scripts'), '-begin');
test_mlsc_ssh2_compatibility();
```

The test proves, without any connection or credential, that:

- the normal MLSC path is provider-free: dialog, Ganymed password
  authentication, `sshare` account discovery, and the Slurm lifecycle
  proceed without any trusted-material input;
- the strict verifier is opt-in only: when a provider is supplied it accepts
  only the trusted pinned key and fails closed on a mismatched key, a
  different host, a different port, an unsupported algorithm, and an
  unparseable blob, and the strict verifier is handed to
  `Connection.connect(verifier)` before authentication;
- the numeric exit status is collected after a bounded
  `EXIT_STATUS`/`CLOSED` wait before close, only `0` maps to success, and
  stdout never overrides the status;
- `ssh2_command` keeps its one- and two-output legacy callers compatible and
  exposes the numeric (or unavailable) status as the optional third output;
- the report publishes no credentials, no key material, and no operator
  identity, while recording the proven login hostname
  `mlsc-login.nmr.mgh.harvard.edu` and `Crypto compatibility: PROVEN`;
- the existing `passwordEntryDialog` credential UX is preserved unchanged.

Expected result is a passing report with `Normal MLSC path: PROVIDER_FREE`,
`Host-key verification: OPT_IN`, `Live validation: NOT_ATTEMPTED`,
`Command exit status: SEAM_VERIFIED`, `Crypto compatibility: PROVEN`,
`Result: PASS_LOCAL_AUDIT`, and no trusted-material blockers. A passing
credential-free test is not evidence of a passed live readiness check.
Production readiness remains unclaimed until live checks A)–D) above are
separately completed.
