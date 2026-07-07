# Proposal: Local Pipeline End-of-Run QC Compatibility Fix

## Intent

On MATLAB R2026a, the local (non-deployed) QC output block in `atlas_based_attenuation_map.m` throws an `InteractionsManager/registerInteraction` error during `pause(1)` after the validation TIFF is already written. The pipeline completes and produces correct outputs, but the error is noisy, looks like a failure, and is fragile against future MATLAB graphics changes. The fix must keep the package running cleanly across R2010b→R2026a.

## Scope

### In Scope
- Replace the `figure/imagesc/print/pause(1)/close` QC block in the `~isdeployed` branch of `atlas_based_attenuation_map.m` (~lines 662-666) with the `imwrite(...,'Resolution',300)` call already proven in the `isdeployed` branch.
- Preserve the output filename `Fusion_MR_Pseudo_CT_validation.tiff` and the 300 DPI intent.
- Keep all preceding/following logic (`quick_fusion_pseudo_ct`, `att_map.nii` write, version file) untouched.

### Out of Scope
- Touching the earlier `spm('CreateIntWin','on')` / `close(fh)` window (separate, unconfirmed risk).
- Changing QC content, color mapping, or `quick_fusion_pseudo_ct` internals.
- Launchpad path (already uses `imwrite`).
- Any feature work; this is compat-only.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
None.

> Pure implementation/compat fix. No spec-level behavior changes; existing `launchpad-matlab-compat` spec covers the Launchpad local-side only, not this local-pipeline QC block.

## Approach

Unify the local and deployed QC output paths on `imwrite`. The composite from `quick_fusion_pseudo_ct` is already RGB (via `toverlay2`), so `imwrite` is a direct semantic replacement and removes the hidden figure, event-loop trigger, and `pause` entirely. Eliminates the whole class of web-axes interaction bugs rather than patching one line.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `src/core/atlas_based_attenuation_map.m` | Modified | `~isdeployed` QC block (~lines 662-666) switched to `imwrite` |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `imwrite` TIFF metadata/DPI differs from `print -dtiff -r300` on old MATLAB | Low | Pixels identical; DPI metadata not used downstream; deployed branch already relies on this path |
| `pause(1)` masked a latent `close(fh)` interaction bug | Low | `fh` is older-style figure, separate block; verify end-to-end on real subject |
| No automated test exercises QC TIFF | Med | Manual run on one subject is mandatory (smoke tests are parse-only) |

## Rollback Plan

Revert the single block in `atlas_based_attenuation_map.m` to the original `figure/imagesc/print/pause(1)/close` sequence. No other files change, so a one-file `git revert` restores prior behavior.

## Dependencies

- None beyond the existing MATLAB/SPM8 runtime floor (R2010b+).

## Success Criteria

- [ ] Local pipeline run on R2026a completes with no `InteractionsManager` error after the QC TIFF write.
- [ ] `Fusion_MR_Pseudo_CT_validation.tiff` is produced and visibly correct on one real subject.
- [ ] Run on the cluster's R2010b-class runtime still produces the TIFF without error.
- [ ] `run_smoke_tests.m` and `run_lint.m` pass.

## Proposal Question Round (assumptions)

Assumed without blocking: DPI metadata fidelity is non-critical (no downstream consumer reads it); the `close(fh)` block is out of scope and must stay unchanged. Confirm or correct before specs.