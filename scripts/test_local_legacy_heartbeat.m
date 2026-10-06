function test_local_legacy_heartbeat()
%TEST_LOCAL_LEGACY_HEARTBEAT Deterministic local-legacy backend checks.
%   Tests ONLY (T004). No production files are altered. The helper already
%   implements T002/T003; this file verifies the PRODUCTION monitor with
%   instant fake backends and a narrow deterministic seam (injected
%   clock/process/interruption into the production wait loop), never real
%   60 s waits and never live compiled/MCR/FreeSurfer/SSH/Slurm work.
%
%   Coverage: start message, suppression before 60 s, heartbeat at ~60 s
%   via production emissions, no duplicate within interval via production,
%   HH:MM:SS via production, successful exit, nonzero propagation, exit-0
%   + missing att_map rejection, interruption unwind via production main +
%   production stop, child-disappears/unverifiable failure via production,
%   unknown/garbage status fails via production read (never infinite, never
%   success), no healthy-process timeout (long healthy run via production
%   seam), interrupt ownership (TERM forwarded, owned fake gone),
%   uncapped log (verbose output succeeds with diagnostics retained,
%   large regular output completes at full size), unchanged compiled
%   command/args/env (runner mcr staged batch 0 aliasing defaults),
%   unchanged normalization, unchanged local-current + mlsc-legacy behavior,
%   no MLSC/Slurm dependency. R2010b-compatible (char-only).
%
%   Strategy: (a) static pins that production constants/text hold (60 s
%   threshold, 30 s pause, still-running text, HH:MM:SS sprintf, fail-closed
%   read, kill -0 / SIGTERM, trap-forward, no file-size cap, seam fields), and
%   (b) deterministic seam-injected calls into the PRODUCTION monitor via
%   the '__legacy_backend_test__' dispatch plus full-main calls with a 6th
%   seam arg. Heartbeats are counted from production pseudo_CT_output
%   emissions captured with evalc. Instant fake backends verify live
%   messages without waiting. The launch wrapper publishes the status file
%   atomically (write-then-rename), so a reader observes only a missing
%   or complete file.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
src_path = genpath(fullfile(root_dir, 'src'));
old_path = path();
addpath(src_path, '-begin');
path_cleanup = onCleanup(@() local_restore_path(old_path)); %#ok<NASGU>
n_pass = 0;

config_root = fullfile(root_dir, 'src', 'config');
helper_path = fullfile(root_dir, 'src', 'core', ...
    'pseudo_CT_run_local_legacy_subject.m');
helper_source = local_read(helper_path);
lower_helper = lower(helper_source);

% --- Static pins: heartbeat contract (production loop) ---
assert(~isempty(strfind(helper_source, 'Legacy pseudo-CT started.')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, ...
    'Legacy pseudo-CT still running (elapsed %s).')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'elapsed - last_heartbeat >= 60')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'last_heartbeat = 0;')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'last_heartbeat = elapsed;')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'pause(30);')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'while true')));
n_pass = n_pass + 1;
assert(isempty(strfind(lower_helper, 'timeout_seconds')));
n_pass = n_pass + 1;
assert(isempty(strfind(lower_helper, 'accounting_timeout')));
n_pass = n_pass + 1;
assert(isempty(strfind(lower_helper, 'max_polls')));
n_pass = n_pass + 1;

% --- Static pins: completion / failure messages ---
assert(~isempty(strfind(helper_source, ...
    'Legacy pseudo-CT completed (elapsed %s).')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'Backend exit status: %d.')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'Verifying attenuation map.')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, ...
    'Required attenuation map was not found.')));
n_pass = n_pass + 1;

% --- Static pins: interruption/unwind owns SIGTERM cleanup ---
assert(~isempty(strfind(helper_source, ...
    'Legacy pseudo-CT interrupted (elapsed %s).')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'Backend interrupt detail:')));
n_pass = n_pass + 1;
wait_pos = strfind(helper_source, 'local_wait_legacy_backend(');
catch_pos = strfind(helper_source, 'catch ME_backend');
assert(~isempty(wait_pos) && ~isempty(catch_pos) && ...
    wait_pos(1) < catch_pos(1));
n_pass = n_pass + 1;
assert(length(strfind(helper_source, ...
    'local_stop_legacy_backend(backend_pid)')) >= 2);
n_pass = n_pass + 1;

% --- Static pins: child-disappears/unverifiable fails closed ---
assert(~isempty(strfind(helper_source, ...
    'Backend process disappeared before reporting an exit status.')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'kill -0 %d')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'str2double(strtrim(char(raw)))')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'code == floor(code)')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'code >= 0')));
n_pass = n_pass + 1;

