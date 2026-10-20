function test_mlsc_backend()
%TEST_MLSC_BACKEND Focused credential-free MLSC seam tests.
%   Exercises account selection, shared-path preflight, safe script
%   generation/execution, and the strict submission boundary without using
%   credentials, a real scheduler, or a network connection.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');

test_root = [tempname ' with space' char(39) 'quote;$(not-executed)'];
mkdir(test_root);
cleanup = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>

old_environment = struct('path', getenv('PATH'), ...
    'tmpdir', getenv('TMPDIR'), ...
    'cpus', getenv('SLURM_CPUS_PER_TASK'), ...
    'runner_log', getenv('MLSC_TEST_RUNNER_LOG'), ...
    'fs_log', getenv('MLSC_TEST_FS_LOG'), ...
    'sbatch_log', getenv('MLSC_TEST_SBATCH_LOG'));
environment_cleanup = onCleanup(@() ...
    local_restore_environment(old_environment)); %#ok<NASGU>

shared_temp = fullfile(test_root, ['shared ' char(39) 'temp;$(safe)']);
node_local = fullfile(test_root, 'node-local-tmp');
fake_bin = fullfile(test_root, 'fake-bin');
mkdir(shared_temp);
mkdir(node_local);
mkdir(fake_bin);

input_name = ['input ' char(39) 'image;$(safe).nii'];
input_path = fullfile(shared_temp, input_name);
script_path = fullfile(shared_temp, ...
    ['job ' char(39) 'script;$(safe).sh']);
runner_path = fullfile(test_root, ...
    ['runner ' char(39) 'script;$(safe).sh']);
mcr_root = fullfile(test_root, ['mcr ' char(39) 'root;$(safe)']);
batch_templates = fullfile(test_root, ...
    ['batch ' char(39) 'templates;$(safe)']);
defaults_mat = fullfile(test_root, ...
    ['defaults ' char(39) 'file;$(safe).mat']);
freesurfer_env = fullfile(test_root, ...
    ['FreeSurfer ' char(39) 'env;$(safe)']);
runner_log = fullfile(test_root, 'runner.log');
fs_log = fullfile(test_root, 'freesurfer.log');
sbatch_log = fullfile(test_root, 'sbatch.log');

mkdir(mcr_root);
mkdir(batch_templates);
local_write(input_path, 'shared input');
local_write(defaults_mat, 'defaults');
local_write(freesurfer_env, ['#!/bin/bash' char(10)]);
runner_text = ['#!/bin/bash' char(10) ...
    'printf ''%s\n'' "$PWD" > "$MLSC_TEST_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$1" >> "$MLSC_TEST_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$2" >> "$MLSC_TEST_RUNNER_LOG"' char(10) ...
    'printf ''runner output\n'' > "$PWD/att_map.nii"' char(10) ...
    'printf ''version\n'' > "$PWD/Pseudo_CT_AC_Version.txt"' char(10)];
local_write(runner_path, runner_text);
runner_before = local_read(runner_path);
normalizer_path = fullfile(fake_bin, 'mri_normalize');
local_write(normalizer_path, ['#!/bin/bash' char(10) ...
    'printf ''%s\n'' "$PWD" > "$MLSC_TEST_FS_LOG"' char(10) ...
    'printf ''%s\n'' "$1" >> "$MLSC_TEST_FS_LOG"' char(10) ...
    'cp -- "$1" "$2"' char(10)]);
sbatch_path = fullfile(fake_bin, 'sbatch');
local_write(sbatch_path, ['#!/bin/bash' char(10) ...
    'printf ''%s\n'' "$@" > "$MLSC_TEST_SBATCH_LOG"' char(10)]);
local_make_executable(runner_path);
local_make_executable(normalizer_path);
local_make_executable(sbatch_path);

config = struct();
config.mode = 'mlsc';
config.aliasing_default = 1;
config.mlsc = struct('host', 'mlsc.nmr.mgh.harvard.edu', ...
    'runner', runner_path, 'mcr_root', mcr_root, ...
    'defaults_mat', defaults_mat, 'batch_templates', batch_templates, ...
    'shell', '/bin/bash', 'freesurfer_env', freesurfer_env, ...
    'partition', 'basic', 'nodes', 1, 'ntasks', 1, ...
    'cpus_per_task', 1, 'memory', '1G', 'time', '00:01:00');
subject = struct('subject_id', 'fixture-subject', ...
    'shared_input', input_path, 'shared_temp', shared_temp, ...
    'check_aliasing', 1);
runtime = struct('account', ['account ' char(39) ';$(safe)'], ...
    'job_name', ['job ' char(39) ';$(safe)'], ...
    'script_path', script_path);

