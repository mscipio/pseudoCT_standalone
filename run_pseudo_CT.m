function report = run_pseudo_CT(varargin)
%RUN_PSEUDO_CT Public pseudoCT MATLAB frontend; delegates to the compiled launcher.
%   REPORT = RUN_PSEUDO_CT('Profile', P, 'MPRAGE', FILE_OR_CELL, ...) validates
%   (default) or submits one request through bin/pseudoct run validate|run.
%   MATLAB only parses the parameters, writes the launcher arguments, invokes
%   the launcher and displays its result. The scientific pipeline and the
%   validation are not executed in MATLAB.
%
%   Name-value parameters (case-insensitive):
%     Profile (required)       local, local-mprage-only, mlsc, mlsc-mprage-only
%     MPRAGE (required)        path, or cell of paths for a multi-subject request
%     UMAP                     path (or cell, positionally paired); omit to autodiscover
%     Action                   'validate' (default) or 'submit'
%     CorrectAliasing, RecenterBeforeNormalization, CleanupOnSuccess
%                              true/false or 'yes'/'no'; omit for the profile default
%     CurrentArtifactRoot      compiled-artifact validation override
%     GroupAccount             MLSC account selection (not a secret)
%     HostKeyFile              MLSC strict host-key input
%     CredentialHandoff        existing single-use launcher handoff (MLSC submit only)
%     Runtime                  installed release label, for example R2010b
%     McrRoot                  MATLAB Runtime root for the selected release
%     Launcher                 path to bin/pseudoct; default: the bin/pseudoct beside
%                              this file (installed distribution), else PSEUDOCT_LAUNCHER
%   Passwords and user names are not accepted (use CredentialHandoff).
%
%   RUN_PSEUDO_CT() with no arguments opens the pseudoCT window: profile
%   selection, then the MPRAGE/UMAP window. Validate and Submit call the same
%   launcher path as the arguments above. The window stays open after each
%   submission and does not block MATLAB.
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(mfilename('fullpath'));
% Shared helpers: the password dialog and its tools, and the credential store,
% are the src/ originals in a source checkout and package copies in an installed
% distribution. The frontend folder goes first so its window files win.
shared_dirs = {fullfile(root_dir, 'src', 'api'); fullfile(root_dir, 'src', 'gui'); ...
    fullfile(root_dir, 'src', 'gui', 'passwordTools'); ...
    fullfile(root_dir, 'frontend', 'passwordTools'); fullfile(root_dir, 'frontend')};
for ii = 1:length(shared_dirs)
    if exist(shared_dirs{ii}, 'dir') == 7
        addpath(shared_dirs{ii}, '-begin');
    end
end
if nargin == 0
    report = local_open_window(root_dir);
    return;
end

request = pseudo_CT_launch_request('parse', varargin, root_dir);
report = pseudo_CT_launch_request('invoke', request);
local_print_report(report);
end

function report = local_open_window(root_dir)
%LOCAL_OPEN_WINDOW Profile selection, runtime and MCR root, then the window.
launcher = pseudo_CT_launch_request('launcher', '', root_dir);
selection = pseudo_CT_profile_selector(launcher);
report = struct('ok', false, 'outcome', 'cancelled', 'profile', '', ...
    'runtime', '', 'action', 'window', 'exit_code', 0, ...
    'submission_status', 'not_attempted', 'authentication_status', 'not_attempted', ...
    'dispatch_status', 'not_dispatched', 'error_code', '', 'error_message', '', ...
    'job_ids', {{}});
if isempty(selection.profile)
    return;
end
profiles = pseudo_CT_profile_choices();
config = profiles(strcmp({profiles.name}, selection.profile)).config;
mcr_root = '';
if ~isempty(selection.runtime)
    mcr_root = local_mcr_root(selection.runtime);
    if isempty(mcr_root)
        mcr_root = uigetdir('', ['Select the MATLAB Runtime root for ' ...
            selection.runtime]);
        if isequal(mcr_root, 0) || isempty(mcr_root)
            return;
        end
    end
end
context = struct('root_dir', root_dir, 'launcher', launcher, ...
    'runtime', selection.runtime, 'mcr_root', mcr_root);
load_mr_4_AC(config.io_policy.gui, config, context);
report.ok = true;
report.outcome = 'window_opened';
report.profile = selection.profile;
report.runtime = selection.runtime;
end

function mcr_root = local_mcr_root(label)
%LOCAL_MCR_ROOT Per-release, then global, MATLAB Runtime root from the environment.
mcr_root = strtrim(getenv(['PSEUDOCT_MCR_ROOT_' label]));
if isempty(mcr_root)
    mcr_root = strtrim(getenv('PSEUDOCT_MCR_ROOT'));
end
end

function local_print_report(report)
if report.ok
    verdict = 'SUCCESS';
else
    verdict = 'FAILURE';
end
fprintf('run_pseudo_CT %s %s: %s\n', report.action, report.profile, verdict);
fprintf('  outcome: %s (exit %d)\n', report.outcome, report.exit_code);
fprintf('  submission: %s  authentication: %s  dispatch: %s\n', ...
    report.submission_status, report.authentication_status, report.dispatch_status);
if ~isempty(report.error_code)
    fprintf('  error: %s %s\n', report.error_code, report.error_message);
elseif ~isempty(report.error_message)
    fprintf('  error: %s\n', report.error_message);
end
if isempty(report.job_ids)
    fprintf('  job ids: none\n');
else
    fprintf('  job ids: %s\n', sprintf('%s ', report.job_ids{:}));
end
end
