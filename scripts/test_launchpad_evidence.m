function test_launchpad_evidence()
%TEST_LAUNCHPAD_EVIDENCE RED-first bounded lifecycle non-regression checks.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'launchpad'));
state = struct('profile', 'launchpad', 'subject_count', 1, ...
    'jobname', 'pbsjob_123', 'jobnum', 123, 'exit_status', 0, ...
    'pbs_logs', {{'job.o123', 'job.e123'}}, 'att_map_present', true, ...
    'cleanup', 'remote-scratch-removed');

first = launchpad_evidence('init', state);
second = launchpad_evidence('init', state);
assert(isequal(first, second), 'Identical lifecycle snapshots must be bytewise stable.');
next = launchpad_evidence('polling', first, struct('exit_status', 0));
next = launchpad_evidence('pbs_logs', next, struct('pbs_logs', state.pbs_logs));
next = launchpad_evidence('retrieval', next, struct('att_map_present', true));
next = launchpad_evidence('cleanup', next, struct('cleanup', state.cleanup));
assert(strcmp(next.schema, 'pseudo-CT.launchpad-evidence/v1'));
assert(length(next.lifecycle) == 5);
assert(strcmp(next.lifecycle{1}, 'init') && strcmp(next.lifecycle{end}, 'cleanup'));
assert(next.exit_status == 0 && next.att_map_present);
test_missing_att_map(root_dir);
fprintf('=== Launchpad evidence tests passed: lifecycle state and legacy 711 output gate ===\n');
end

function test_missing_att_map(root_dir)
% Exercise the retained Launchpad missing-output behavior with local stubs.
% No SSH, PBS, SCP, or remote command is reached by this test.
test_dir = tempname;
mkdir(test_dir);
stub_dir = fullfile(test_dir, 'stubs');
mkdir(stub_dir);
old_path = path();
cleanup = onCleanup(@() local_restore_test_path(old_path, test_dir)); %#ok<NASGU>

local_write(fullfile(stub_dir, 'ssh2_config.m'), ...
    ['function connection = ssh2_config(hostname, username, ignored)' char(10) ...
     'connection.hostname = hostname;' char(10) ...
     'connection.username = username;' char(10) 'end' char(10)]);
local_write(fullfile(stub_dir, 'ssh2_command.m'), ...
    ['function varargout = ssh2_command(connection, command, varargin)' char(10) ...
     'varargout{1} = connection;' char(10) ...
     'if nargout > 1' char(10) '    varargout{2} = '''';' char(10) ...
     'end' char(10) 'end' char(10)]);
local_write(fullfile(stub_dir, 'scp_put.m'), ...
    ['function connection = scp_put(connection, varargin)' char(10) ...
     'end' char(10)]);
local_write(fullfile(stub_dir, 'scp_get.m'), ...
    ['function connection = scp_get(connection, varargin)' char(10) ...
     'end' char(10)]);
local_write(fullfile(stub_dir, 'run_launchpad_cmd_return.m'), ...
    ['function [connection, jobname, jobnum] = run_launchpad_cmd_return(varargin)' char(10) ...
     'connection = varargin{2};' char(10) ...
     'jobname = ''pbsjob_stub'';' char(10) 'jobnum = 123;' char(10) 'end' char(10)]);
local_write(fullfile(stub_dir, 'check_launchpad_command_status.m'), ...
    ['function status = check_launchpad_command_status(varargin)' char(10) ...
     'status = 0;' char(10) 'end' char(10)]);
local_write(fullfile(stub_dir, 'ssh2_close.m'), ...
    ['function connection = ssh2_close(connection)' char(10) ...
     'end' char(10)]);

addpath(fullfile(root_dir, 'src', 'launchpad'), '-begin');
addpath(fullfile(root_dir, 'src', 'io'), '-begin');
addpath(stub_dir, '-begin');
clear('batch_pseudo_CT_launchpad', 'ssh2_config', 'ssh2_command', ...
    'scp_put', 'scp_get', 'run_launchpad_cmd_return', ...
    'check_launchpad_command_status', 'ssh2_close');

input_path = fullfile(test_dir, 'subject input.nii');
local_write(input_path, 'input');
config = struct();
config.aliasing_default = 1;
config.launchpad = struct('host', 'fixture-launchpad', ...
    'runner', 'fixture-runner', 'mcr_root', 'fixture-mcr', ...
    'defaults_mat', 'fixture-defaults', 'batch_templates', ...
    'fixture-batch', 'queue', '', 'scratch', fullfile(test_dir, 'scratch'));
ssh_log = {'fixture-user', 'fixture-value', 'fixture-host'};
[~, ~, ~, status] = batch_pseudo_CT_launchpad(input_path, ssh_log, ...
    'clean_folder', 0, 'keep_tmp', 0, config);
assert(status == 711);
assert(exist(fullfile(test_dir, 'att_map.nii'), 'file') ~= 2);
end

function local_restore_test_path(old_path, test_dir)
clear('batch_pseudo_CT_launchpad', 'ssh2_config', 'ssh2_command', ...
    'scp_put', 'scp_get', 'run_launchpad_cmd_return', ...
    'check_launchpad_command_status', 'ssh2_close');
path(old_path);
if exist(test_dir, 'dir') == 7
    rmdir(test_dir, 's');
end
end

function local_write(file_path, text)
fid = fopen(file_path, 'w');
assert(fid ~= -1, 'Could not create the Launchpad fixture.');
fwrite(fid, text);
fclose(fid);
end
