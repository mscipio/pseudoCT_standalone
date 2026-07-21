# Legacy Launchpad Parity

## Decision

Historical compatibility is defined by the observed production boundary, not by
a claim that every local R2010 run equals Launchpad. The controlled evidence
places the remaining sensitive boundary at SPM New Segment and the host
environment in which it runs.

For practical historical compatibility, retain the legacy defaults contract,
the production SPM overrides, bone cleanup, and the output settings listed
below. The compiled Launchpad backend remains unchanged.

## Recenter Correction

Actual Launchpad orchestration runs `mri_normalize` before invoking the compiled
pseudo-CT workflow and passes an `_normalized.nii` input. The processing code
therefore bypasses its recenter branch. The parity-correct setting is:

```matlab
recenter_before_normalization = 'No';
```

The earlier statement that `'Yes'` reproduced Launchpad behavior was incorrect.

## Controlled Provenance

The comparison held the pseudo-CT package, subject input, and New Segment job
constant. It compared the historical result with controlled R2010 execution on
the legacy PBS host environment and on celer. Compiled and interpreted R2010
runs were also compared on celer to remove compilation mode as the explanation
for the celer result.

For downstream stages, the comparison started from exact cleaned `rc*` inputs.
This removed upstream New Segment variation from DARTEL, inverse warp, reslice,
and final attenuation-map evaluation.

## New Segment Result

On the legacy PBS E5472/RHEL7/glibc 2.17 environment, the controlled New Segment
run matched the historical result exactly. On celer, R2010 compiled and
interpreted runs matched each other but followed a slightly different iterative
numerical path from the historical result.

This establishes a host-environment boundary for the controlled subject. It
does not identify whether CPU dispatch, glibc, another system-math component, or
an interaction among them causes the difference; those variables were not
isolated independently.

## Exact Downstream Results

Production bone cleanup remained enabled when the cleaned `rc*` inputs were
prepared. Starting from those exact inputs, the compared celer R2010 outputs
were byte-identical at each of these stages:

1. DARTEL.
2. Inverse warp.
3. Atlas reslice.
4. Final attenuation-map construction.

The final `att_map.nii` SHA-256 was:

```text
dc7f0e49016c6cf034b12df04eba78dd346b816f9976da63b8dfd792fdf255cb
```

## Required Settings

Use all of the following for the historical output policy:

- `recenter_before_normalization = 'No'`.
- Bone-segmentation reduction enabled (`cleanup = 1`).
- `zero_background = 'No'`.
- Production New Segment batch settings: `affreg = ''`, `biasfwhm = 30`, and
  `warp.reg = 10`.

The local entry point still loads the established `vers/` SPM compatibility
overrides. They are part of the supported local runtime, but the controlled
host-boundary finding does not attribute New Segment parity to those writer
overrides.

`zero_background = 'Yes'` is an explicit alternate output policy. It applies a
final subject mask locally, including as a post-fetch override for Launchpad,
and therefore does not reproduce the historical unmasked background.

## Limits

The evidence covers one controlled subject. It is not universal parity proof,
does not establish CPU-versus-glibc causality, and does not replace a real
end-to-end run. Operators must still inspect the generated QC TIFF and perform
the normal manual output checks.

## Future Architecture

A unified `run_pseudo_CT.m` entry point with argument- and GUI-selectable
execution and processing profiles is intentionally deferred. That work must
start as a fresh full `sdd-new` and include the complete legacy Launchpad path;
this cleanup does not introduce root configuration or profile APIs.