% --- Static pins: launch wrapper owns TERM-forward + bound, no scans ---
assert(~isempty(strfind(helper_source, ') & echo $!')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'echo $code > ')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, '.tmp')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'mv -f ')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, '2>&1')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'runner_pid=$!')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'trap ')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'kill $runner_pid')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'wait $runner_pid')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'code=$?')));
n_pass = n_pass + 1;
assert(isempty(strfind(helper_source, 'ulimit')));
n_pass = n_pass + 1;
assert(isempty(strfind(lower_helper, 'fsize')));
n_pass = n_pass + 1;
assert(isempty(strfind(lower_helper, 'mkfifo')));
n_pass = n_pass + 1;
assert(isempty(strfind(lower_helper, 'truncate')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'sprintf(''kill %d'', round(pid))')));
n_pass = n_pass + 1;
assert(isempty(strfind(helper_source, 'kill -9')));
n_pass = n_pass + 1;
assert(isempty(strfind(helper_source, 'kill -KILL')));
n_pass = n_pass + 1;
assert(isempty(strfind(helper_source, 'pgrep')));
n_pass = n_pass + 1;
assert(isempty(strfind(helper_source, 'pkill')));
n_pass = n_pass + 1;
assert(isempty(strfind(helper_source, 'ps -')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, '4096')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, ...
    'sprintf(''%02d:%02d:%02d'', hours, minutes, seconds)')));
n_pass = n_pass + 1;

% --- Static pins: deterministic seam fields (production loop) ---
assert(~isempty(strfind(helper_source, '__legacy_backend_test__')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'throw_at')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'exit_tick')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'alive_values')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'clock_values')));
n_pass = n_pass + 1;

% --- Static pins: unchanged compiled command/args/env order ---
% Canonical order: runner mcr staged batch 0 aliasing defaults.
cmd_mark = strfind(helper_source, 'runner_cmd = [');
assert(~isempty(cmd_mark));
cmd_line = helper_source(cmd_mark(1):cmd_mark(1) + 200);
order_tokens = {'q_runner', 'q_mcr', 'q_staged', 'q_batch', ...
    ''' 0 ''', 'num2str(check_aliasing)', 'q_defaults'};
order_pos = zeros(1, length(order_tokens));
for ii = 1:length(order_tokens)
    hit = strfind(cmd_line, order_tokens{ii});
    assert(~isempty(hit));
    order_pos(ii) = hit(1);
end
for ii = 2:length(order_pos)
    assert(order_pos(ii) > order_pos(ii - 1));
end
n_pass = n_pass + 1;

% --- Static pins: unchanged normalization behavior ---
assert(~isempty(strfind(helper_source, 'env -u LD_LIBRARY_PATH')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'tcsh -f -c')));
n_pass = n_pass + 1;
assert(~isempty(strfind(helper_source, 'mri_normalize')));
n_pass = n_pass + 1;

% --- Static pins: no MLSC/Slurm dependency in the helper path ---
assert(isempty(strfind(helper_source, 'config.mlsc')));
n_pass = n_pass + 1;
assert(isempty(strfind(lower_helper, 'mlsc_')));
n_pass = n_pass + 1;
isolation_words = {'sbatch', 'squeue', 'sacct', 'mlsc_backend', ...
    'mlsc_lifecycle', 'generate_slurm'};
for ii = 1:length(isolation_words)
    assert(isempty(strfind(lower_helper, isolation_words{ii})));
    n_pass = n_pass + 1;
end

% --- Static pins: R2010b boundary for the helper ---
% Needles are concatenated so the self-check below stays literal-free.
assert(isempty(strfind(helper_source, ['str' 'join('])));
n_pass = n_pass + 1;
assert(isempty(strfind(helper_source, ['add' 'Parameter'])));
n_pass = n_pass + 1;
assert(isempty(strfind(helper_source, ['str' 'ing('])));
n_pass = n_pass + 1;
assert(isempty(regexp(helper_source, ['\<' 'date' 'time' '\>'], 'once')));
n_pass = n_pass + 1;
assert(isempty(strfind(helper_source, ['tim' 'er('])));
n_pass = n_pass + 1;

