function test_frontend_launch()
%TEST_FRONTEND_LAUNCH Offline checks of the MATLAB frontend delegation.
%   Covers parameter-to-argument translation, quoting of hostile paths, the
%   child environment, secret rejection, result handling, multi-subject config
%   and fingerprint gating. A stub launcher (bash) stands in for bin/pseudoct,
%   so no science, MLSC contact or MATLAB Runtime is used. The optional real
%   check runs only when PSEUDOCT_FRONTEND_TEST_LAUNCHER and
%   PSEUDOCT_FRONTEND_TEST_MPRAGE name an installed launcher and a readable
%   MPRAGE; it validates only.

if ~isunix
    fprintf('  SKIP  test_frontend_launch (requires a POSIX shell)\n');
    return;
end
repo = fileparts(fileparts(mfilename('fullpath')));
old_path = path();
cleanup_path = onCleanup(@() path(old_path)); %#ok<NASGU>
addpath(repo, '-begin');
addpath(fullfile(repo, 'frontend'), '-begin');

scratch_root = getenv('PSEUDOCT_TEST_SCRATCH');
if isempty(scratch_root)
    scratch_root = tempdir;
end
work = tempname(scratch_root);
mkdir(work);
cleanup_work = onCleanup(@() local_remove_tree(work)); %#ok<NASGU>
old_cwd = pwd;
cleanup_cwd = onCleanup(@() cd(old_cwd)); %#ok<NASGU>
cd(work);

% Hostile but legal names: spaces, apostrophe, command substitution, quote.
spaced = fullfile(work, 'scan dir', 'it''s $(touch pwned) MPRAGE.dcm');
second = fullfile(work, 'scan dir', 'q"uote MPRAGE 2.dcm');
umap = fullfile(work, 'umap dir', 'UMAP 1.dcm');
umap2 = fullfile(work, 'umap dir', 'UMAP 2.dcm');
mkdir(fileparts(spaced));
mkdir(fileparts(umap));
local_write(spaced, {'mprage bytes'});
local_write(second, {'mprage bytes 2'});
local_write(umap, {'umap bytes'});
local_write(umap2, {'umap bytes 2'});
handoff = fullfile(work, 'handoff file.mat');
local_write(handoff, {'synthetic handoff placeholder'});
mcr_root = fullfile(work, 'mcr root');
mkdir(mcr_root);

stub_dir = fullfile(work, 'stub dir''s');
mkdir(stub_dir);
stub = fullfile(stub_dir, 'pseudoct stub');
fail_stub = fullfile(stub_dir, 'pseudoct fail stub');
local_write(stub, { ...
    '#!/bin/bash'; ...
    'printf ''%s\n'' "$@" > "$PSEUDOCT_STUB_ARGV"'; ...
    'printf ''LD_LIBRARY_PATH=%s\n'' "${LD_LIBRARY_PATH-unset}" >> "$PSEUDOCT_STUB_ARGV"'; ...
    'echo ''{"type":"result","outcome":"validation_succeeded","submission_status":"not_attempted","authentication_status":"not_attempted","dispatch_status":"not_dispatched","backend":"local","job_ids":[],"error_code":null,"error_message":null,"exit_code":0}'''; ...
    'exit 0'});
local_write(fail_stub, { ...
    '#!/bin/bash'; ...
    'echo ''{"type":"result","outcome":"validation_failed","submission_status":"not_attempted","authentication_status":"not_attempted","dispatch_status":"not_dispatched","backend":"local","job_ids":[],"error_code":"INVALID_REQUEST","error_message":"synthetic rejection","exit_code":65}''';  ...
    'exit 65'});
system(['chmod +x ' local_sh(stub) ' ' local_sh(fail_stub)]);
argv_file = fullfile(work, 'argv.txt');
old_argv_env = getenv('PSEUDOCT_STUB_ARGV');
setenv('PSEUDOCT_STUB_ARGV', argv_file);
cleanup_env = onCleanup(@() setenv('PSEUDOCT_STUB_ARGV', old_argv_env)); %#ok<NASGU>

