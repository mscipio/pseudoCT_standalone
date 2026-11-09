function test_mlsc_slurm_lifecycle()
%TEST_MLSC_SLURM_LIFECYCLE Current MLSC submit/monitor/terminal contract.
%   Uses a synthetic installed-direct package built under scratch (placeholder
%   runner and Runtime tree, packaged resource names; nothing is executed), with
%   synthetic outputs and callbacks. No source artifact, SSH, scheduler command,
%   subject data, or scientific processing runs. The repository SPM tree is used
%   only to write the synthetic att_map fixture.

root_dir = fileparts(fileparts(mfilename('fullpath')));
old_path = path();
addpath(genpath(fullfile(root_dir, 'src')), '-begin');
cleanup_path = onCleanup(@() path(old_path)); %#ok<NASGU>
addpath(fullfile(root_dir, 'external', 'spm8-r6313'), '-begin');

scratch_root = getenv('PSEUDOCT_TEST_SCRATCH');
if isempty(scratch_root)
    scratch_root = fullfile(root_dir, '.aria', 'scratch', 'unplanned', ...
        [datestr(now, 'yyyymmdd-HHMMSS') '-pseudoct-tests']);
end
if exist(scratch_root, 'dir') ~= 7
    mkdir(scratch_root);
end
test_root = tempname(scratch_root);
mkdir(test_root);
cleanup_root = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>

package = local_installed_fixture(test_root);
env_names = {'PSEUDOCT_INSTALL_ROOT'; 'PSEUDOCT_RUNTIME_RELEASE'; ...
    'PSEUDOCT_RUNTIME_MCR_ROOT'; 'PSEUDOCT_RUNTIME_MCR_VERSION'};
old_env = cell(size(env_names));
for ii = 1:length(env_names)
    old_env{ii} = getenv(env_names{ii});
end
cleanup_env = onCleanup(@() local_restore_env(env_names, old_env)); %#ok<NASGU>
setenv('PSEUDOCT_INSTALL_ROOT', package.root);
setenv('PSEUDOCT_RUNTIME_RELEASE', 'R2010b');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', package.mcr);
setenv('PSEUDOCT_RUNTIME_MCR_VERSION', '7.14');
% Installed direct mode: the runner and Runtime come from the selected package;
% both manifest paths are cleared and the packaged resources are the atlas.
config = pseudo_CT_load_profile('mlsc');
config.current.runner = package.runner;
config.current.mcr_root = package.mcr;
config.current.build_manifest = '';
config.current.resource_manifest = '';
config.atlas_root = package.resources;

active_scenario = '';
active_shared_temp = '';
last_console = '';
log_line_a = '[2026-11-06 12:00:01] Aligning MPRAGE and creating subject mask.';
log_line_b = '[2026-11-06 12:00:02] Running SPM New Segment.';
log_line_c = '[2026-11-06 12:00:03] Applying inverse warp.';
active_scheduler_state = 'COMPLETED';
active_exit_code = '0:0';
transport_allowed = true;
submit_calls = 0;
squeue_calls = 0;
sacct_calls = 0;
cancel_calls = 0;
clock_calls = 0;
submit_command_valid = false;
submit_response = '';
submit_fixture_error = '';
clock_base = datenum(2026, 11, 6, 12, 0, 0);
transport = struct('verify', @verify_transport, ...
    'submit_script', @submit_script, 'query_squeue', @query_squeue, ...
    'query_sacct', @query_sacct, ...
    'query_squeue_by_name', @empty_name_query, ...
    'query_sacct_by_name', @empty_name_query, ...
    'cancel_job', @cancel_job, 'sleep', @no_sleep, 'clock', @fake_clock);

result = run_case('completed', 'success');
assert(result.terminal && result.success && result.eligible_for_finalization, ...
    sprintf(['Successful fixture rejected: state=%s; submits=%d; ' ...
    'command_valid=%d; response=%s; fixture_error=%s; detail=%s'], ...
    result.state, submit_calls, submit_command_valid, submit_response, ...
    submit_fixture_error, result.failure_detail));
assert(strcmp(result.state, 'completed') && ...
    strcmp(result.scheduler_state, 'completed'));
assert(result.submission_accepted && result.job_id == 31415);
assert(result.contract.represented && result.copy_back.verified);
assert(result.copy_back.att_map_nonempty && ...
    result.copy_back.handoff_nonempty && ...
    result.copy_back.prepare_evidence_nonempty && ...
    result.copy_back.output_verification_nonempty);
assert(result.evidence_saved && submit_calls == 1 && ...
    squeue_calls == 1 && sacct_calls == 1);
