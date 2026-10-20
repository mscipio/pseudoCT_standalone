# MLSC Current Release Gate (T001/T002)

> Status: tooling implemented, unexecuted. No release-candidate build has
> been compiled, no package published, no deployment performed. This
> document describes the human-operated sequence only.

## 0. Confinement

MLSC CURRENT only. The release-candidate build path, the packaged-files
inventory, and the publication validator leave LEGACY, local, and
Launchpad behavior unchanged: ordinary `build_mlsc_current` invocations
(without release arguments) follow the byte-identical historical path
(same entrypoint, same `-I`/`-a` manifest, same defaults, same manifest
fields plus the additive inventory), and no file under `src/launchpad/`,
legacy profiles, or the deprecated Launchpad path is touched.

## 1. Sequence

```
CANDIDATE-BUILD  →  VALIDATE (prepublication)  →  COPY + PROVENANCE  →  PUBLISH
       →  VERIFY (postinstall, at the exact runtime path)
```

1. **Candidate-build** (human-operated, clean checkout at the release
   tag): `scripts/build_mlsc_current.m` with `ReleaseTag`/`ReleaseCommit`
   resolves the expected commit (commit==tag enforced), then BEFORE
   compiling requires HEAD plus the clean-tree fingerprint to equal that
   exact release source (fail closed), isolates compilation inputs in a
   clean detached worktree under `scratch/release_gate/` (the dirty tree
   never contaminates the build; an existing worktree is reused ONLY
   when it IS the repository top level — canonical candidate path
   must equal the controlled `git -C <candidate> rev-parse
   --show-toplevel` answer (GIT_DIR/GIT_WORK_TREE stripped), so a
   plain subdirectory reporting its parent, a bogus `.git` entry, or
   a lookup error is refused as unverifiable — AND pristine: same
   HEAD, no uncommitted changes, matching
   clean-tree fingerprint — otherwise the build refuses and the operator
   removes it before a fresh worktree is created on re-run), compiles the unchanged
   `src/mlsc/mlsc_current_payload.m` entrypoint with the pinned R2026a
   Compiler and the unchanged `-I`/`-a` manifest (re-rooted at the
   worktree), and stages outputs under `scratch/release_gate/<label>/`.
2. **Validate (prepublication)**: `scripts/validate_mlsc_release.m`
   `prepublication` checks the staged package (10 requirements, §4).
   The release-tree fingerprint is always recomputed from the
   repository; a recompute failure propagates and blocks (recorded-only
   evidence is never accepted).
3. **Copy + provenance**: the operator copies the validated package to
   the deployment root using the exact runtime mapping (staged
   `payload_build/<name>` deploys flat to `<DeployRoot>/<name>`, so the
   launcher sits at the root per the pinned profile with the manifests
   alongside) and records deployment-copy provenance (which
   packaged inventory hashes were verified at the exact runtime path).
4. **Publish**: only after prepublication PASS plus Gate-A binding.
5. **Verify (postinstall)**: `validate_mlsc_release` `postinstall`
   re-verifies every packaged inventory hash at the exact `DeployRoot`
   under the pinned flat runtime layout (nested `payload_build`
   staging is rejected as a mismatched layout).

Gate A itself (launcher/MCR/headless PREPARE+COMPUTE against the exact
candidate, then `mlsc_finalize_gate_a`) still needs separate human
authorization per the existing runbook; the publication validator
requires the finalized Gate-A record but never mints one.

## 2. Human-operated commands

Release-candidate build (from a checkout pinned at the release tag;
the gate blocks on any dirty tree, so this is normally a fresh clone
or an isolated worktree — the build additionally isolates its own
compile worktree and never publishes, installs, or tags):

```
/usr/pubsw/packages/matlab/26.1/bin/matlab -batch "addpath(fullfile(pwd,'scripts')); build_mlsc_current('ReleaseTag','vX.Y.Z')"
```

With an explicit commit pin and an out-of-band expected fingerprint:

```
/usr/pubsw/packages/matlab/26.1/bin/matlab -batch "addpath(fullfile(pwd,'scripts')); build_mlsc_current('ReleaseTag','vX.Y.Z','ReleaseCommit','<40-hex>','ExpectedFingerprint','<64-hex>')"
```