% --- Static pins: unchanged local-current + mlsc-legacy behavior ---
entry_source = local_read(fullfile(root_dir, 'run_pseudo_CT.m'));
assert(~isempty(strfind(entry_source, 'switch config.mode')));
n_pass = n_pass + 1;
generate_source = local_read(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_generate_slurm_script.m'));
assert(~isempty(strfind(generate_source, ''' 0 ''')));
n_pass = n_pass + 1;
assert(~isempty(strfind(generate_source, 'num2str(check_aliasing)')));
n_pass = n_pass + 1;
assert(~isempty(strfind(generate_source, 'att_map.nii')));
n_pass = n_pass + 1;
remote_source = local_read(fullfile(root_dir, 'src', 'remote', ...
    'run_normalization_cmd.m'));
assert(~isempty(strfind(remote_source, 'setenv LD_LIBRARY_PATH')));
n_pass = n_pass + 1;
local_legacy_source = local_read(fullfile(root_dir, 'src', 'config', ...
    'profiles', 'local_legacy.m'));
assert(isempty(strfind(local_legacy_source, 'config.mlsc')));
n_pass = n_pass + 1;
assert(~isempty(strfind(local_legacy_source, 'config.legacy.runner')));
n_pass = n_pass + 1;
assert(~isempty(strfind(local_legacy_source, 'att_map.nii')));
n_pass = n_pass + 1;
mlsc_legacy_source = local_read(fullfile(root_dir, 'src', 'config', ...
    'profiles', 'mlsc_legacy.m'));
assert(~isempty(strfind(mlsc_legacy_source, ...
    'mlsc.nmr.mgh.harvard.edu')));
n_pass = n_pass + 1;
local_current_cfg = pseudo_CT_load_profile('local-current', config_root);
local_legacy_cfg = pseudo_CT_load_profile('local-legacy', config_root);
mlsc_legacy_cfg = pseudo_CT_load_profile('mlsc-legacy', config_root);
assert(strcmp(local_current_cfg.mode, 'local') && ...
    strcmp(local_current_cfg.implementation, 'current'));
n_pass = n_pass + 1;
assert(strcmp(local_legacy_cfg.mode, 'local') && ...
    strcmp(local_legacy_cfg.implementation, 'legacy-v2'));
n_pass = n_pass + 1;
assert(strcmp(mlsc_legacy_cfg.mode, 'mlsc') && ...
    strcmp(mlsc_legacy_cfg.implementation, 'legacy-v2'));
n_pass = n_pass + 1;

% --- Static pins: this test file itself stays R2010b-compatible ---
% Needles are concatenated so this self-check does not match its own text.
self_source = local_read([mfilename('fullpath') '.m']);
assert(isempty(strfind(self_source, ['str' 'join('])));
n_pass = n_pass + 1;
assert(isempty(strfind(self_source, ['add' 'Parameter'])));
n_pass = n_pass + 1;
assert(isempty(strfind(self_source, ['str' 'ing('])));
n_pass = n_pass + 1;
assert(isempty(regexp(self_source, ['\<' 'date' 'time' '\>'], 'once')));
n_pass = n_pass + 1;
assert(isempty(strfind(self_source, ['tim' 'er('])));
n_pass = n_pass + 1;
assert(isempty(strfind(self_source, ['local_' 'simulate_wait'])));
n_pass = n_pass + 1;
assert(isempty(strfind(self_source, ['local_' 'model_'])));
n_pass = n_pass + 1;
assert(isempty(strfind(self_source, ['Poll ' 'bound'])));
n_pass = n_pass + 1;

% --- Live pins: instant fake backends + evalc capture (no 60 s waits) ---
[fixture, fixture_cleanup] = local_build_fixture(local_legacy_cfg); %#ok<NASGU>
old_matlab_path = path();
old_path_env = getenv('PATH');
old_fs_env = getenv('LOCAL_LEGACY_FS_LOG');
old_runner_env = getenv('LOCAL_LEGACY_RUNNER_LOG');
addpath(fixture.stub_dir, '-begin');
clear('dcm2nii');
rehash;
stub_cleanup = onCleanup(@() local_restore_stub(old_matlab_path)); %#ok<NASGU>
setenv('PATH', [fixture.fake_bin pathsep old_path_env]);
setenv('LOCAL_LEGACY_FS_LOG', fixture.fs_log);
setenv('LOCAL_LEGACY_RUNNER_LOG', fixture.runner_log);
env_cleanup = onCleanup(@() local_restore_env(old_path_env, old_fs_env, old_runner_env)); %#ok<NASGU>

% Success: start message, suppression before 60 s, elapsed HH:MM:SS.
cfg_ok = fixture.cfg_base;
cfg_ok.legacy.runner = fixture.runner_ok;
job_ok = struct('mprage_fn', fixture.input_file, ...
    'temp_dir', fixture.temp_ok, 'processing_dir', fixture.proc_ok);
job_ok.correct_aliasing = 1;
if exist(fixture.fs_log, 'file') == 2
    delete(fixture.fs_log);
end
if exist(fixture.runner_log, 'file') == 2
    delete(fixture.runner_log);
end
captured_ok = '';
ok_result = 0;
[ok_result, captured_ok] = local_run_legacy(job_ok, cfg_ok);
assert(ok_result == 1);
n_pass = n_pass + 1;
assert(~isempty(strfind(captured_ok, 'Legacy pseudo-CT started.')));
n_pass = n_pass + 1;
assert(isempty(strfind(captured_ok, 'still running')));
n_pass = n_pass + 1;
assert(~isempty(strfind(captured_ok, 'Legacy pseudo-CT completed')));
n_pass = n_pass + 1;
assert(~isempty(regexp(captured_ok, '\d{2}:\d{2}:\d{2}', 'once')));
n_pass = n_pass + 1;
assert(exist(fullfile(fixture.temp_ok, 'att_map.nii'), 'file') == 2);
n_pass = n_pass + 1;
assert(exist(fullfile(fixture.proc_ok, 'att_map.nii'), 'file') == 2);
n_pass = n_pass + 1;
fs_lines = local_read_lines(fixture.fs_log);
assert(length(fs_lines) == 2);
n_pass = n_pass + 1;
assert(strcmp(fs_lines{2}, fullfile(fixture.temp_ok, ...
    'mprage_normalized.nii')));
n_pass = n_pass + 1;
runner_lines = local_read_lines(fixture.runner_log);
assert(length(runner_lines) == 6);
n_pass = n_pass + 1;
assert(strcmp(runner_lines{1}, fixture.mcr_dir));
n_pass = n_pass + 1;
assert(strcmp(runner_lines{2}, fullfile(fixture.temp_ok, ...
    'mprage_normalized.nii')));
n_pass = n_pass + 1;
assert(strcmp(runner_lines{3}, fixture.batch_dir));
n_pass = n_pass + 1;
assert(strcmp(runner_lines{4}, '0'));
n_pass = n_pass + 1;
assert(strcmp(runner_lines{5}, '1'));
n_pass = n_pass + 1;
assert(strcmp(runner_lines{6}, fixture.defaults_file));
n_pass = n_pass + 1;

% Nonzero exit propagates as failure with the status in the message.
cfg_fail = fixture.cfg_base;
cfg_fail.legacy.runner = fixture.runner_fail;
job_fail = struct('mprage_fn', fixture.input_file, ...
    'temp_dir', fixture.temp_fail, 'processing_dir', fixture.proc_fail);
job_fail.correct_aliasing = 1;
if exist(fixture.runner_log, 'file') == 2
    delete(fixture.runner_log);
end
captured_fail = '';
fail_result = 0;
[fail_result, captured_fail] = local_run_legacy(job_fail, cfg_fail);
assert(fail_result == 0);
n_pass = n_pass + 1;
assert(~isempty(strfind(captured_fail, 'Backend exit status: 7.')));
n_pass = n_pass + 1;
assert(exist(fullfile(fixture.temp_fail, 'att_map.nii'), 'file') ~= 2);
n_pass = n_pass + 1;

% Exit-0 with missing att_map still rejects at the verified gate.
cfg_noatt = fixture.cfg_base;
cfg_noatt.legacy.runner = fixture.runner_noatt;
job_noatt = struct('mprage_fn', fixture.input_file, ...
    'temp_dir', fixture.temp_noatt, 'processing_dir', fixture.proc_noatt);
job_noatt.correct_aliasing = 1;
captured_noatt = '';
noatt_result = 0;
[noatt_result, captured_noatt] = local_run_legacy(job_noatt, cfg_noatt);
assert(noatt_result == 0);
n_pass = n_pass + 1;
assert(~isempty(strfind(captured_noatt, ...
    'Required attenuation map was not found.')));
n_pass = n_pass + 1;

% Interruption via PRODUCTION unwind + stop: seam throw inside the
% production wait must surface as the production interrupted message.
cfg_int = fixture.cfg_base;
cfg_int.legacy.runner = fixture.runner_ok;
job_int = struct('mprage_fn', fixture.input_file, ...
    'temp_dir', [fixture.temp_ok '_int'], 'processing_dir', [fixture.proc_ok '_int']);
job_int.correct_aliasing = 1;
seam_int = struct('exit_tick', Inf, 'exit_code', 0, ...
    'alive_values', [1 1 1 1], 'clock_values', [0 0 0 0], 'throw_at', 2);
captured_int = '';
int_result = 1;
[int_result, captured_int] = local_run_legacy_seam(job_int, cfg_int, seam_int);
assert(int_result == 0);
n_pass = n_pass + 1;
assert(~isempty(strfind(captured_int, 'Legacy pseudo-CT interrupted')));
n_pass = n_pass + 1;
assert(~isempty(strfind(captured_int, 'Backend interrupt detail:')));
n_pass = n_pass + 1;
assert(~isempty(strfind(captured_int, 'Simulated backend wait interrupt.')));
n_pass = n_pass + 1;

% Uncapped log via PRODUCTION launch: a verbose backend writing ~25 MB to
% stdout must now succeed with the full log retained, and a ~27 MB regular
% output file must also complete at full size (the wrapper sets no
% file-size limit). Fast: head -c from /dev/zero, no minute waits.
verbose_runner = fullfile(fixture.fake_bin, 'runner verbose with space.sh');
local_write(verbose_runner, ...
    ['#!/bin/bash' char(10) ...
     'printf ''%s\n'' "$1" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
     'printf ''%s\n'' "$2" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
     'printf ''%s\n'' "$3" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
     'printf ''%s\n'' "$4" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
     'printf ''%s\n'' "$5" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
     'printf ''%s\n'' "$6" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
     'att_dir=$(dirname "$2")' char(10) ...
     'printf ''fixture-att-map'' > "$att_dir/att_map.nii"' char(10) ...
     'head -c 26214400 /dev/zero' char(10) ...
     'head -c 28311552 /dev/zero > "$att_dir/large_output.bin"' char(10) ...
     'exit 0' char(10)]);
local_make_executable(verbose_runner);
cfg_verbose = fixture.cfg_base;
cfg_verbose.legacy.runner = verbose_runner;
job_verbose = struct('mprage_fn', fixture.input_file, ...
    'temp_dir', [fixture.temp_ok '_verbose'], 'processing_dir', [fixture.proc_ok '_verbose']);
job_verbose.correct_aliasing = 1;
if exist(fixture.runner_log, 'file') == 2
    delete(fixture.runner_log);
end
captured_verbose = '';
verbose_result = 0;
[verbose_result, captured_verbose] = local_run_legacy(job_verbose, cfg_verbose);
assert(verbose_result == 1);
n_pass = n_pass + 1;
assert(~isempty(strfind(captured_verbose, 'Legacy pseudo-CT completed')));
n_pass = n_pass + 1;
verbose_log = fullfile(job_verbose.temp_dir, 'legacy_backend.log');
verbose_info = dir(verbose_log);
assert(~isempty(verbose_info) && verbose_info(1).bytes >= 26214400);
n_pass = n_pass + 1;
large_info = dir(fullfile(job_verbose.temp_dir, 'large_output.bin'));
assert(~isempty(large_info) && large_info(1).bytes == 28311552);
n_pass = n_pass + 1;
assert(exist(fullfile(job_verbose.processing_dir, 'att_map.nii'), 'file') == 2);
n_pass = n_pass + 1;
verbose_runner_lines = local_read_lines(fixture.runner_log);
assert(length(verbose_runner_lines) == 6);
n_pass = n_pass + 1;
assert(strcmp(verbose_runner_lines{5}, '1'));
n_pass = n_pass + 1;

path(old_matlab_path);
clear('dcm2nii');
rehash;
setenv('PATH', old_path_env);
setenv('LOCAL_LEGACY_FS_LOG', old_fs_env);
setenv('LOCAL_LEGACY_RUNNER_LOG', old_runner_env);

% --- Production seam: heartbeat / timing via production emissions ---
% All calls below go through the PRODUCTION wait loop via the
% '__legacy_backend_test__' dispatch with injected clock/process. No model.
invoke_context = struct('log_file', '', 'subject_index', 1, ...
    'subject_count', 1, 'scope', 'subject', 'stage_index', 3, ...
    'stage_count', 8);

% Instant completion suppresses the heartbeat (mirrors live runs above).
seam_fast = struct('exit_tick', 1, 'exit_code', 0, ...
    'alive_values', 1, 'clock_values', 0);
[captured_fast, res_fast] = local_test_wait(seam_fast);
assert(res_fast.completed && res_fast.exit_status == 0);
n_pass = n_pass + 1;
assert(isempty(strfind(captured_fast, 'still running')));
n_pass = n_pass + 1;

% Heartbeat fires once the production clock reaches ~60 s.
seam_beat = struct('exit_tick', 4, 'exit_code', 0, ...
    'alive_values', [1 1 1 1], 'clock_values', [0 30 60 61]);
[captured_beat, res_beat] = local_test_wait(seam_beat);
assert(res_beat.completed && res_beat.exit_status == 0);
n_pass = n_pass + 1;
assert(length(strfind(captured_beat, 'still running')) == 1);
n_pass = n_pass + 1;
assert(~isempty(regexp(captured_beat, '\d{2}:\d{2}:\d{2}', 'once')));
n_pass = n_pass + 1;

% No duplicate within the interval: 0..122 s emits exactly at 60 and 120.
seam_two = struct('exit_tick', 10, 'exit_code', 0, ...
    'alive_values', ones(1, 10), ...
    'clock_values', [0 30 60 61 65 90 119 120 121 122]);
[captured_two, res_two] = local_test_wait(seam_two);
assert(res_two.completed);
n_pass = n_pass + 1;
assert(length(strfind(captured_two, 'still running')) == 2);
n_pass = n_pass + 1;

% No healthy-process timeout: a 2 h healthy run still completes via production.
long_alive = ones(1, 242);
long_clock = (0:241) * 30;
seam_long = struct('exit_tick', 242, 'exit_code', 0, ...
    'alive_values', long_alive, 'clock_values', long_clock);
[captured_long, res_long] = local_test_wait(seam_long);
assert(res_long.completed && res_long.exit_status == 0);
n_pass = n_pass + 1;
assert(length(strfind(captured_long, 'still running')) == 120);
n_pass = n_pass + 1;

% Child-disappears/unverifiable reads as failure via production, never success.
seam_gone = struct('exit_tick', Inf, 'exit_code', 0, ...
    'alive_values', [1 1 0 0], 'clock_values', [0 30 60 90]);
[captured_gone, res_gone] = local_test_wait(seam_gone);
assert(~res_gone.completed && res_gone.exit_status == -1);
n_pass = n_pass + 1;
assert(~isempty(strfind(res_gone.failure_reason, 'disappeared')));
n_pass = n_pass + 1;
assert(isempty(strfind(captured_gone, 'still running')));
n_pass = n_pass + 1;

% Unknown/garbage status fails via PRODUCTION read, never infinite/never success.
garbage_dir = tempname;
mkdir(garbage_dir);
garbage_cleanup = onCleanup(@() local_cleanup(garbage_dir)); %#ok<NASGU>
garbage_path = fullfile(garbage_dir, 'legacy_backend.exit');
local_write(garbage_path, 'abc');
seam_garbage = struct('alive_values', 0, 'clock_values', 0);
req_garbage = struct('op', 'wait', 'pid', 999999, 'status_path', garbage_path, ...
    'invoke_context', invoke_context, 'backend_started', tic, 'seam', seam_garbage);
res_garbage = pseudo_CT_run_local_legacy_subject('__legacy_backend_test__', req_garbage);
assert(~res_garbage.completed && res_garbage.exit_status == -1);
n_pass = n_pass + 1;
assert(~isempty(strfind(res_garbage.failure_reason, 'disappeared')));
n_pass = n_pass + 1;

% Fail-closed exit parsing via PRODUCTION read (real files, no replica).
parse_cases = {'0', true, 0; '7', true, 7; '', false, -1; ...
    'abc', false, -1; '-1', false, -1; '1.5', false, -1};
for ii = 1:size(parse_cases, 1)
    parse_dir = tempname;
    mkdir(parse_dir);
    parse_file = fullfile(parse_dir, 'exit');
    local_write(parse_file, parse_cases{ii, 1});
    res_parse = pseudo_CT_run_local_legacy_subject('__legacy_backend_test__', ...
        struct('op', 'read', 'status_path', parse_file));
    if parse_cases{ii, 2}
        assert(res_parse.found && res_parse.exit_status == parse_cases{ii, 3});
    else
        assert(~res_parse.found);
    end
    n_pass = n_pass + 1;
    rmdir(parse_dir, 's');
end

% Interruption propagates from the PRODUCTION wait (unwind owns stop).
seam_throw = struct('exit_tick', Inf, 'exit_code', 0, ...
    'alive_values', [1 1 1], 'clock_values', [0 0 0], 'throw_at', 2);
threw = false;
throw_msg = '';
try
    local_test_wait(seam_throw);
catch ME
    threw = true;
    throw_msg = ME.message;
end
assert(threw && ~isempty(strfind(throw_msg, 'Simulated backend wait interrupt.')));
n_pass = n_pass + 1;

% Interrupt ownership via PRODUCTION launch/stop: TERM to the owned wrapper
% must terminate the owned fake runner (sleep 300); assert both gone.
own_dir = [tempname ' own'];
mkdir(own_dir);
own_log = fullfile(own_dir, 'b.log');
own_status = fullfile(own_dir, 'b.exit');
own_pidfile = fullfile(own_dir, 'runner.pid');
own_script = fullfile(own_dir, 'runner sleep with space.sh');
local_write(own_script, ...
    ['#!/bin/bash' char(10) ...
     ['echo $$ > ' local_shell_quote(own_pidfile)] char(10) ...
     'exec sleep 300' char(10)]);
local_make_executable(own_script);
own_q = local_shell_quote(own_script);
res_launch = pseudo_CT_run_local_legacy_subject('__legacy_backend_test__', ...
    struct('op', 'launch', 'runner_cmd', own_q, 'log_path', own_log, 'status_path', own_status));
assert(res_launch.pid > 0);
n_pass = n_pass + 1;
pause(1);
own_runner_pid = str2double(strtrim(local_read(own_pidfile)));
assert(isfinite(own_runner_pid) && own_runner_pid > 0);
n_pass = n_pass + 1;
[own_w0, ~] = system(sprintf('kill -0 %d', round(res_launch.pid)));
[own_r0, ~] = system(sprintf('kill -0 %d', round(own_runner_pid)));
assert(own_w0 == 0 && own_r0 == 0);
n_pass = n_pass + 1;
pseudo_CT_run_local_legacy_subject('__legacy_backend_test__', ...
    struct('op', 'stop', 'pid', res_launch.pid));
pause(3);
[own_w1, ~] = system(sprintf('kill -0 %d', round(res_launch.pid)));
[own_r1, ~] = system(sprintf('kill -0 %d', round(own_runner_pid)));
assert(own_w1 ~= 0 && own_r1 ~= 0);
n_pass = n_pass + 1;
rmdir(own_dir, 's');

% HH:MM:SS via PRODUCTION elapsed (no replica).
elapsed_cases = {'00:00:00', 0; '00:00:59', 59; '00:01:00', 60; ...
    '00:59:59', 3599; '01:00:00', 3600; '01:01:01', 3661; ...
    '02:00:00', 7200; '25:01:01', 90061};
for ii = 1:size(elapsed_cases, 1)
    res_elapsed = pseudo_CT_run_local_legacy_subject('__legacy_backend_test__', ...
        struct('op', 'elapsed', 'seconds', elapsed_cases{ii, 2}));
    assert(strcmp(res_elapsed.text, elapsed_cases{ii, 1}));
    n_pass = n_pass + 1;
end

fprintf(['Local-legacy heartbeat tests passed: %d checks, start/ ' ...
    'suppression/heartbeat-once, HH:MM:SS, exit and gate behavior, ' ...
    'production unwind/stop/ownership, uncapped log, fail-closed production.\n'], ...
    n_pass);
end

function [result, captured] = local_run_legacy(job, cfg)
%LOCAL_RUN_LEGACY Single live legacy-backend invocation.
%   The status file is published atomically (write-then-rename), so an
%   instant backend deterministically reports without a retry.
result = 0;
captured = evalc( ...
    'result = pseudo_CT_run_local_legacy_subject(job, cfg, 1, 1, false);');
end

function [result, captured] = local_run_legacy_seam(job, cfg, seam)
%LOCAL_RUN_LEGACY_SEAM Full-main invocation with an injected wait seam.
%   Exercises the production unwind path (catch + stop + messages).
result = 0;
captured = evalc( ...
    'result = pseudo_CT_run_local_legacy_subject(job, cfg, 1, 1, false, seam);');
end

function [captured, res] = local_test_wait(seam)
%LOCAL_TEST_WAIT Production wait via dispatch with evalc capture.
%   Heartbeats are production pseudo_CT_output emissions, not a model.
invoke_context = struct('log_file', '', 'subject_index', 1, ...
    'subject_count', 1, 'scope', 'subject', 'stage_index', 3, ...
    'stage_count', 8);
req = struct('op', 'wait', 'pid', 999999, 'status_path', tempname, ...
    'invoke_context', invoke_context, 'backend_started', tic, 'seam', seam);
captured = '';
res = struct('completed', false, 'exit_status', -1, 'failure_reason', '');
captured = evalc('res = pseudo_CT_run_local_legacy_subject(''__legacy_backend_test__'', req);');
end

function [fixture, fixture_cleanup] = local_build_fixture(base_config)
fixture_root = [tempname ' with space'];
mkdir(fixture_root);
fixture_cleanup = onCleanup(@() local_cleanup(fixture_root)); %#ok<NASGU>
stub_dir = fullfile(fixture_root, 'stub dir');
fake_bin = fullfile(fixture_root, 'fake bin');
fixture_data = fullfile(fixture_root, 'fixture data with space');
mkdir(stub_dir);
mkdir(fake_bin);
mkdir(fixture_data);
local_write(fullfile(stub_dir, 'dcm2nii.m'), ...
    ['function out_path = dcm2nii(in_path, out_path, varargin)' char(10) ...
     'if ~ischar(in_path) || ~ischar(out_path)' char(10) ...
     'error(''fixture:InvalidPath'', ''paths must be char'');' char(10) ...
     'end' char(10) ...
     '[copy_ok, copy_msg] = copyfile(in_path, out_path, ''f'');' char(10) ...
     'if ~copy_ok' char(10) ...
     'error(''fixture:CopyFailed'', ''copy failed: %s'', copy_msg);' char(10) ...
     'end' char(10) 'end' char(10)]);
local_write(fullfile(fake_bin, 'mri_normalize'), ...
    ['#!/bin/bash' char(10) ...
     'printf ''%s\n'' "$1" >> "$LOCAL_LEGACY_FS_LOG"' char(10) ...
     'printf ''%s\n'' "$2" >> "$LOCAL_LEGACY_FS_LOG"' char(10) ...
     'cp -- "$1" "$2"' char(10)]);
mcr_dir = fullfile(fixture_data, 'mcr root with space');
batch_dir = fullfile(fixture_data, 'batch templates with space');
atlas_dir = fullfile(fixture_data, 'atlas root with space');
mkdir(mcr_dir);
mkdir(batch_dir);
mkdir(atlas_dir);
defaults_file = fullfile(fixture_data, 'defaults file with space.mat');
local_write(defaults_file, 'fixture');
env_file = fullfile(fixture_data, 'freesurfer env with space');
local_write(env_file, ['setenv LOCAL_LEGACY_FIXTURE 1' char(10)]);
input_dir = fullfile(fixture_data, 'input dir with space');
mkdir(input_dir);
input_file = fullfile(input_dir, 'input image with space.nii');
local_write(input_file, 'MPRAGE-FIXTURE');
runner_ok = fullfile(fixture_data, 'runner ok with space.sh');
runner_fail = fullfile(fixture_data, 'runner fail with space.sh');
runner_noatt = fullfile(fixture_data, 'runner noatt with space.sh');
runner_body = ['printf ''%s\n'' "$1" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$2" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$3" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$4" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$5" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$6" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10)];
local_write(runner_ok, ['#!/bin/bash' char(10) runner_body ...
    'att_dir=$(dirname "$2")' char(10) ...
    'printf ''fixture-att-map'' > "$att_dir/att_map.nii"' char(10) ...
    'exit 0' char(10)]);
local_write(runner_fail, ['#!/bin/bash' char(10) runner_body 'exit 7' char(10)]);
local_write(runner_noatt, ['#!/bin/bash' char(10) runner_body 'exit 0' char(10)]);
local_make_executable(fullfile(fake_bin, 'mri_normalize'));
local_make_executable(runner_ok);
local_make_executable(runner_fail);
local_make_executable(runner_noatt);
cfg_base = base_config;
cfg_base.atlas_root = atlas_dir;
cfg_base.normalization.source_command = ['source ' env_file];
cfg_base.io_policy.output = 'nifti-only';
cfg_base.cleanup_on_success = false;
cfg_base.legacy.runner = runner_ok;
cfg_base.legacy.mcr_root = mcr_dir;
cfg_base.legacy.defaults_mat = defaults_file;
cfg_base.legacy.batch_templates = batch_dir;
fixture = struct('stub_dir', stub_dir, 'fake_bin', fake_bin, ...
    'mcr_dir', mcr_dir, 'batch_dir', batch_dir, ...
    'defaults_file', defaults_file, 'input_file', input_file, ...
    'runner_ok', runner_ok, 'runner_fail', runner_fail, ...
    'runner_noatt', runner_noatt, ...
    'fs_log', fullfile(fixture_data, 'fs.log'), ...
    'runner_log', fullfile(fixture_data, 'runner.log'), ...
    'cfg_base', cfg_base, ...
    'temp_ok', fullfile(fixture_data, 'temp ok with space'), ...
    'proc_ok', fullfile(fixture_data, 'proc ok with space'), ...
    'temp_fail', fullfile(fixture_data, 'temp fail with space'), ...
    'proc_fail', fullfile(fixture_data, 'proc fail with space'), ...
    'temp_noatt', fullfile(fixture_data, 'temp noatt with space'), ...
    'proc_noatt', fullfile(fixture_data, 'proc noatt with space'));
end

function local_make_executable(file_path)
[status, detail] = system(['/bin/chmod 700 ' local_shell_quote(file_path)]);
assert(status == 0, detail);
end

function quoted = local_shell_quote(value)
single_quote = char(39);
quoted = single_quote;
for ii = 1:length(value)
    if value(ii) == single_quote
        quoted = [quoted single_quote char(34) single_quote char(34) single_quote]; %#ok<AGROW>
    else
        quoted = [quoted value(ii)]; %#ok<AGROW>
    end
end
quoted = [quoted single_quote];
end

function lines = local_read_lines(file_path)
fid = fopen(file_path, 'r');
assert(fid ~= -1);
text = fread(fid, inf, '*char')';
fclose(fid);
lines = regexp(text, '\r\n|\n|\r', 'split');
if ~isempty(lines) && isempty(lines{end})
    lines = lines(1:end-1);
end
lines = lines(:);
end

function text = local_read(file_path)
fid = fopen(file_path, 'r');
assert(fid ~= -1);
text = fread(fid, inf, '*char')';
fclose(fid);
end

function local_write(file_path, text)
fid = fopen(file_path, 'w');
assert(fid ~= -1);
fwrite(fid, text);
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end

function local_restore_path(old_path)
path(old_path);
end

function local_restore_stub(old_path)
clear('dcm2nii');
path(old_path);
try
    rehash;
catch %#ok<CTCH>
end
end

function local_restore_env(old_path, old_fs, old_runner)
setenv('PATH', old_path);
setenv('LOCAL_LEGACY_FS_LOG', old_fs);
setenv('LOCAL_LEGACY_RUNNER_LOG', old_runner);
end