assert(submit_command_valid, 'The generated submit command was invalid.');

result = run_case('completed-missing-output', 'missing_output');
assert(result.terminal && ~result.success && ...
    ~result.eligible_for_finalization && ~result.copy_back.verified);
assert(~isempty(strfind(result.failure_detail, 'incomplete required outputs')));

result = run_case('failed', 'failed');
assert(result.terminal && ~result.success && strcmp(result.state, 'failed'));
assert(result.accounting_record_found && result.exit_code == 2);

result = run_case('cancelled', 'timeout_cancel');
assert(result.terminal && ~result.success && strcmp(result.state, 'cancelled'));
assert(result.cancel_requested && result.cancel_succeeded && cancel_calls == 1);

% Caught post-submit interruption: the job is never cancelled, the outcome is
% unverified, and the manual scancel command is printed.
result = run_case('interrupted', 'interrupt');
assert(result.interrupted && result.terminal && ~result.success && ...
    ~result.eligible_for_finalization && strcmp(result.state, 'interrupted'));
assert(cancel_calls == 0, 'A caught interruption must not cancel the Slurm job.');
assert(result.job_id == 31415);
assert(~isempty(strfind(result.interruption_detail, 'continues to run')) && ...
    ~isempty(strfind(result.interruption_detail, 'scancel 31415')));
assert(~isempty(strfind(last_console, 'scancel 31415')), ...
    'The manual cancellation command must be printed for an interrupted job.');

% A Slurm log truncated and rewritten mid-run must not show earlier lines again.
result = run_case('log-rotate', 'log_rotate');
log_counts = [numel(strfind(last_console, 'Aligning MPRAGE and creating subject mask.')), ...
    numel(strfind(last_console, 'Running SPM New Segment.')), ...
    numel(strfind(last_console, 'Applying inverse warp.'))];
assert(isequal(log_counts, [1 1 1]), ...
    sprintf(['Each log line must show once across a rewrite: counts A/B/C = ' ...
    '%d/%d/%d. Console: %s'], log_counts(1), log_counts(2), log_counts(3), last_console));

% A rejected security gate must fail closed before the submit callback.
transport_allowed = false;
result = run_case('transport-rejected', 'transport_rejected');
assert(result.terminal && ~result.success && ~result.submission_accepted);
assert(submit_calls == 0);

assert(strcmp(mlsc_parse_squeue_state('COMPLETING+'), 'running'));
record = mlsc_parse_sacct_terminal( ...
    '31415|CANCELLED|0:15|2026-11-06T12:00:00|2026-11-06T12:01:00|60', ...
    31415);
assert(record.found && record.terminal && strcmp(record.state, 'cancelled'));