Prepublication validation of the staged package:

```
/usr/pubsw/packages/matlab/26.1/bin/matlab -batch "addpath(fullfile(pwd,'scripts')); validate_mlsc_release('prepublication','PackageDir',fullfile(pwd,'scratch','release_gate','vX.Y.Z'),'ReleaseTag','vX.Y.Z','GateARecord','/path/to/mlsc_current_gate_a.mat')"
```

Postinstall verification of the deployment copy:

```
/usr/pubsw/packages/matlab/26.1/bin/matlab -batch "addpath(fullfile(pwd,'scripts')); validate_mlsc_release('postinstall','BuildManifest','<package>/mlsc_current_build.mat','ResourceManifest','<package>/mlsc_current_resources.mat','ReleaseTag','vX.Y.Z','GateARecord','/path/to/mlsc_current_gate_a.mat','DeployRoot','<exact runtime path>')"
```

Test seam (bounded, nonprocessing; mcc unreachable — only the gate
helper and the validator run, with synthetic manifests):

```
/usr/pubsw/packages/matlab/26.1/bin/matlab -batch "addpath(fullfile(pwd,'scripts')); addpath(fullfile(pwd,'src','mlsc')); test_mlsc_release_gate"
```

The shared gate logic (`resolve_commit`, `release_tree`,
`verify_clean_source`, `ensure_worktree`, `sha256_file`,
`inventory_dir`, `is_valid_sha256`) lives in
`src/mlsc/mlsc_release_gate.m` and is used by both the build path and
the validator, so the two cannot drift on exact-source semantics.

## 3. Manifest schema notes

Schema strings and versions are unchanged
(`pseudo-CT.mlsc-current-build/v1`, version 1;
`pseudo-CT.mlsc-current-resources/v1`, version 1;
`pseudo-CT.mlsc-current-gate-a/v1`, version 1), so the existing
`mlsc_current_validate` contract keeps working. The build manifest
gains additive fields only:

| Field | Ordinary build | Release-candidate build |
|---|---|---|
| `build_mode` | `'local'` | `'release-candidate'` |
| `release_tag` | `''` | tag as given (`''` when commit-pinned) |
| `release_commit` | `''` | expected 40-hex commit |
| `release_tree` | `''` | `rev-parse <commit>^{tree}` |
| `release_worktree` | `''` | repo-relative `scratch/release_gate/worktree-<label>` |
| `packaged_files` | sorted relpaths of every staged file | same |
| `packaged_checksums` | `'<rel> bytes=<N> sha256=<hex>'` per file | same |
| `packaged_files_fingerprint` | SHA-256 over canonical `'<rel>\t<hex>\n'` | same |

