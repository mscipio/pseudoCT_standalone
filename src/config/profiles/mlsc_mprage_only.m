function config = mlsc_mprage_only()
%MLSC_MPRAGE_ONLY MLSC current-lineage MPRAGE-only profile.
%   Reuse MLSC-CURRENT's artifact and scheduler contract; only the input,
%   output, and GUI policies differ.

config = mlsc_current();

% MPRAGE-only collection needs no UMAP reference and produces NIfTI only.
config.io_policy.reference = 'none';
config.io_policy.output = 'nifti-only';
config.io_policy.gui = 'mprage-only';
config.compatibility_profile = 'mlsc-current';

% Human-facing selector metadata; runtime identity remains filename-derived.
config.presentation.display_name = 'MPRAGE-only — MLSC';
config.presentation.description = ...
    'Generate a NIfTI-only pseudoCT from MPRAGE alone on MLSC. No UMAP required.';
config.presentation.group = 'specialized';
config.presentation.recommended = false;
config.presentation.order = 20;
end