% 1. Parameter-to-argument translation (exact argument list).
request_args = {'Profile', 'local', 'MPRAGE', spaced, 'UMAP', umap, ...
    'Action', 'submit', 'Runtime', 'R2010b', 'McrRoot', mcr_root, ...
    'Launcher', stub, 'CorrectAliasing', false, 'CleanupOnSuccess', 'yes', ...
    'CredentialHandoff', handoff};
req = pseudo_CT_launch_request('parse', request_args, repo);
argv = pseudo_CT_launch_request('argv', req);
expected = {'run', '--mcr', 'R2010b', '--mcr-root', mcr_root, 'run', ...
    '--profile', 'local', '--mprage', spaced, '--umap', umap, ...
    '--correct-aliasing', 'no', '--cleanup-on-success', 'yes', ...
    '--credential-handoff', handoff, '--format', 'jsonl'};
assert(isequal(argv, expected), 'Frontend argument translation changed.');

% 2. Secrets and malformed parameters are rejected before any launch.
local_expect('pseudo_CT:FrontendSecretArgument', @() local_parse({'Profile', 'local', ...
    'MPRAGE', spaced, 'Password', 'x'}, repo));
local_expect('pseudo_CT:FrontendSecretArgument', @() local_parse({'Profile', 'local', ...
    'MPRAGE', spaced, 'Username', 'x'}, repo));
local_expect('pseudo_CT:FrontendSecretArgument', @() local_parse({'Profile', 'local', ...
    'MPRAGE', spaced, 'Token', 'x'}, repo));
local_expect('pseudo_CT:FrontendUsage', @() local_parse({'Profile', 'local', ...
    'MPRAGE'}, repo));
local_expect('pseudo_CT:FrontendUsage', @() local_parse({'Profile', 'local', ...
    'MPRAGE', spaced, 'Action', 'run'}, repo));
local_expect('pseudo_CT:InvalidProfile', @() local_parse({'Profile', 'local_typo', ...
    'MPRAGE', spaced}, repo));
local_expect('pseudo_CT:OrchestrationInput', @() local_parse({'Profile', 'local', ...
    'MPRAGE', fullfile(work, 'missing.dcm')}, repo));
local_expect('pseudo_CT:OrchestrationInput', @() local_parse({'Profile', 'local', ...
    'MPRAGE', {spaced, second}, 'UMAP', {umap}}, repo));
% CurrentArtifactRoot is a development-only override accepted for the MLSC profiles
% only; the local profiles are refused with the shared identifier.
local_expect('run_pseudo_CT:InvalidMlscCurrentOverride', @() local_parse({'Profile', ...
    'local', 'MPRAGE', spaced, 'CurrentArtifactRoot', work}, repo));
local_expect('run_pseudo_CT:InvalidMlscCurrentOverride', @() local_parse({'Profile', ...
    'local-mprage-only', 'MPRAGE', spaced, 'CurrentArtifactRoot', work}, repo));
mlsc_override = local_parse({'Profile', 'mlsc', 'MPRAGE', spaced, ...
    'CurrentArtifactRoot', work, 'Launcher', stub}, repo);
assert(strcmp(mlsc_override.artifact_root, work), ...
    'The MLSC profile must keep the development-only CurrentArtifactRoot.');
old_launcher_env = getenv('PSEUDOCT_LAUNCHER');
cleanup_launcher_env = onCleanup(@() setenv('PSEUDOCT_LAUNCHER', old_launcher_env)); %#ok<NASGU>
setenv('PSEUDOCT_LAUNCHER', '');
local_expect('pseudo_CT:FrontendLauncher', @() local_parse({'Profile', 'local', ...
    'MPRAGE', spaced}, repo));