fprintf('Current MLSC submit/monitor/output/failure/cancellation checks passed.\n');

    function output = run_case(name, scenario)
        case_root = fullfile(test_root, name);
        active_shared_temp = fullfile(case_root, 'subject');
        evidence_dir = fullfile(case_root, 'evidence');
        mkdir(case_root);
        mkdir(active_shared_temp);
        mkdir(evidence_dir);
        input_path = fullfile(active_shared_temp, 'mprage.nii');
        local_write(input_path, 'synthetic input');
        subject = struct('subject_id', ['t003-' name], ...
            'shared_input', input_path, 'shared_temp', active_shared_temp, ...
            'check_aliasing', 0, 'recenter_before_normalization', 'No');
        runtime = struct('account', 'test-account', ...
            'script_path', fullfile(case_root, 'job.sh'), ...
            'evidence_dir', evidence_dir, 'log_archive_dir', evidence_dir, ...
            'timeout_seconds', 60, 'poll_interval_seconds', 1, ...
            'accounting_timeout_seconds', 1, 'max_polls', 1, ...
            'max_accounting_polls', 2, 'max_reconciliation_polls', 1, ...
            'reconciliation_interval_seconds', 1, ...
            'submission_correlation_id', 't003lifecycle');
        active_scenario = scenario;
        active_scheduler_state = 'COMPLETED';
        active_exit_code = '0:0';
        if strcmp(scenario, 'failed')
            active_scheduler_state = 'FAILED';
            active_exit_code = '2:0';
        elseif strcmp(scenario, 'timeout_cancel')
            runtime.timeout_seconds = 0.1;
        elseif strcmp(scenario, 'transport_rejected')
            transport_allowed = false;
        end
        if strcmp(scenario, 'log_rotate')
            runtime.timeout_seconds = 3600;
            runtime.max_polls = 4;
        end
        submit_calls = 0;
        squeue_calls = 0;
        sacct_calls = 0;
        cancel_calls = 0;
        clock_calls = 0;
        last_console = evalc('output = mlsc_lifecycle(subject, config, runtime, transport);');
    end

    function accepted = verify_transport()
        accepted = transport_allowed;
    end

    function response = submit_script(command)
        submit_command_valid = ischar(command) && ~isempty(command);
        submit_calls = submit_calls + 1;
        if strcmp(active_scenario, 'success') || ...
                strcmp(active_scenario, 'missing_output')
            try
                local_write_current_outputs(active_shared_temp, ...
                    strcmp(active_scenario, 'missing_output'));
            catch ME
                submit_fixture_error = ME.message;
            end
        end
        if strcmp(active_scenario, 'log_rotate')
            % Slurm stderr carries the diagnostic lines under test; stdout is not
            % a progress source in RC7.
            local_write(fullfile(active_shared_temp, 'pseudoCT_mlsc_31415.err'), ...
                [log_line_a char(10) log_line_b char(10)]);
        end
        response = '31415;mlsc';
        submit_response = response;
    end

    function response = query_squeue(~)
        squeue_calls = squeue_calls + 1;
        if strcmp(active_scenario, 'interrupt')
            error('mlsc_test:Interrupt', 'Injected interruption after submission.');
        end
        if strcmp(active_scenario, 'log_rotate')
            log_path = fullfile(active_shared_temp, 'pseudoCT_mlsc_31415.err');
            if squeue_calls == 2
                % Truncate to a shorter log: the reader restarts at byte 0.
                local_write(log_path, [log_line_a char(10)]);
            elseif squeue_calls == 3
                % Append after the rewrite: only the new line may show.
                local_write(log_path, [log_line_a char(10) log_line_c char(10)]);
            end
        end
        response = 'RUNNING';
    end

    function response = query_sacct(~)
        sacct_calls = sacct_calls + 1;
        if strcmp(active_scenario, 'log_rotate')
            response = '31415|PENDING|0:0|2026-11-06T12:00:00||';
        elseif strcmp(active_scenario, 'timeout_cancel') && cancel_calls == 0
            response = '31415|PENDING|0:0|2026-11-06T12:00:00||';
        elseif strcmp(active_scenario, 'timeout_cancel')
            response = '31415|CANCELLED|0:15|2026-11-06T12:00:00|2026-11-06T12:01:00|60';
        else
            response = sprintf(['31415|%s|%s|2026-11-06T12:00:00|' ...
                '2026-11-06T12:01:00|60'], active_scheduler_state, ...
                active_exit_code);
        end
    end

    function response = empty_name_query(~)
        response = '';
    end

    function cancel_job(~)
        cancel_calls = cancel_calls + 1;
    end

    function no_sleep(~)
    end

    function value = fake_clock()
        clock_calls = clock_calls + 1;
        value = clock_base + clock_calls / 86400;
    end
end