% Account discovery and selection remain runtime-only, including GUI cancel.
account_lines = {'Account                RawShares'; ...
    '---------------------- ---------'; 'alpha                  10'; ...
    'beta                   20'; 'alpha                  10'; ...
    'mal;formed'; 'bad$account            5'};
assert(isequal(mlsc_parse_slurm_accounts(account_lines), {'alpha', 'beta'}));
assert(isempty(mlsc_parse_slurm_accounts({'Account RawShares'; '---'})));
% Canonical `sshare -U -u $USER -P --format=Account --noheader` live
% shapes: a single Account field per line, as a cell array or as char
% text, with an optional trailing pipe; blank lines are ignored and
% repeated, header, and malformed single-field lines stay filtered out.
assert(isequal(mlsc_parse_slurm_accounts({'catanacol'}), {'catanacol'}));
assert(isequal(mlsc_parse_slurm_accounts('catanacol'), {'catanacol'}));
assert(isequal(mlsc_parse_slurm_accounts({'catanacol|'}), {'catanacol'}));
assert(isequal(mlsc_parse_slurm_accounts({'catanacol|', '', 'Account', ...
    'catanacol', 'mal;formed'}), {'catanacol'}));
local_assert_error(@() mlsc_select_account({}), ...
    'pseudo_CT:MLSCNoAccounts');
assert(strcmp(mlsc_select_account({'only'}), 'only'));
local_test_account_dialog();

% Shared input/temp and selected MLSC resources pass without any Launchpad
% fields, while malformed or unrelated runtime values fail closed.
preflight = mlsc_preflight(subject, config, runtime);
assert(preflight.ok && preflight.shared_input_readable && ...
    preflight.shared_temp_writable);
assert(preflight.needs_normalization);
bad_subject = subject;
bad_subject.shared_input = fullfile(test_root, 'outside.nii');
local_write(bad_subject.shared_input, 'outside');
local_assert_error(@() mlsc_preflight(bad_subject, config, runtime), ...
    'pseudo_CT:MLSCPreflight');
bad_subject = subject;
bad_subject.shared_input = fullfile(shared_temp, 'missing.nii');
local_assert_error(@() mlsc_preflight(bad_subject, config, runtime), ...
    'pseudo_CT:MLSCInputUnreadable');
bad_config = config;
bad_config.mlsc.account = 'must-not-be-persisted';
local_assert_error(@() mlsc_preflight(subject, bad_config, runtime), ...
    'pseudo_CT:MLSCPreflight');
bad_runtime = runtime;
bad_runtime.password = 'must-not-be-passed';
local_assert_error(@() mlsc_preflight(subject, config, bad_runtime), ...
    'pseudo_CT:MLSCPreflight');

% Generate and execute the actual script with local fixture commands. This
% proves shell quoting, normal cp staging in both directions, node-local
% FreeSurfer/runner execution, and non-empty output gating without Slurm.
% The FreeSurfer normalization runs isolated via tcsh; the generated
% batch-script fixture is validated with bash -n only (syntax validation,
% no FreeSurfer/pseudoCT/SSH/Slurm execution).
artifact = mlsc_generate_slurm_script(subject, config, runtime);
assert(strcmp(artifact.heavy_processing_root, '$TMPDIR'));
assert(~isempty(strfind(artifact.script_text, ...
    'cp -- "$shared_input" "$local_input"')));
assert(~isempty(strfind(artifact.script_text, ...
    'cp -- "$TMPDIR/att_map.nii" "$shared_temp/att_map.nii"')));
% Isolated tcsh form with in-tcsh configured env sourcing and quoted I/O.
assert(~isempty(strfind(artifact.script_text, 'env -u LD_LIBRARY_PATH')));
assert(~isempty(strfind(artifact.script_text, 'tcsh -f -c ''source ')));
assert(~isempty(strfind(artifact.script_text, ...
    'source "$MLSC_FREESURFER_ENV"; mri_normalize "$TMPDIR/$MLSC_INPUT_NAME" "$TMPDIR/$MLSC_NORMALIZED_NAME"')));
assert(~isempty(strfind(artifact.script_text, ...
    ['MLSC_FREESURFER_ENV=' local_shell_quote(freesurfer_env)])));
assert(~isempty(strfind(artifact.script_text, '$TMPDIR/$MLSC_INPUT_NAME')));
% No Bash-level source of the configured env; sourcing occurs only inside tcsh.
assert(isempty(strfind(artifact.script_text, ...
    ['source ' local_shell_quote(freesurfer_env)])));