% 3. Invocation through the stub: the arguments arrive exactly, the child has
%    no MATLAB runtime library variable, the hostile path does not execute.
old_ld = getenv('LD_LIBRARY_PATH');
cleanup_ld = onCleanup(@() setenv('LD_LIBRARY_PATH', old_ld)); %#ok<NASGU>
setenv('LD_LIBRARY_PATH', fullfile(work, 'matlab', 'runtime', 'glnxa64'));
result = pseudo_CT_launch_request('invoke', req);
assert(result.ok && result.exit_code == 0, 'The stub validation did not succeed.');
assert(strcmp(result.outcome, 'validation_succeeded'));
assert(strcmp(result.submission_status, 'not_attempted'));
assert(strcmp(result.authentication_status, 'not_attempted'));
assert(strcmp(result.dispatch_status, 'not_dispatched'));
assert(isempty(result.error_code) && isempty(result.job_ids));
lines = local_lines(argv_file);
assert(strcmp(lines{end}, 'LD_LIBRARY_PATH=unset'), ...
    'MATLAB library path leaked into the launcher environment.');
assert(isequal(lines(1:end - 1), argv), 'Launcher argv differs from the request.');
for kk = 1:numel(lines)
    assert(isempty(strfind(lower(lines{kk}), 'password')) && ...
        isempty(strfind(lower(lines{kk}), 'username')), ...
        'A credential-like token reached the launcher argv.');
end
assert(exist(fullfile(work, 'pwned'), 'file') ~= 2, ...
    'A hostile path was executed by the shell.');

% 4. A launcher rejection is reported as a failure with its error code.
req_fail = pseudo_CT_launch_request('parse', {'Profile', 'local', 'MPRAGE', spaced, ...
    'Launcher', fail_stub}, repo);
failed = pseudo_CT_launch_request('invoke', req_fail);
assert(~failed.ok && failed.exit_code == 65);
assert(strcmp(failed.outcome, 'validation_failed'));
assert(strcmp(failed.error_code, 'INVALID_REQUEST'));
assert(strcmp(failed.error_message, 'synthetic rejection'));

% 5. Multi-subject requests use a JSON config with escaped paths.
req_multi = pseudo_CT_launch_request('parse', {'Profile', 'local', ...
    'MPRAGE', {spaced, second}, 'UMAP', {umap, umap2}, 'Launcher', stub}, repo);
config_text = pseudo_CT_launch_request('config', req_multi);
assert(~isempty(strfind(config_text, '"mprage": [')));
assert(~isempty(strfind(config_text, '"umap": [')));
assert(~isempty(strfind(config_text, strrep(second, '"', '\"'))));
multi_argv = pseudo_CT_launch_request('argv', req_multi, fullfile(work, 'job.json'));
assert(any(strcmp(multi_argv, '--config')) && ~any(strcmp(multi_argv, '--mprage')));

% 6. Fingerprints identify one set of inputs and options.
fp_a = pseudo_CT_launch_request('fingerprint', req);
fp_b = pseudo_CT_launch_request('fingerprint', pseudo_CT_launch_request('parse', ...
    request_args, repo));
assert(strcmp(fp_a, fp_b), 'Identical inputs must give the same fingerprint.');
fp_option = pseudo_CT_launch_request('fingerprint', pseudo_CT_launch_request('parse', ...
    {'Profile', 'local', 'MPRAGE', spaced, 'UMAP', umap, 'Launcher', stub, ...
    'CorrectAliasing', true}, repo));
assert(~strcmp(fp_a, fp_option), 'A changed option must change the fingerprint.');
local_write(spaced, {'mprage bytes changed on disk'});
fp_file = pseudo_CT_launch_request('fingerprint', pseudo_CT_launch_request('parse', ...
    request_args, repo));
assert(~strcmp(fp_a, fp_file), 'A changed input file must change the fingerprint.');

% 6b. Submit uses the same fingerprint as its validation (action and handoff
%     are not inputs), so a validated request can be submitted unchanged.
fp_submit = pseudo_CT_launch_request('fingerprint', pseudo_CT_launch_request('parse', ...
    [request_args, {'Action', 'submit'}], repo));
% fp_file is the fingerprint of the current inputs (after the file change above).
assert(strcmp(fp_file, fp_submit), 'Submit must share the validated fingerprint.');