The inventory covers every file staged under the output root except
the self-describing pair `mlsc_current_build.mat`/`.txt` (self-hash
impossible; the `.mat` identity is bound instead by the Gate-A
record's `build_manifest_checksum`). The human-readable
`mlsc_current_build.txt` companion lists the new fields. `dist/` is
excluded from release archives by the existing export policy, which is
why deployment-copy provenance (§5) is recorded separately instead of
assuming the archive carries the build tree.

## 4. Validator check table (10 requirements)

| # | Requirement | Check | Block reason contains |
|---|---|---|---|
| 1 | commit==tag | tag resolves read-only; manifest `source_commit`/`release_commit` equal it; built-for tag equals it | `source_commit`, `release tag` |
| 2 | artifacts-from-source | recomputed `<commit>^{tree}` equals manifest `release_tree` (recompute failure propagates, never a recorded-only accept); `build_mode` is `release-candidate` | `release_tree`, `release-candidate` |
| 3 | compiler+MCR compat | `MATLAB Compiler 26.1 (R2026a)`, R2026a/26.1/glnxa64/26.1, pinned root with disk-validated `VersionInfo.xml` (existing contract), update satisfied, 3 toolboxes | `compiler`, `MCR_ROOT`, `update`, `toolbox` |
| 4 | required files | prepublication: `payload_build/` (dist), launcher, compiled CTF/executable, build + resource manifests, non-empty; postinstall: the pinned flat runtime layout (launcher at the root, executable beside it, manifests alongside) | `payload_build`, `mlsc_current_payload`, `resource`, `runtime layout` |
| 5 | SHA match | runner/exe/resource/inventory hashes recomputed from disk | `runner`, `wrong hash` |
| 6 | package==build | per-file inventory match; staged set equals inventory (extras block); deployed set equals the mapped inventory (staged `payload_build/<name>` → `<DeployRoot>/<name>`) | `package-vs-build`, `deploy-vs-package`, `Stale extra` |
| 7 | runtime paths pinned | MCR_ROOT is the pinned tree; staged runner path equals the manifest (prepublication) | `runtime path`, `pinned` |
| 8 | Gate-A binding | full `mlsc_current_validate` execution bar: record schema/version, every required field (source, pinned runtime identity, runner, executable, manifests, natives, run evidence), source binding, disk-validated runtime binding, recomputed file bindings (missing files rejected, never skipped), all gates pass, no foreign records | `Gate-A`, `missing field`, `foreign record` |
| 9 | no stale/fallback | SHA-256 only (no size/mtime fallback), no local-mode manifests, no extras | `release-candidate`, `Stale extra` |
| 10 | missing=>block | every absent input/evidence blocks first | `missing`, `required` |

## 5. Deployment-copy provenance

Because `dist/` is excluded from release archives, the validator never
assumes the deployment copy equals the build tree. Postinstall requires
the exact pinned runtime layout — launcher directly at the deployment
root (never nested under `payload_build/`), compiled executable beside
it, build/resource manifests alongside (the `BuildManifest` /
`ResourceManifest` arguments must be exactly those alongside files) —
and checks each packaged inventory file at its mapped runtime path
(staged `payload_build/<name>` deploys flat to `<name>`) by SHA-256; a
nested staging tree, foreign manifest paths, or a deploy-vs-package
diff blocks. Files outside the packaged inventory are
reported, never treated as proof, and no whole-directory
deployed-byte identity is claimed without checking.

## 6. What is NOT authorized here

No compiler invocation by tests, no live subject run, no `sbatch`, no
SSH/Slurm submission, no production execution, no `/usr/pubsw` copy,
no tarball, no commit/push/tag/publish/deploy. Gate A/B/C/D still need
separate human authorization.

## 7. Change record (anchor-guard hardening)

The reuse anchor was a `.git`-existence check (file in a linked
worktree, directory in a standalone checkout). That check is bypassable:
a bogus `.git` entry planted in a plain subdirectory under a clean
parent at the release commit, combined with conflicting
`GIT_DIR`/`GIT_WORK_TREE` overrides (which make unsanitized git report
the parent's pristine state), reused attacker content as the release
source. The guard is now strict top-level equality: the candidate's
canonical absolute path must equal the controlled
`git -C <candidate> rev-parse --show-toplevel` answer canonicalized the
same way (overrides stripped; every candidate-scoped git read in
`ensure_worktree` uses the same controlled environment). Legitimate
standalone checkouts (`.git` directory) and linked worktrees (`.git`
file) satisfy equality; plain subdirectories (parent match), errors,
and unexpected values refuse reuse as unverifiable. HEAD/tree/
porcelain/fingerprint/provenance checks are unchanged. Regression
`N13b` in `scripts/test_mlsc_release_gate.m` covers the exact bypass
plus standalone/worktree accept and subdir/invalid-metadata/wrong-commit
refuse cases as synthetic fixtures (throwaway repo only).

File identities (SHA-256) at the time of this change:

```
39ba99dc472b591ea2e8bcfabdde8e43251ecec95d9c45d298499e3e94c544cf  src/mlsc/mlsc_release_gate.m
f55d17d6b7311ca4eeee8e8d02e656cec295cf0a615bfae46e9eb179b0e2e6e8  scripts/test_mlsc_release_gate.m
```

Full targeted suite (`test_mlsc_release_gate`): 2 positive + 20
negative pass, including every `N13b` sub-case.