assert(length(strfind(artifact.script_text, 'source ')) == 1);
% The outer tcsh -c payload carries no Bash single-quoted fragments.
tcsh_marker = 'tcsh -f -c ''';
tcsh_start = strfind(artifact.script_text, tcsh_marker);
assert(~isempty(tcsh_start));
tcsh_payload = artifact.script_text(tcsh_start(1) + length(tcsh_marker):end);
tcsh_end = strfind(tcsh_payload, char(39));
assert(~isempty(tcsh_end));
tcsh_payload = tcsh_payload(1:tcsh_end(1) - 1);
assert(isempty(strfind(tcsh_payload, char(39))));
% Compiled/MCR invocation stays outside tcsh on its own Bash line.
q_runner_expected = local_shell_quote(runner_path);
tcsh_found = false;
runner_found = false;
script_lines = regexp(artifact.script_text, '\r\n|\n|\r', 'split');
for line_idx = 1:length(script_lines)
    script_line = script_lines{line_idx};
    if ~isempty(strfind(script_line, 'tcsh -f -c'))
        tcsh_found = true;
        assert(isempty(strfind(script_line, q_runner_expected)), ...
            'Compiled invocation must stay outside tcsh.');
    end
    if ~isempty(strfind(script_line, q_runner_expected))
        runner_found = true;
        assert(isempty(strfind(script_line, 'tcsh -f -c')), ...
            'Compiled invocation must stay outside tcsh.');
        assert(isempty(strfind(script_line, 'mri_normalize')), ...
            'Compiled invocation must stay outside tcsh.');
    end
end
assert(tcsh_found && runner_found);
% No FreeSurfer LD_LIBRARY_PATH leak: the only hit is the env -u prefix.
assert(isempty(strfind(artifact.script_text, 'export LD_LIBRARY_PATH')));
assert(isempty(strfind(artifact.script_text, 'LD_LIBRARY_PATH=')));
assert(length(strfind(artifact.script_text, 'LD_LIBRARY_PATH')) == 1);
assert(isempty(strfind(lower(artifact.script_text), 'scp_put')));
assert(isempty(strfind(lower(artifact.script_text), 'scp_get')));
assert(isempty(strfind(lower(artifact.script_text), 'network payload')));
local_write(script_path, artifact.script_text);
local_make_executable(script_path);

setenv('PATH', [fake_bin pathsep old_environment.path]);
setenv('TMPDIR', node_local);
setenv('SLURM_CPUS_PER_TASK', '1');
setenv('MLSC_TEST_RUNNER_LOG', runner_log);
setenv('MLSC_TEST_FS_LOG', fs_log);
setenv('MLSC_TEST_SBATCH_LOG', sbatch_log);
[status, detail] = system(['/bin/bash -n ' local_shell_quote(script_path)]);
assert(status == 0, detail);
[status, detail] = system(['/bin/bash ' local_shell_quote(script_path)]);
assert(status == 0, detail);
assert(exist(fullfile(node_local, input_name), 'file') == 2);
assert(exist(fullfile(node_local, ...
    [input_name(1:end-4) '_normalized.nii']), 'file') == 2);
assert(exist(fullfile(shared_temp, 'att_map.nii'), 'file') == 2);
assert(dir(fullfile(shared_temp, 'att_map.nii')).bytes > 0);
assert(exist(fullfile(shared_temp, 'Pseudo_CT_AC_Version.txt'), 'file') == 2);
assert(strcmp(local_read(runner_path), runner_before));
fs_lines = local_read_lines(fs_log);
runner_lines = local_read_lines(runner_log);
assert(strcmp(fs_lines{1}, node_local));
assert(strcmp(fs_lines{2}, fullfile(node_local, input_name)));
assert(strcmp(runner_lines{1}, node_local));
assert(strcmp(runner_lines{2}, mcr_root));
assert(strcmp(runner_lines{3}, fullfile(node_local, ...
    [input_name(1:end-4) '_normalized.nii'])));
setenv('TMPDIR', shared_temp);
[status, ~] = system(['/bin/bash ' local_shell_quote(script_path)]);
assert(status == 71, 'Shared subject temp was accepted as node-local TMPDIR.');
setenv('TMPDIR', node_local);

% The generated sbatch command is also shell-safe, but this test only calls a
% local fixture executable and never reaches a scheduler.
[status, detail] = system(artifact.submission_command);
assert(status == 0, detail);
sbatch_lines = local_read_lines(sbatch_log);
assert(isequal(sbatch_lines, {'--parsable'; '--account'; runtime.account; ...
    '--job-name'; runtime.job_name; '--'; runtime.script_path}));

% T006: generated progress-file presence, bounded record set, exact order,
% at-most-once emission, optional normalization, independent Slurm logs,
% and unchanged exit contracts. Local fixture text only; no scheduler.
assert(strcmp(artifact.progress_filename, '.mlsc_progress'));
assert(strcmp(artifact.progress_path, ...
    fullfile(shared_temp, '.mlsc_progress')));
