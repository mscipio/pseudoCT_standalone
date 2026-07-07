## Exploration: MATLAB 2026a compatibility error at end of local pipeline

### Current State

Near the end of `atlas_based_attenuation_map.m`, after the attenuation map is written and the QC composite image is generated, the local (non-deployed) path creates a hidden figure, prints it to TIFF, pauses, then closes the figure:

```matlab
hhh = figure('Visible', 'off'); imagesc(composite);
drawnow;
print(hhh, '-dtiff', '-r300', fullfile(paths, 'Fusion_MR_Pseudo_CT_validation.tiff'));
pause(1);
close(hhh);
```

On MATLAB R2026a, `pause(1)` triggers the event loop, which causes `matlab.graphics.interaction.graphicscontrol.InteractionsManager/registerInteraction` to throw:

> `Error using + Invalid type of input arguments (should be uint64)`

The `print` call already succeeds — the TIFF is written — so the error is purely during post-print cleanup. The pipeline then continues to write the version file and finish normally.

The deployed branch already bypasses this entire graphics path by using `imwrite(composite, ..., 'Resolution', 300)`, which is a clue that the figure-based approach is problematic in non-interactive contexts.

### Affected Areas

- `src/core/atlas_based_attenuation_map.m` — lines 661-666: the hidden-figure creation, `print`, `pause(1)`, and `close` sequence that triggers the error.
- `src/qc/quick_fusion_pseudo_ct.m` — returns the 2D RGB composite matrix used as input to the figure; it does not create figures itself.
- `run_pseudo_CT_local.m` — dispatches to the local path where `isdeployed` is false, so the buggy branch is always taken.

No version guards (`verLessThan`, `spm_check_version`) exist in project source code for graphics operations. The project targets MATLAB R2010b+.

### Approaches

1. **Remove `pause(1)` only** — delete the single line after `print`.
   - Pros: smallest possible change, fixes the immediate R2026a error, `print` is synchronous so the pause is likely unnecessary.
   - Cons: does not prevent similar interaction bugs from `close(hhh)` or future graphics changes; if pause was masking an old-MATLAB flush issue, we could regress on ancient versions.
   - Effort: Low

2. **Unify local and deployed QC paths using `imwrite`** — replace the `figure/imagesc/print/pause/close` block with the `imwrite` path already used in the `isdeployed` branch.
   - Pros: eliminates the entire graphics subsystem from the QC output step, already proven in compiled mode, most robust across all MATLAB versions, no hidden figure or event-loop side effects.
   - Cons: `imwrite` TIFF `'Resolution'` parameter may not set DPI metadata identically to `print -dtiff -r300` in very old MATLAB, but the image pixels are identical. Slightly larger change (~4 lines).
   - Effort: Low

3. **Add `verLessThan` guard around `pause(1)`** — keep pause only on older MATLAB releases.
   - Pros: preserves historical behavior if it mattered.
   - Cons: band-aid, requires guessing an exact version cutoff, does not fix the underlying incompatibility class.
   - Effort: Low

### Recommendation

**Approach 2: unify the QC output to `imwrite`.**

The composite matrix returned by `quick_fusion_pseudo_ct` is already RGB (via `toverlay2`), so `imwrite` is a direct semantic replacement. The deployed branch has been using this successfully. This removes the hidden figure, `imagesc`, `print`, `pause`, and `close` from the local path entirely, making the pipeline immune to modern MATLAB graphics interaction changes. It is the safest fix for a project that must run on R2010b through R2026a.

If the user insists on the absolute smallest change, Approach 1 (remove `pause(1)`) is acceptable as a quick patch, but it leaves the door open for future graphics event-loop issues.

### Risks

- The `fh` SPM Interactive window is still created earlier (`spm('CreateIntWin','on')`) and closed later (`close(fh)`). If `pause(1)` was masking an analogous interaction bug on `fh`, we could see a similar error after closing that window. However, `fh` is an older-style figure and less likely to trigger web-based axes interactions.
- Smoke tests cover file/parse integrity only; they do not exercise the figure path. Manual end-to-end verification on a real subject is required to confirm the QC TIFF still renders correctly.
- If we keep the figure path but remove pause, `close(hhh)` could still trigger graphics events if a `drawnow` is called elsewhere in the call stack, though this is unlikely.

### Ready for Proposal

Yes. The orchestrator should tell the user that the root cause is `pause(1)` interacting with modern MATLAB's web-based axes event loop, and that the recommended fix is to switch the local QC branch to `imwrite` (matching the already-deployed branch). The change is low-effort, low-risk, and preserves output semantics.
