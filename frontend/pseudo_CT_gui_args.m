function args = pseudo_CT_gui_args(values, context, action)
%PSEUDO_CT_GUI_ARGS Name-value arguments for the shared bridge from GUI controls.
%   ARGS = PSEUDO_CT_GUI_ARGS(VALUES, CONTEXT, ACTION) maps the GUI state to
%   the same Name, Value list that run_pseudo_CT accepts, so the GUI and
%   argument mode build identical launcher requests.
%     VALUES: profile, mprage, umap ('' when none), aliasing, recenter,
%             cleanup (logical), gui_mode ('mMR' or 'mprage-only'),
%             group_account, credential_handoff (path, '' when none).
%     CONTEXT: launcher, runtime, mcr_root ('' when not installed).
%     ACTION: 'validate' or 'submit'.
%   Minimum supported MATLAB: R2010b.

args = {'Profile', values.profile, 'MPRAGE', values.mprage, ...
    'Action', action, 'Launcher', context.launcher, ...
    'CorrectAliasing', logical(values.aliasing), ...
    'RecenterBeforeNormalization', logical(values.recenter), ...
    'CleanupOnSuccess', logical(values.cleanup)};
if ~strcmp(values.gui_mode, 'mprage-only') && ischar(values.umap) && ...
        ~isempty(values.umap)
    args = [args, {'UMAP', values.umap}];
end
if ~isempty(context.runtime)
    args = [args, {'Runtime', context.runtime}];
end
if ~isempty(context.mcr_root)
    args = [args, {'McrRoot', context.mcr_root}];
end
if ~isempty(values.group_account)
    args = [args, {'GroupAccount', values.group_account}];
end
if ~isempty(values.credential_handoff)
    args = [args, {'CredentialHandoff', values.credential_handoff}];
end
end