% 6c. GUI state machine: Submit only after a successful validation of exactly
%     the current inputs; busy disables both; a changed fingerprint disables Submit.
state = pseudo_CT_gui_state('', [], false);
assert(~state.validate_enabled && ~state.submit_enabled);
state = pseudo_CT_gui_state(fp_file, [], false);
assert(state.validate_enabled && ~state.submit_enabled);
ok_validation = struct('fingerprint', fp_file, 'ok', true);
state = pseudo_CT_gui_state(fp_file, ok_validation, false);
assert(state.validate_enabled && state.submit_enabled);
state = pseudo_CT_gui_state(fp_option, ok_validation, false);
assert(~state.submit_enabled, 'A changed option must disable Submit.');
state = pseudo_CT_gui_state(fp_file, struct('fingerprint', fp_file, 'ok', false), false);
assert(~state.submit_enabled, 'A failed validation must not enable Submit.');
state = pseudo_CT_gui_state(fp_file, ok_validation, true);
assert(~state.validate_enabled && ~state.submit_enabled, 'Busy must disable both.');

% 6d. GUI arguments and argument mode produce the same launcher argv.
gui_values = struct('profile', 'local', 'mprage', spaced, 'umap', umap, ...
    'aliasing', false, 'recenter', false, 'cleanup', true, ...
    'gui_mode', 'mMR', 'group_account', '', 'credential_handoff', '');
gui_context = struct('launcher', stub, 'runtime', '', 'mcr_root', '');
gui_args = pseudo_CT_gui_args(gui_values, gui_context, 'validate');
arg_mode_args = {'Profile', 'local', 'MPRAGE', spaced, 'UMAP', umap, ...
    'Action', 'validate', 'Launcher', stub, 'CorrectAliasing', false, ...
    'RecenterBeforeNormalization', false, 'CleanupOnSuccess', true};
assert(isequal(pseudo_CT_launch_request('argv', pseudo_CT_launch_request('parse', ...
    gui_args, repo)), pseudo_CT_launch_request('argv', pseudo_CT_launch_request('parse', ...
    arg_mode_args, repo))), 'GUI and argument mode must build the same argv.');
gui_submit = pseudo_CT_gui_args(setfield(gui_values, 'credential_handoff', handoff), ...
    setfield(gui_context, 'runtime', 'R2010b'), 'submit');
assert(any(strcmp(gui_submit, 'CredentialHandoff')) && any(strcmp(gui_submit, 'Runtime')));

% 6e. Installed release list (synthetic installed root with a stub launcher).
installed_root = fullfile(work, 'installed root');
mkdir(fullfile(installed_root, 'bin'));
mkdir(fullfile(installed_root, 'runtimes'));
installed_stub = fullfile(installed_root, 'bin', 'pseudoct');
local_write(installed_stub, { ...
    '#!/bin/bash'; ...
    'if [ "$1" = "--list-releases" ]; then printf ''R2010b\t7.14\tdefault\nR2014b\t8.4\t-\n''; exit 0; fi'; ...
    'exit 64'});
system(['chmod +x ' local_sh(installed_stub)]);
releases = pseudo_CT_launch_request('releases', installed_stub);
assert(numel(releases) == 2 && strcmp(releases(1).label, 'R2010b') && ...
    strcmp(releases(1).mcr_version, '7.14') && releases(1).default && ~releases(2).default);
assert(isempty(pseudo_CT_launch_request('releases', stub)), ...
    'A launcher without runtimes/ must list no releases.');

