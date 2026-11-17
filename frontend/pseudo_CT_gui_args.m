function args = pseudo_CT_gui_args(values, context, action)
%PSEUDO_CT_GUI_ARGS Name-value arguments for the shared bridge from GUI controls.
%   ARGS = PSEUDO_CT_GUI_ARGS(VALUES, CONTEXT, ACTION) maps the GUI state to
%   the same Name, Value list that run_pseudo_CT accepts, so the GUI and
%   argument mode build identical launcher requests.
%     VALUES: profile, mprage, umap ('' when none), aliasing, recenter,
%             cleanup (logical), gui_mode ('mMR' or 'mprage-only'),
%             optionally max_concurrent (subjects at once, 1-32; passed when > 1),
%             group_account, credential_handoff (path, '' when none), and optionally
%             subjects_file: a subjects-file path. When subjects_file is present and
%             not empty it is passed as 'Subject', FILE and mprage/umap are not used
%             (the window always runs through a subjects file).
%     CONTEXT: launcher, runtime, mcr_root ('' when not installed).
%     ACTION: 'validate', 'submit' or 'authenticate'.
%   Minimum supported MATLAB: R2010b.

if isfield(values, 'subjects_file') && ~isempty(values.subjects_file)
    args = {'Profile', values.profile, 'Subject', values.subjects_file};
else
    args = {'Profile', values.profile, 'MPRAGE', values.mprage};
end
args = [args, {'Action', action, 'Launcher', context.launcher, ...
    'CorrectAliasing', logical(values.aliasing), ...
    'RecenterBeforeNormalization', logical(values.recenter), ...
    'CleanupOnSuccess', logical(values.cleanup)}];
if ~(isfield(values, 'subjects_file') && ~isempty(values.subjects_file)) && ...
        ~strcmp(values.gui_mode, 'mprage-only') && ischar(values.umap) && ...
        ~isempty(values.umap)
    args = [args, {'UMAP', values.umap}];
end
if ~isempty(context.runtime)
    args = [args, {'Runtime', context.runtime}];
end
if ~isempty(context.mcr_root)
    args = [args, {'McrRoot', context.mcr_root}];
end
if isfield(values, 'max_concurrent') && ~isempty(values.max_concurrent) && ...
        values.max_concurrent > 1
    args = [args, {'MaxConcurrent', values.max_concurrent}];
end
if ~isempty(values.group_account)
    args = [args, {'GroupAccount', values.group_account}];
end
if ~isempty(values.credential_handoff)
    args = [args, {'CredentialHandoff', values.credential_handoff}];
end
end