assert(strcmp(mlsc_progress('filename'), artifact.progress_filename));
expected_progress = {'stage_in|done'; 'preparation|done'; 'alias_recenter|done'; ...
    'normalize|start'; 'normalize|done'; 'alignment_mask|done'; ...
    'segmentation|done'; 'bone|done'; 'dartel_warp_reslice|done'; ...
    'pseudoCT|start'; 'pseudoCT|done'; 'attenuation_qc|done'; ...
    'verify|start'; 'verify|done'; 'copy_back|start'; 'copy_back|done'};
assert(isequal(artifact.progress_records, expected_progress));
assert(isequal(mlsc_progress('records'), expected_progress));
assert(artifact.preflight.needs_normalization);
% R006: legacy emits its original nine subset exactly once in order;
% current milestones are recognized by the shared engine but absent here.
legacy_subset = {'stage_in|done'; 'normalize|start'; ...
    'normalize|done'; 'pseudoCT|start'; 'pseudoCT|done'; ...
    'verify|start'; 'verify|done'; 'copy_back|start'; ...
    'copy_back|done'};
assert(~isempty(strfind(artifact.script_text, ...
    'progress_file="$shared_temp/.mlsc_progress"')));
assert(~isempty(strfind(artifact.script_text, 'mlsc_record_progress() {')));
assert(~isempty(strfind(artifact.script_text, '(umask 077;')));
assert(~isempty(strfind(artifact.script_text, '|| true')));
progress_markers = cell(size(legacy_subset));
for progress_ii = 1:length(legacy_subset)
    progress_markers{progress_ii} = ['mlsc_record_progress ''' ...
        legacy_subset{progress_ii} ''''];
    assert(length(strfind(artifact.script_text, ...
        progress_markers{progress_ii})) == 1, ...
        'Each legacy progress milestone must be emitted exactly once.');
end
for progress_ii = 2:length(progress_markers)
    earlier = strfind(artifact.script_text, progress_markers{progress_ii - 1});
    later = strfind(artifact.script_text, progress_markers{progress_ii});
    assert(earlier(1) < later(1), ...
        'Progress milestones must stay in reachable execution order.');
end
% Current milestones are recognized but absent from legacy (no leakage).
current_only = {'preparation|done'; 'alias_recenter|done'; ...
    'alignment_mask|done'; 'segmentation|done'; 'bone|done'; ...
    'dartel_warp_reslice|done'; 'attenuation_qc|done'};
for progress_ii = 1:length(current_only)
    assert(isempty(strfind(artifact.script_text, current_only{progress_ii})), ...
        'Legacy script carries current milestones.');
end
assert(isempty(strfind(artifact.script_text, runtime.account)), ...
    'The progress script must not interpolate the runtime account.');
lower_script = lower(artifact.script_text);
assert(isempty(strfind(lower_script, 'password')));
assert(isempty(strfind(lower_script, 'credential')));
assert(isempty(strfind(lower_script, 'ssh')));
assert(~strcmp(artifact.stdout_log_path, artifact.stderr_log_path));
assert(~isempty(strfind(artifact.stdout_log_path, '%j')));
assert(~isempty(strfind(artifact.stderr_log_path, '%j')));
assert(isempty(strfind(artifact.script_text, '/dev/null')));
assert(~isempty(strfind(artifact.script_text, '#SBATCH --output=')));
assert(~isempty(strfind(artifact.script_text, '#SBATCH --error=')));
assert(~isempty(strfind(artifact.script_text, 'exit 71')));
assert(~isempty(strfind(artifact.script_text, 'exit 72')));
assert(~isempty(strfind(artifact.script_text, 'exit 73')));
assert(~isempty(strfind(artifact.script_text, 'exit 74')));
% Optional normalization: an already-normalized input produces no false
% normalize milestones while the other seven records stay ordered and once.
normalized_input = fullfile(shared_temp, 'already_normalized.nii');
local_write(normalized_input, 'normalized input');
normalized_subject = subject;
normalized_subject.shared_input = normalized_input;
normalized_artifact = mlsc_generate_slurm_script(normalized_subject, ...
    config, runtime);
assert(~normalized_artifact.preflight.needs_normalization);
assert(isempty(strfind(normalized_artifact.script_text, ...
    'normalize|start')));
assert(isempty(strfind(normalized_artifact.script_text, ...
    'normalize|done')));
expected_without_norm = {'stage_in|done'; 'pseudoCT|start'; ...
    'pseudoCT|done'; 'verify|start'; 'verify|done'; ...
    'copy_back|start'; 'copy_back|done'};
for progress_ii = 1:length(expected_without_norm)
    marker = ['mlsc_record_progress ''' ...
        expected_without_norm{progress_ii} ''''];
    assert(length(strfind(normalized_artifact.script_text, marker)) == 1);
end
% R2010b compatibility guard for the generator seam under test.
generator_source = local_read(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_generate_slurm_script.m'));
assert(~isempty(strfind(generator_source, ...
    'Minimum supported MATLAB: R2010b')));
assert(isempty(strfind(generator_source, 'contains(')));
assert(isempty(strfind(generator_source, 'startsWith(')));
assert(isempty(strfind(generator_source, 'string(')));
local_mlint_parse(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_generate_slurm_script.m'));
local_mlint_parse(fullfile(root_dir, 'src', 'mlsc', 'mlsc_progress.m'));

% The backend accepts only a strict verified callback and never exposes
% credential or network-payload fields. Submission is represented by a fake
% sbatch response, not performed.
verify_value = true;
verify_calls = 0;
submit_calls = 0;
submitted_command = '';
transport = struct('verify', @backend_verify, ...
    'submit_script', @backend_submit);
backend_result = mlsc_backend(subject, config, runtime, transport);
assert(backend_result.job_id == 31415 && backend_result.submission_accepted);
assert(backend_result.secure_transport_verified);
assert(~backend_result.credentials_emitted && ...
    ~backend_result.network_payload_staging);
assert(verify_calls == 1 && submit_calls == 1);
assert(strcmp(submitted_command, backend_result.artifact.submission_command));
assert(exist(runtime.script_path, 'file') == 2);

% Regression A: a writable runtime.evidence_dir selects the receipt dir
% while the script still materializes only to runtime.script_path.
evidence_dir = fullfile(test_root, 'evidence');
mkdir(evidence_dir);
evidence_runtime = runtime;
evidence_runtime.evidence_dir = evidence_dir;
evidence_result = mlsc_backend(subject, config, evidence_runtime, transport);
assert(strncmp(evidence_result.submission_receipt_path, ...
    [evidence_dir filesep], length(evidence_dir) + 1));
assert(exist(evidence_result.submission_receipt_path, 'file') == 2);
assert(exist(runtime.script_path, 'file') == 2);
assert(evidence_result.job_id == 31415 && ...
    evidence_result.submission_accepted);

% Regression B: an invalid runtime.evidence_dir falls back to shared_temp
% while the script still materializes only to runtime.script_path.
fallback_runtime = runtime;
fallback_runtime.evidence_dir = fullfile(test_root, 'missing-evidence-dir');
fallback_result = mlsc_backend(subject, config, fallback_runtime, transport);
assert(strncmp(fallback_result.submission_receipt_path, ...
    [shared_temp filesep], length(shared_temp) + 1));
assert(exist(fallback_result.submission_receipt_path, 'file') == 2);
assert(exist(runtime.script_path, 'file') == 2);
assert(fallback_result.job_id == 31415 && ...
    fallback_result.submission_accepted);

% T008: a preserved-temp retry starts from a fresh per-run progress
% boundary. A stale prior-run file never survives submission, so the
% current run neither consumes stale records nor suppresses its own
% duplicates as already-emitted. Local fixtures only; no scheduler.
t008_progress_path = fullfile(shared_temp, '.mlsc_progress');
t008_stale = fopen(t008_progress_path, 'w');
assert(t008_stale ~= -1);
fwrite(t008_stale, ['stage_in|done' char(10) 'pseudoCT|done' char(10) ...
    'copy_back|done' char(10)]);
fclose(t008_stale);
assert(exist(t008_progress_path, 'file') == 2);
t008_result = mlsc_backend(subject, config, runtime, transport);
assert(t008_result.job_id == 31415 && t008_result.submission_accepted);
if exist(t008_progress_path, 'file') == 2
    t008_info = dir(t008_progress_path);
    assert(numel(t008_info) == 1 && t008_info(1).bytes == 0);
end
t008_fresh = fopen(t008_progress_path, 'w');
assert(t008_fresh ~= -1);
fwrite(t008_fresh, ['stage_in|done' char(10)]);
fclose(t008_fresh);
t008_cursor = mlsc_progress('init');
[t008_events, t008_cursor] = mlsc_progress('consume', ...
    t008_progress_path, t008_cursor);
assert(isequal(t008_events, {'stage_in|done'}));
if exist(t008_progress_path, 'file') == 2
    delete(t008_progress_path);
end

% T011: robust per-submission progress boundary. The current submission
% selects one exact unique artifact derived from its non-secret
% correlation identity; Slurm writes only that file, lifecycle reads only
% that file, and a stale prior file that remains present/undeletable is
% never emitted. Local fixtures only; no scheduler.
t011_legacy_path = fullfile(shared_temp, '.mlsc_progress');
t011_stale = fopen(t011_legacy_path, 'w');
assert(t011_stale ~= -1);
fwrite(t011_stale, ['pseudoCT|done' char(10) 'copy_back|done' char(10)]);
fclose(t011_stale);
t011_first = mlsc_backend(subject, config, runtime, transport);
assert(t011_first.job_id == 31415 && t011_first.submission_accepted);
t011_corr = t011_first.submission_correlation_id;
assert(ischar(t011_corr) && size(t011_corr, 1) == 1 && ~isempty(t011_corr));
assert(length(t011_corr) <= 64);
assert(~isempty(regexp(t011_corr, '^[A-Za-z0-9_.-]+$', 'once')));
t011_expected_name = ['.mlsc_progress_' t011_corr];
assert(length(t011_expected_name) <= 80);
assert(strcmp(t011_first.progress_filename, t011_expected_name));
assert(strcmp(t011_first.artifact.progress_filename, t011_expected_name));
assert(strcmp(t011_first.progress_path, ...
    fullfile(shared_temp, t011_expected_name)));
assert(strcmp(t011_first.artifact.progress_path, ...
    fullfile(shared_temp, t011_expected_name)));
assert(strcmp(t011_first.progress_correlation_id, t011_corr));
assert(strcmp(t011_first.artifact.progress_correlation_id, t011_corr));
assert(strcmp(mlsc_progress('filename_for', t011_corr), ...
    t011_expected_name));
assert(strcmp(mlsc_progress('path_for', shared_temp, t011_corr), ...
    fullfile(shared_temp, t011_expected_name)));
assert(~strcmp(t011_first.progress_path, t011_legacy_path));
assert(~isempty(strfind(t011_first.artifact.script_text, ...
    ['progress_file="$shared_temp/' t011_expected_name '"'])));
assert(isempty(strfind(t011_first.artifact.script_text, ...
    'progress_file="$shared_temp/.mlsc_progress"')));
for t011_ii = 1:length(legacy_subset)
    t011_marker = ['mlsc_record_progress ''' ...
        legacy_subset{t011_ii} ''''];
    assert(length(strfind(t011_first.artifact.script_text, ...
        t011_marker)) == 1);
end
assert(isempty(strfind(t011_first.artifact.script_text, runtime.account)));
assert(isempty(strfind(t011_expected_name, runtime.account)));
assert(isempty(strfind(lower(t011_first.artifact.script_text), 'password')));
% A stale file that remains present (undeletable) never leaks into the
% current generation: only the new file is consumed.
t011_recreate = fopen(t011_legacy_path, 'w');
assert(t011_recreate ~= -1);
fwrite(t011_recreate, ['pseudoCT|done' char(10) ...
    'copy_back|done' char(10)]);
fclose(t011_recreate);
assert(exist(t011_legacy_path, 'file') == 2);
assert(exist(t011_first.progress_path, 'file') ~= 2);
t011_new = fopen(t011_first.progress_path, 'w');
assert(t011_new ~= -1);
fwrite(t011_new, ['stage_in|done' char(10)]);
fclose(t011_new);
t011_cursor = mlsc_progress('init');
[t011_events, t011_cursor] = mlsc_progress('consume', ...
    t011_first.progress_path, t011_cursor);
assert(isequal(t011_events, {'stage_in|done'}));
[t011_repeat, t011_cursor] = mlsc_progress('consume', ...
    t011_first.progress_path, t011_cursor);
assert(isempty(t011_repeat));
t011_legacy_cursor = mlsc_progress('init');
[t011_legacy_events, ~] = mlsc_progress('consume', t011_legacy_path, ...
    t011_legacy_cursor);
assert(isequal(t011_legacy_events, ...
    {'pseudoCT|done'; 'copy_back|done'}));
assert(~isequal(t011_events, t011_legacy_events));
% Independent generation: the next submission owns a different file.
t011_second = mlsc_backend(subject, config, runtime, transport);
assert(t011_second.job_id == 31415 && t011_second.submission_accepted);
assert(~strcmp(t011_second.progress_path, t011_first.progress_path));
assert(~strcmp(t011_second.submission_correlation_id, t011_corr));
assert(~isempty(strfind(t011_second.artifact.script_text, ...
    ['progress_file="$shared_temp/' t011_second.progress_filename '"'])));
% A caller-provided valid correlation is honored deterministically.
t011_fixed_runtime = runtime;
t011_fixed_runtime.submission_correlation_id = 't011fixed01';
t011_fixed = mlsc_backend(subject, config, t011_fixed_runtime, transport);
assert(strcmp(t011_fixed.submission_correlation_id, 't011fixed01'));
assert(strcmp(t011_fixed.progress_filename, '.mlsc_progress_t011fixed01'));
assert(strcmp(t011_fixed.artifact.progress_path, ...
    fullfile(shared_temp, '.mlsc_progress_t011fixed01')));
assert(~isempty(strfind(t011_fixed.artifact.script_text, ...
    'progress_file="$shared_temp/.mlsc_progress_t011fixed01"')));
if exist(t011_legacy_path, 'file') == 2
    delete(t011_legacy_path);
end
if exist(t011_first.progress_path, 'file') == 2
    delete(t011_first.progress_path);
end
if exist(fullfile(shared_temp, '.mlsc_progress_t011fixed01'), 'file') == 2
    delete(fullfile(shared_temp, '.mlsc_progress_t011fixed01'));
end
if exist(t011_second.progress_path, 'file') == 2
    delete(t011_second.progress_path);
end

% T014: a caller-supplied correlation cannot reselect an existing
% generation. A preserved correlation-specific progress file whose
% receipt is missing/moved forces a fresh identity; the preserved file
% is never appended or consumed. Local fixtures only; no scheduler.
t014_collision = 't014collide01';
t014_stale_name = ['.mlsc_progress_' t014_collision];
t014_stale_path = fullfile(shared_temp, t014_stale_name);
t014_stale_receipt = fullfile(shared_temp, ...
    ['.mlsc_submission_' t014_collision '.mat']);
if exist(t014_stale_receipt, 'file') == 2
    delete(t014_stale_receipt);
end
if exist(t014_stale_path, 'file') == 2
    delete(t014_stale_path);
end
t014_seed = fopen(t014_stale_path, 'w');
assert(t014_seed ~= -1);
fwrite(t014_seed, ['pseudoCT|done' char(10) 'copy_back|done' char(10)]);
fclose(t014_seed);
assert(exist(t014_stale_path, 'file') == 2);
t014_before_text = local_read(t014_stale_path);
t014_before_info = dir(t014_stale_path);
assert(numel(t014_before_info) == 1);
t014_collision_runtime = runtime;
t014_collision_runtime.submission_correlation_id = t014_collision;
t014_result = mlsc_backend(subject, config, t014_collision_runtime, ...
    transport);
assert(t014_result.job_id == 31415 && t014_result.submission_accepted);
assert(~strcmp(t014_result.submission_correlation_id, t014_collision));
assert(~strcmp(t014_result.progress_path, t014_stale_path));
assert(~strcmp(t014_result.progress_filename, t014_stale_name));
assert(~strcmp(t014_result.submission_receipt_path, t014_stale_receipt));
assert(~isempty(strfind(t014_result.artifact.script_text, ...
    ['progress_file="$shared_temp/' t014_result.progress_filename '"'])));
assert(isempty(strfind(t014_result.artifact.script_text, t014_stale_name)));
assert(exist(t014_stale_path, 'file') == 2);
assert(strcmp(local_read(t014_stale_path), t014_before_text));
t014_after_info = dir(t014_stale_path);
assert(numel(t014_after_info) == 1 && ...
    t014_after_info(1).bytes == t014_before_info(1).bytes);
assert(exist(t014_result.progress_path, 'file') ~= 2);
t014_fresh_cursor = mlsc_progress('init');
[t014_fresh_events, ~] = mlsc_progress('consume', ...
    t014_result.progress_path, t014_fresh_cursor);
assert(isempty(t014_fresh_events));
t014_stale_cursor = mlsc_progress('init');
[t014_stale_events, ~] = mlsc_progress('consume', t014_stale_path, ...
    t014_stale_cursor);
assert(isequal(t014_stale_events, ...
    {'pseudoCT|done'; 'copy_back|done'}));
assert(~isequal(t014_fresh_events, t014_stale_events));
t014_backend_source = local_read(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_backend.m'));
assert(~isempty(strfind(t014_backend_source, ...
    'Minimum supported MATLAB: R2010b')));
assert(isempty(strfind(t014_backend_source, 'contains(')));
assert(isempty(strfind(t014_backend_source, 'startsWith(')));
assert(isempty(strfind(t014_backend_source, 'string(')));
local_mlint_parse(fullfile(root_dir, 'src', 'mlsc', 'mlsc_backend.m'));
if exist(t014_stale_path, 'file') == 2
    delete(t014_stale_path);
end
if exist(t014_result.progress_path, 'file') == 2
    delete(t014_result.progress_path);
end

verify_value = false;
submit_count_before = submit_calls;
local_assert_error(@() mlsc_backend(subject, config, runtime, transport), ...
    'pseudo_CT:MLSCTransportRejected');
assert(submit_calls == submit_count_before);
secret_transport = transport;
secret_transport.password = 'blocked';
local_assert_error(@() mlsc_backend(subject, config, runtime, secret_transport), ...
    'pseudo_CT:MLSCTransportRejected');

% This is the single source-boundary check needed for the no-reachability
% invariant; script behavior above covers all staging and command content.
backend_source = local_read(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_backend.m'));
forbidden_helpers = {'scp_put'; 'scp_get'; 'batch_pseudo_CT_launchpad'; ...
    'run_launchpad_cmd_return'; 'pbsubmit'};
for ii = 1:length(forbidden_helpers)
    assert(isempty(strfind(backend_source, forbidden_helpers{ii})));
end

fprintf(['=== MLSC backend tests passed: accounts, shared-path preflight, ', ...
    'quoted cp staging, node-local execution, output gating, and strict ', ...
    'transport boundary ===\n']);

    function accepted = backend_verify()
        verify_calls = verify_calls + 1;
        accepted = verify_value;
    end

    function response = backend_submit(command)
        submit_calls = submit_calls + 1;
        submitted_command = command;
        response = '31415;mlsc';
    end
end

function local_test_account_dialog()
stub_dir = tempname;
mkdir(stub_dir);
local_write(fullfile(stub_dir, 'listdlg.m'), ...
    ['function [selection, accepted] = listdlg(varargin)' char(10) ...
     'global test_mlsc_selection test_mlsc_accepted' char(10) ...
     'selection = test_mlsc_selection;' char(10) ...
     'accepted = test_mlsc_accepted;' char(10) 'end' char(10)]);
old_path = path();
cleanup = onCleanup(@() local_restore_listdlg(old_path, stub_dir)); %#ok<NASGU>
addpath(stub_dir, '-begin');
clear('listdlg');
global test_mlsc_selection test_mlsc_accepted
test_mlsc_selection = 2;
test_mlsc_accepted = 1;
assert(strcmp(mlsc_select_account({'first'; 'second'}), 'second'));
test_mlsc_selection = [];
test_mlsc_accepted = 0;
assert(isempty(mlsc_select_account({'first'; 'second'})));
end

function local_restore_listdlg(old_path, stub_dir)
clear('listdlg');
path(old_path);
global test_mlsc_selection test_mlsc_accepted
test_mlsc_selection = [];
test_mlsc_accepted = [];
clear global test_mlsc_selection test_mlsc_accepted
if exist(stub_dir, 'dir') == 7
    rmdir(stub_dir, 's');
end
end

function local_assert_error(callback, expected_identifier)
failed = false;
actual_identifier = '';
try
    feval(callback);
catch ME
    failed = true;
    actual_identifier = ME.identifier;
end
assert(failed, 'The focused negative test did not fail closed.');
if nargin > 1 && ~isempty(expected_identifier)
    assert(strcmp(actual_identifier, expected_identifier), ...
        'Unexpected error identifier: %s', actual_identifier);
end
end

function quoted = local_shell_quote(value)
single_quote = char(39);
quoted = single_quote;
for ii = 1:length(value)
    if value(ii) == single_quote
        quoted = [quoted single_quote char(34) single_quote ...
            char(34) single_quote]; %#ok<AGROW>
    else
        quoted = [quoted value(ii)]; %#ok<AGROW>
    end
end
quoted = [quoted single_quote];
end

function local_make_executable(file_path)
[status, detail] = system(['/bin/chmod 700 ' local_shell_quote(file_path)]);
assert(status == 0, detail);
end

function text = local_read(file_path)
fid = fopen(file_path, 'r');
assert(fid ~= -1, 'Could not read %s.', file_path);
text = fread(fid, inf, '*char')';
fclose(fid);
end

function lines = local_read_lines(file_path)
text = local_read(file_path);
lines = regexp(text, '\r\n|\n|\r', 'split');
if ~isempty(lines) && isempty(lines{end})
    lines = lines(1:end-1);
end
lines = lines(:);
end

function local_write(file_path, text)
fid = fopen(file_path, 'w');
assert(fid ~= -1, 'Could not write %s.', file_path);
fwrite(fid, text);
fclose(fid);
end

function local_restore_environment(environment)
setenv('PATH', environment.path);
setenv('TMPDIR', environment.tmpdir);
setenv('SLURM_CPUS_PER_TASK', environment.cpus);
setenv('MLSC_TEST_RUNNER_LOG', environment.runner_log);
setenv('MLSC_TEST_FS_LOG', environment.fs_log);
setenv('MLSC_TEST_SBATCH_LOG', environment.sbatch_log);
end

function local_mlint_parse(file_path)
try
    mlint(file_path);
catch ME
    assert(false, 'MLSC source failed to parse: %s', ME.message);
end
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