% 6h. Launcher resolution: an installed distribution (no src/) always uses its packaged
%     bin/pseudoct, ignores PSEUDOCT_LAUNCHER and refuses an explicit Launcher that is
%     not that file; an incomplete one (no runtimes/) fails closed with no
%     launcher-path advice; a source checkout honours Launcher and PSEUDOCT_LAUNCHER
%     for development.
installed_full = fullfile(work, 'installed full');
mkdir(fullfile(installed_full, 'bin'));
mkdir(fullfile(installed_full, 'runtimes'));
packaged_stub = fullfile(installed_full, 'bin', 'pseudoct');
local_write(packaged_stub, { ...
    '#!/bin/bash'; ...
    'printf ''%s\n'' "$@" > "$PSEUDOCT_STUB_ARGV"'; ...
    'echo ''{"type":"result","outcome":"validation_succeeded","submission_status":"not_attempted","authentication_status":"not_attempted","dispatch_status":"not_dispatched","backend":"local","job_ids":[],"error_code":null,"error_message":null,"exit_code":0}'''; ...
    'exit 0'});
system(['chmod +x ' local_sh(packaged_stub)]);
setenv('PSEUDOCT_LAUNCHER', stub);
req_installed = pseudo_CT_launch_request('parse', {'Profile', 'local', ...
    'MPRAGE', spaced}, installed_full);
assert(strcmp(req_installed.launcher, packaged_stub), ...
    'An installed distribution must use its packaged launcher, not PSEUDOCT_LAUNCHER.');
req_source = pseudo_CT_launch_request('parse', {'Profile', 'local', ...
    'MPRAGE', spaced}, repo);
assert(strcmp(req_source.launcher, stub), ...
    'A source checkout must honour PSEUDOCT_LAUNCHER for development.');
req_source_explicit = pseudo_CT_launch_request('parse', {'Profile', 'local', ...
    'MPRAGE', spaced, 'Launcher', fail_stub}, repo);
assert(strcmp(req_source_explicit.launcher, fail_stub), ...
    'A source checkout must honour an explicit Launcher for development.');
% Installed: with PSEUDOCT_LAUNCHER still set, an explicit Launcher naming any other
% file is refused before anything runs; only the bundled bin/pseudoct is accepted.
local_expect('run_pseudo_CT:LauncherOverrideDevelopmentOnly', @() local_parse({ ...
    'Profile', 'local', 'MPRAGE', spaced, 'Launcher', stub}, installed_full));
local_expect('run_pseudo_CT:LauncherOverrideDevelopmentOnly', @() local_parse({ ...
    'Profile', 'local', 'MPRAGE', spaced, 'Launcher', fail_stub}, installed_full));
local_expect('run_pseudo_CT:LauncherOverrideDevelopmentOnly', @() local_parse({ ...
    'Profile', 'local', 'MPRAGE', spaced, 'Launcher', fullfile(installed_full, 'bin', 'other')}, ...
    installed_full));
req_bundled_explicit = pseudo_CT_launch_request('parse', {'Profile', 'local', ...
    'MPRAGE', spaced, 'Launcher', packaged_stub}, installed_full);
assert(strcmp(req_bundled_explicit.launcher, packaged_stub), ...
    'An installed distribution must accept only its bundled launcher explicitly.');
setenv('PSEUDOCT_LAUNCHER', '');
installed_broken = fullfile(work, 'installed broken');
mkdir(fullfile(installed_broken, 'bin'));
local_write(fullfile(installed_broken, 'bin', 'pseudoct'), {'#!/bin/bash'; 'exit 0'});
setenv('PSEUDOCT_LAUNCHER', stub);
broken_message = local_expect('pseudo_CT:FrontendLauncher', @() local_parse({'Profile', ...
    'local', 'MPRAGE', spaced}, installed_broken));
setenv('PSEUDOCT_LAUNCHER', '');
assert(isempty(strfind(broken_message, 'PSEUDOCT_LAUNCHER')) && ...
    isempty(strfind(broken_message, 'Pass')), ...
    'An incomplete installation must not ask for a launcher path or environment variable.');

% 6i. The GUI sends run validate and run through the packaged launcher with the
%     argv the CLI parses; the stub records exactly what it receives.
gui_validate = pseudo_CT_launch_request('parse', {'Profile', 'local', 'MPRAGE', spaced, ...
    'Action', 'validate'}, installed_full);
