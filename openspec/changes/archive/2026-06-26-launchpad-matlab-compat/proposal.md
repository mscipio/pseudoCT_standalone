# Proposal: Launchpad MATLAB Compatibility

## Intent

Two confirmed local-MATLAB-version bugs in the Launchpad pipeline, isolated by an A/B run on the same subject, the same compiled cluster binary, and the same MCR (R2010b). **Symptom 1:** pre-R2013a calls `strsplit` (R2013a+ only) at `run_launchpad_cmd_return.m:44` and crashes at job submission. **Symptom 2:** post-R2015a strict colon-operator enforcement errors at `nii2dcm_header_copy_vb20_david.m:82` because `for m=1:size(dicom_ref_all)` uses a non-scalar `size()` result. We fix both. We also add local-side diagnostics for a third, separately observed silent cluster/copy-back failure (root cause unknown, subject-specific, deferred) without claiming to fix it. The compiled `Pseudo_CT_launchpad` binary is out of scope (frozen external artifact).

**Context on the MATLAB floor:** the cluster's compiled `Pseudo_CT_launchpad` runs on MATLAB R2010b. Aligning the local-side minimum to R2010b keeps the supported range consistent with the cluster runtime, and the proposed `regexp`-based split is available since R14, so the backport is safe at the floor.

## Scope

### In Scope
- Backport `strsplit(jobnumline, '.')` to `regexp(jobnumline, '\.', 'split')` in `run_launchpad_cmd_return.m:44` (works R2007b+)
- Replace `for m=1:size(dicom_ref_all)` with `for m=1:numel(dicom_ref_all)` in `nii2dcm_header_copy_vb20_david.m:82` (works on every MATLAB release)
- After `scp_get` in `batch_pseudo_CT_launchpad.m:83-89`, verify `att_map.nii` is among the copied files; if absent, copy back the cluster job's stderr/log for diagnostics and set a clear per-subject failure message
- In `run_pseudo_CT_launchpad.m:129-135`, when `att_map.nii` is missing, print the subject path AND the temp_dir listing before incrementing `num_failed` (current `disp(ME.message)` is vague)
- Document the committed minimum MATLAB version (R2010b) in `run_pseudo_CT_launchpad.m` header and `defaults_pseudo_CT_launchpad.m`

### Out of Scope
- Rebuilding or introspecting the compiled `Pseudo_CT_launchpad` binary (frozen external artifact)
- The silent cluster/copy-back failure observed on subject `DPR_GWI007_DEP/MEMPRAGE_BC.nii` (R2026a log 2026-06-21) — root cause unknown, likely subject-specific; deferred to a possible follow-up `launchpad-pipeline-robustness` change
- Retry logic for cluster-failed subjects
- Changing DICOM output, QC, or att-map math
- The local (`run_pseudo_CT_local.m`) path (unaffected — both Symptoms 1 and 2 are Launchpad-only)

## Capabilities

### New Capabilities
- `launchpad-matlab-compat`: Local-side MATLAB version compatibility fixes for the Launchpad pipeline (pre-R2013a `strsplit` backport; post-R2015a `numel` colon fix), plus local-side diagnostics that surface cluster stderr to the operator when a cluster job exits 0 but does not produce the expected `att_map.nii`.

### Modified Capabilities
None — `batch-autodiscovery-observability` (UMAP/UTE discovery messages) is a distinct area; this change adds no spec-level requirement there.

## Approach

1. One-line regex backport in the submission helper (fully owned, low risk).
2. One-line `numel` fix in the post-cluster DICOM writer (fully owned, low risk; addresses Symptom 2 confirmed by A/B run).
3. In `batch_pseudo_CT_launchpad`, when `ss_tot(jj)==0` (job "succeeded") but `ls` of the copied-back files does not contain `att_map.nii`, run an extra `scp_get` for the cluster job's `.o*`/`.e*` PBS output files from `/pbs/<user>/` and print their head to stdout. This converts an opaque "Pseudo-CT processing finished without creating" into an actionable cluster-side clue for the deferred MEMPRAGE_BC-class failure.
4. Mirror the `fprintf`-to-stdout observability pattern already established by `batch-autodiscovery-observability` (messages survive `warning('off','all')`).

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `src/launchpad/run_launchpad_cmd_return.m:44` | Modified | `strsplit` → `regexp(...,'split')` |
| `src/io/nii2dcm_header_copy_vb20_david.m:82` | Modified | `1:size(dicom_ref_all)` → `1:numel(dicom_ref_all)` |
| `src/launchpad/batch_pseudo_CT_launchpad.m:83-94` | Modified | Post-scp att_map check + PBS log fetch |
| `run_pseudo_CT_launchpad.m:129-135` | Modified | Richer missing-output message |
| `run_pseudo_CT_launchpad.m` header; `src/config/defaults_pseudo_CT_launchpad.m` | Modified | Document min MATLAB R2010b |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| PBS log path/permission differs per cluster config | Med | Wrapped in try/catch; failure degrades to current opaque message, never crashes |
| `regexp` split returns cell of different shape than `strsplit` for edge inputs | Low | Both return cellstr split on single-char delimiter; verify with the known `jobnumline` format |
| Att_map check false-positive on filenames with `att_map` substring | Low | Match exact basename `att_map.nii` against the `ls` result |
| Other latent `1:size(struct)` patterns in bundled SPM8/imgaussian | Med | Out of scope: this change audits only `src/`; SPM8 is bundled and not modified; the `vers/` overrides already address the 3 known SPM8 issues. Subjects hitting SPM8 internals are blocked regardless of this change. |

## Rollback Plan

`git revert` the single commit. No config, data, or external-artifact changes.

## Dependencies

- Martinos Launchpad cluster access (existing, unchanged)
- `ssh2_v2_m1_r5` toolbox for extra PBS-row scp fetch (already on path)

## Success Criteria

- [ ] `run_launchpad_cmd_return` parses and runs on R2010b without `strsplit` reference
- [ ] Same subject that succeeds on R2013b runs to DICOM completion on R2026a (A/B reproducibility)
- [ ] No "Colon operands must be real scalars" error on R2026a for any owned-code path
- [ ] A job that exits 0 but produces no `att_map.nii` yields a stdout message naming the subject AND the head of the cluster stdout/stderr log (covers the deferred MEMPRAGE_BC-class failure)
- [ ] Min MATLAB version (R2010b) appears in the entry-script header and defaults file