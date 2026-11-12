function report = run_pseudo_CT(varargin)
%RUN_PSEUDO_CT Public pseudoCT MATLAB frontend; delegates to the compiled launcher.
%   REPORT = RUN_PSEUDO_CT('Profile', P, 'MPRAGE', FILE_OR_CELL, ...) validates
%   (default) or submits one request through bin/pseudoct validate|run.
%   MATLAB only parses the parameters, writes the launcher arguments, invokes
%   the launcher and displays its result. The scientific pipeline and the
%   validation are not executed in MATLAB.
%
%   Name-value parameters (case-insensitive):
%     Profile (required)       local, local-mprage-only, mlsc, mlsc-mprage-only
%     MPRAGE (required)        path, or cell of paths for a multi-subject request
%                              (not used by Action 'authenticate')
%     UMAP                     path (or cell, positionally paired); omit to autodiscover
%     Action                   'validate' (default), 'submit', or 'authenticate' (MLSC only,
%                              needs CredentialHandoff; logs in without processing inputs)
%     CorrectAliasing, RecenterBeforeNormalization, CleanupOnSuccess
%                              true/false or 'yes'/'no'; omit for the profile default
%     CurrentArtifactRoot      development-only override; MLSC profiles only (mlsc,
%                              mlsc-mprage-only). Local profiles reject it.
%     GroupAccount             MLSC account selection (not a secret)
%     HostKeyFile              MLSC strict host-key input
%     CredentialHandoff        existing single-use launcher handoff (MLSC submit or authenticate)
%     Runtime                  installed release label, for example R2010b
%     McrRoot                  Optional explicit MATLAB Runtime root (--mcr-root); omit for
%                              the release's catalog location
%     Launcher                 Installed distribution: omit it, or pass the bundled
%                              bin/pseudoct beside this file; any other path is refused
%                              with run_pseudo_CT:LauncherOverrideDevelopmentOnly. Source
%                              checkout only: development and test override for
%                              bin/pseudoct, otherwise PSEUDOCT_LAUNCHER is used.
%                              PSEUDOCT_LAUNCHER is never read in an installed distribution.
%   Passwords and user names are not accepted (use CredentialHandoff).
%
%   Launcher exit codes (REPORT.exit_code, same as bin/pseudoct --help): 0 validated,
%   completed or authenticated, 64 usage/config, 65 invalid request, 66 authentication, 67 submission
%   failure, 68 scientific failure/unverified, 69 launcher/runtime failure, 70 MATLAB
%   dispatch or runtime failure. CurrentArtifactRoot follows the same MLSC-only rule
%   in bin/pseudoct, the frontend and the headless API.
%
%   RUN_PSEUDO_CT() with no arguments opens the pseudoCT window: profile
%   selection, then the MPRAGE/UMAP window. Run checks the inputs and, when they
%   pass, executes the request (for MLSC it asks for the login after the check),
%   through the same launcher path as the arguments above. No separate validate
%   step is required. The
%   window stays open after each request, but MATLAB is busy while Run runs: the
%   launcher runs synchronously through system() (frontend/pseudo_CT_launch_request.m).
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
%LOCAL_OPEN_WINDOW Profile selection, then the window. No MATLAB Runtime root is
%   chosen here: the launcher resolves the selected release from the catalog
%   location (or --mcr-root), so the window never offers a folder picker.
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
context = struct('root_dir', root_dir, 'launcher', launcher, ...
    'runtime', selection.runtime, 'mcr_root', '');
load_mr_4_AC(config.io_policy.gui, config, context);
report.ok = true;
report.outcome = 'window_opened';
report.profile = selection.profile;
report.runtime = selection.runtime;
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