validate_result = pseudo_CT_launch_request('invoke', gui_validate);
assert(validate_result.ok && strcmp(validate_result.outcome, 'validation_succeeded'), ...
    'The packaged launcher did not accept run validate.');
seen = local_lines(argv_file);
assert(isequal(seen, pseudo_CT_launch_request('argv', gui_validate)), ...
    'GUI validate must send its request argv to the packaged launcher.');
assert(strcmp(seen{1}, 'run') && strcmp(seen{2}, 'validate'), 'GUI validate must send run validate.');
gui_submit = pseudo_CT_launch_request('parse', {'Profile', 'local', 'MPRAGE', spaced, ...
    'Action', 'submit'}, installed_full);
pseudo_CT_launch_request('invoke', gui_submit);
seen = local_lines(argv_file);
assert(isequal(seen, pseudo_CT_launch_request('argv', gui_submit)), ...
    'GUI submit must send its request argv to the packaged launcher.');
assert(strcmp(seen{1}, 'run') && strcmp(seen{2}, 'run'), 'GUI submit must send run run.');
assert(strcmp(gui_validate.launcher, packaged_stub) && strcmp(gui_submit.launcher, packaged_stub), ...
    'The GUI must reach the same packaged bin/pseudoct as the CLI.');
% The GUI passes its own bundled launcher explicitly (pseudo_CT_gui_args context): that
% exact path is accepted and still reaches the packaged launcher.
gui_explicit = pseudo_CT_launch_request('parse', pseudo_CT_gui_args(gui_values, ...
    struct('launcher', packaged_stub, 'runtime', '', 'mcr_root', ''), 'validate'), installed_full);
assert(strcmp(gui_explicit.launcher, packaged_stub), ...
    'A GUI request with the bundled launcher must resolve to it.');
explicit_result = pseudo_CT_launch_request('invoke', gui_explicit);
assert(explicit_result.ok && strcmp(explicit_result.outcome, 'validation_succeeded'), ...
    'The GUI request through the bundled launcher did not validate.');

% 6f. The static profile table matches the profile files (source checkout only).
if exist(fullfile(repo, 'src', 'config', 'profiles'), 'dir') == 7
    addpath(genpath(fullfile(repo, 'src')), '-begin');
    addpath(fullfile(repo, 'frontend'), '-begin');
    choices = pseudo_CT_profile_choices();
    for kk = 1:numel(choices)
        real = pseudo_CT_load_profile(choices(kk).name);
        assert(strcmp(real.presentation.display_name, choices(kk).display_name), ...
            'Static display name drifted for %s.', choices(kk).name);
        assert(strcmp(real.presentation.description, choices(kk).description), ...
            'Static description drifted for %s.', choices(kk).name);
        % Descriptions must not use build jargon or a fixed-release claim.
        bad_terms = {'payload', 'current-science', 'R2010b'};
        for bb = 1:numel(bad_terms)
            assert(isempty(strfind(real.presentation.description, bad_terms{bb})) && ...
                isempty(strfind(choices(kk).description, bad_terms{bb})), ...
                'Description for %s contains forbidden term "%s".', ...
                choices(kk).name, bad_terms{bb});
        end
        assert(strcmp(real.presentation.group, choices(kk).group) && ...
            real.presentation.recommended == choices(kk).recommended && ...
            real.presentation.order == choices(kk).order, ...
            'Static presentation drifted for %s.', choices(kk).name);
        assert(strcmp(real.mode, choices(kk).config.mode), ...
            'Static mode drifted for %s.', choices(kk).name);
        assert(strcmp(real.io_policy.reference, choices(kk).config.io_policy.reference) && ...
            strcmp(real.io_policy.output, choices(kk).config.io_policy.output) && ...
            strcmp(real.io_policy.gui, choices(kk).config.io_policy.gui), ...
            'Static io_policy drifted for %s.', choices(kk).name);
        assert(real.aliasing_default == choices(kk).config.aliasing_default && ...
            strcmp(real.recenter_before_normalization, ...
            choices(kk).config.recenter_before_normalization) && ...
            real.cleanup_on_success == choices(kk).config.cleanup_on_success, ...
            'Static GUI defaults drifted for %s.', choices(kk).name);
    end