function local_write_current_outputs(shared_temp, omit_qc)
att_path = fullfile(shared_temp, 'att_map.nii');
V = struct('fname', att_path, 'dim', [2 2 2], 'dt', [16 0], ...
    'mat', eye(4), 'pinfo', [1 0 0]');
spm_write_vol(V, ones(2, 2, 2, 'single'));
qc_path = fullfile(shared_temp, 'Fusion_MR_Pseudo_CT_validation.tiff');
version_path = fullfile(shared_temp, 'Pseudo_CT_AC_Version.txt');
local_write(qc_path, 'synthetic QC');
local_write(version_path, 'synthetic version');
handoff = struct('schema', 'pseudo-CT.current-handoff/v1');
save(fullfile(shared_temp, 'mlsc_current_handoff.mat'), 'handoff', '-v6');
local_write(fullfile(shared_temp, ...
    'mlsc_current_prepare_evidence.txt'), 'prepare evidence');
local_write_verification(fullfile(shared_temp, ...
    'mlsc_current_output_verification.txt'), att_path, qc_path, version_path);
if omit_qc
    delete(qc_path);
end
end

function local_write_verification(path_name, att_path, qc_path, version_path)
att_info = dir(att_path);
qc_info = dir(qc_path);
version_info = dir(version_path);
att_sha = local_sha256(att_path);
qc_sha = local_sha256(qc_path);
version_sha = local_sha256(version_path);
V = spm_vol(att_path);
V = V(1);
dim_text = strtrim(sprintf('%g ', V.dim(:)'));
affine_text = strtrim(sprintf('%.17g ', V.mat(:)'));
fid = fopen(path_name, 'w');
assert(fid ~= -1);
fprintf(fid, 'schema: pseudo-CT.mlsc-current-output-verification/v1\n');
fprintf(fid, 'handoff: fixture-handoff\n');
fprintf(fid, 'needs_normalization: 0\n');
fprintf(fid, 'normalized_input_verified: fixture-normalized.nii\n');
fprintf(fid, 'normalized_input: bytes=10;datenum=1.000000;sha256=%s\n', ...
    version_sha);
fprintf(fid, ['output att_map.nii: bytes=%d;datenum=%.6f;' ...
    'sha256=%s\n'], att_info(1).bytes, att_info(1).datenum, att_sha);
fprintf(fid, ['output Fusion_MR_Pseudo_CT_validation.tiff: bytes=%d;' ...
    'datenum=%.6f;sha256=%s\n'], qc_info(1).bytes, ...
    qc_info(1).datenum, qc_sha);
fprintf(fid, ['output Pseudo_CT_AC_Version.txt: bytes=%d;' ...
    'datenum=%.6f;sha256=%s\n'], version_info(1).bytes, ...
    version_info(1).datenum, version_sha);
fprintf(fid, 'att_map_basename: att_map.nii\n');
fprintf(fid, 'att_map_bytes: %d\n', att_info(1).bytes);
fprintf(fid, 'att_map_sha256: %s\n', att_sha);
fprintf(fid, 'att_map_datatype: 16\n');
fprintf(fid, 'att_map_dim: %s\n', dim_text);
fprintf(fid, 'att_map_affine: %s\n', affine_text);
fprintf(fid, 'att_map_finite: 1\n');
fclose(fid);
end

function value = local_sha256(path_name)
single_quote = char(39);
quoted_path = [single_quote strrep(path_name, single_quote, ...
    [single_quote '"' single_quote '"' single_quote]) single_quote];
[status, output] = system(['sha256sum ' quoted_path ' 2>/dev/null']);
assert(status == 0, 'SHA-256 fixture utility unavailable.');
tokens = regexp(strtrim(output), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', ...
    'tokens', 'once');
assert(~isempty(tokens), 'Unable to parse SHA-256 fixture digest.');
value = lower(tokens{1});
end

function local_write(path_name, text)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'Unable to create a lifecycle fixture.');
fwrite(fid, text);
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end

function package = local_installed_fixture(test_root)
%LOCAL_INSTALLED_FIXTURE Synthetic installed-direct package; placeholder files only.
fix = fullfile(test_root, 'installed');
release_dir = fullfile(fix, 'runtimes', 'R2010b');
package = struct('root', fix, 'mcr', fullfile(fix, 'mcr'), ...
    'runner', fullfile(release_dir, 'run_pseudoct_pipeline.sh'), ...
    'resources', fullfile(fix, 'resources'));
local_make_dir(fullfile(fix, 'bin'));
local_make_dir(release_dir);
local_make_dir(fullfile(fix, 'mcr', 'runtime', 'glnxa64'));
local_make_dir(fullfile(fix, 'mcr', 'toolbox', 'compiler'));
local_make_dir(package.resources);
local_write(fullfile(fix, 'bin', 'pseudoct'), sprintf('#!/bin/sh\n'));
local_write(fullfile(fix, 'manifest.json'), sprintf('{}\n'));
local_write(package.runner, sprintf('#!/bin/sh\n# Synthetic runner fixture; never executed.\n'));
local_write(fullfile(release_dir, 'pseudoct_pipeline'), ...
    sprintf('Synthetic payload fixture; never executed.\n'));
local_write(fullfile(fix, 'mcr', 'runtime', 'glnxa64', 'libmwmclmcrrt.so.7.14'), ...
    sprintf('synthetic\n'));
local_write(fullfile(fix, 'mcr', 'toolbox', 'compiler', 'mcrversion.ver'), ...
    sprintf('7.14\n'));
names = {'ch2.nii'; 'new_segment_batch.mat'; ...
    'dartel_existing_template_batch.mat'; 'create_inverse_warped_batch.mat'; ...
    'Template_1.nii'; 'Template_2.nii'; 'Template_3.nii'; ...
    'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'; 'TPM.nii'; ...
    'Fixture_Atlas.nii'};
for ii = 1:length(names)
    local_write(fullfile(package.resources, names{ii}), sprintf('synthetic %d\n', ii));
end
end

function local_restore_env(names, values)
for ii = 1:length(names)
    setenv(names{ii}, values{ii});
end
end

function local_make_dir(directory)
if exist(directory, 'dir') ~= 7
    mkdir(directory);
end
end
