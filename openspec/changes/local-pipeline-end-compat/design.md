# Design: Local Pipeline End-of-Run QC Compatibility Fix

## Technical Approach

Replace the local (non-deployed) `figure/imagesc/print/pause(1)/close` validation-image block in `atlas_based_attenuation_map.m` with the `imwrite(...'Resolution',300)` call already proven in the deployed branch. The composite from `quick_fusion_pseudo_ct` is an RGB matrix (via `toverlay2`), so `imwrite` is a direct semantic replacement — no figure rendering, no event loop, no graphics dependence. This unifies the local and deployed paths on a single I/O primitive and eliminates the entire class of MATLAB web-axes interaction bugs.

## Architecture Decisions

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Remove `pause(1)` only | Smallest diff; leaves `figure/print/close` in place — still vulnerable to future graphics API changes | Rejected |
| Add `verLessThan` guard around `pause` | Band-aid; requires guessing version cutoff; doesn't fix root cause | Rejected |
| Unify on `imwrite` | 5-line removal + 1-line insertion; proven in deployed branch; eliminates graphics dependency entirely; `imwrite` `'Resolution'` available since R2009b (predates R2010b floor) | **Chosen** |

**Rationale**: The deployed branch has used `imwrite` on the same RGB composite since v2.0 (Dec/2014) — zero reported TIFF issues across R2010b–R2026a. The graphics-based path is unnecessary for a pre-computed RGB matrix. Removing the entire graphics block is the smallest safe change that also hardens against future MATLAB UI changes.

## Data Flow

```
quick_fusion_pseudo_ct(paths)
    → composite (RGB M×N×3 double)
        → imwrite(composite, paths/Fusion_MR_Pseudo_CT_validation.tiff, 'Resolution', 300)
            → 300 DPI TIFF on disk
```

No intermediate figure, no `drawnow`, no `pause`, no `close`. The RGB data flows directly from `toverlay2` tiling to disk I/O.

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `src/core/atlas_based_attenuation_map.m` | Modify | Replace lines 661–669 (`if ~isdeployed` … `else` … `end`) with `imwrite(composite, fullfile(paths, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'Resolution', 300);` |

**Exact diff (5 removals, 1 addition):**

```matlab
% BEFORE (lines 661-669):
if ~isdeployed
    hhh = figure('Visible', 'off'); imagesc(composite);
    drawnow;
    print(hhh, '-dtiff', '-r300', fullfile(paths, 'Fusion_MR_Pseudo_CT_validation.tiff'));
    pause(1);
    close(hhh);
else
    imwrite(composite, fullfile(paths, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'Resolution', 300);
end

% AFTER:
imwrite(composite, fullfile(paths, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'Resolution', 300);
```

## Interfaces / Contracts

No interface changes. The function boundary (`atlas_based_attenuation_map` inputs: `P, dir_batch_templates, ssh_log, correct_aliasing, defaults`; output: `Pf`) is unchanged. The TIFF filename, format, and pixel content are preserved. The only output difference is the metadata mechanism: `imwrite` sets XResolution/YResolution via the TIFF `Resolution` parameter rather than via `print -dtiff -r300`, but both produce 300 DPI tags.

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Smoke (parse) | File parses after edit | `run('scripts/run_smoke_tests.m')` — already covers `atlas_based_attenuation_map.m` parse check |
| Lint | No new warnings | `run('scripts/run_lint.m')` |
| Manual E2E | TIFF produced without error on R2026a | Run `run_pseudo_CT_local('batch')` on one real subject, confirm no `InteractionsManager` error |
| Manual E2E | TIFF produced without error on R2010b-class runtime | Run on cluster, confirm pipeline completes and QC TIFF is visibly correct |
| Manual visual | Output matches prior path | Compare `Fusion_MR_Pseudo_CT_validation.tiff` pixel content and DPI metadata against a known-good run from the old code |

## Migration / Rollout

No data migration required. The output filename and pixel content are semantically identical. Rollback is a single `git revert` of the one-file change.

## Open Questions

None.