end

% 6g. The frontend UMAP discovery (shipped without src/io) must agree with the
%     source discovery rule for a found, an absent and an ambiguous reference.
addpath(genpath(fullfile(repo, 'src')), '-begin');
discover_root = fullfile(work, 'discover', 'MR');
mkdir(fullfile(discover_root, 'MPRAGE'));
mkdir(fullfile(discover_root, 'UMAP'));
discover_mprage = fullfile(discover_root, 'MPRAGE', 'scan0001.dcm');
local_write(discover_mprage, {'mprage'});
local_write(fullfile(discover_root, 'UMAP', 'umap0001.dcm'), {'umap'});
[~, source_umap] = pseudo_CT_discover_ute_umap(discover_mprage);
frontend_umap = pseudo_CT_discover_umap(discover_mprage);
assert(ischar(frontend_umap) && strcmp(frontend_umap, source_umap), ...
    'The frontend UMAP discovery must match the source discovery.');
local_write(fullfile(discover_root, 'UMAP', 'umap0002.dcm'), {'second'});
[~, source_two] = pseudo_CT_discover_ute_umap(discover_mprage);
frontend_two = pseudo_CT_discover_umap(discover_mprage);
assert(strcmp(frontend_two, source_two), 'Ambiguous candidates must resolve the same way.');
empty_root = fullfile(work, 'discover-empty', 'MR');
mkdir(fullfile(empty_root, 'MPRAGE'));
empty_mprage = fullfile(empty_root, 'MPRAGE', 'scan0001.dcm');
local_write(empty_mprage, {'mprage'});
[~, source_none] = pseudo_CT_discover_ute_umap(empty_mprage);
assert(isequal(pseudo_CT_discover_umap(empty_mprage), source_none) && ...
    isequal(source_none, 0), 'An absent UMAP must be reported as 0 by both.');

% 7. Optional real-distribution validation (never submits).
launcher = getenv('PSEUDOCT_FRONTEND_TEST_LAUNCHER');
mprage = getenv('PSEUDOCT_FRONTEND_TEST_MPRAGE');
if ~isempty(launcher) && ~isempty(mprage)
    report = run_pseudo_CT('Profile', 'local', 'MPRAGE', mprage, ...
        'Launcher', launcher);
    assert(report.ok && strcmp(report.outcome, 'validation_succeeded'), ...
        'The installed launcher did not validate the real MPRAGE.');
    assert(strcmp(report.submission_status, 'not_attempted'));
    assert(strcmp(report.dispatch_status, 'not_dispatched'));
end
end

function req = local_parse(args, repo)
req = pseudo_CT_launch_request('parse', args, repo);
end

function message = local_expect(identifier, handle)
message = '';
raised = false;
try
    feval(handle);
catch ME
    raised = true;
    message = ME.message;
    if ~strcmp(ME.identifier, identifier)
        error('test_frontend_launch:Identifier', 'Expected %s, got %s: %s', ...
            identifier, ME.identifier, ME.message);
    end
end
if ~raised
    error('test_frontend_launch:NoError', 'Expected %s but no error was raised.', identifier);
end
end

function local_write(path_text, lines)
fid = fopen(path_text, 'w');
if fid == -1
    error('test_frontend_launch:Write', 'Cannot write %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
for kk = 1:numel(lines)
    fprintf(fid, '%s\n', lines{kk});
end
end

function lines = local_lines(path_text)
fid = fopen(path_text, 'r');
if fid == -1
    error('test_frontend_launch:Read', 'Cannot read %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
text = fread(fid, '*char')';
lines = regexp(text, char(10), 'split');
if ~isempty(lines) && isempty(lines{end})
    lines(end) = [];
end
end

function quoted = local_sh(text)
q = char(39);
quoted = [q strrep(text, q, [q char(92) q q]) q];
end

function local_remove_tree(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
