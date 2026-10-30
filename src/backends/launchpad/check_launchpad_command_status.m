% Date: May/28/2026;
% Standalone copy of the piano_mMR Launchpad status helper.

function [ss_tot, queue_time, run_time] = check_launchpad_command_status(jobname, varargin)

if nargin < 6 || ~isstruct(varargin{end})
    error('pseudo_CT:ProfileRequired', ...
        'check_launchpad_command_status requires the selected profile config.');
end
config = varargin{end};
output_context = struct();
if length(varargin) >= 6 && isstruct(varargin{end - 1})
    output_context = varargin{end - 1};
end

pause_time = 30;
init_pause = 90;
jobnum = 1;
queue_time = [];
run_time = [];

if nargin > 1
    ssh2_conn = varargin{1};
else
    [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
        'WindowName', 'Enter your Martinos Login and Password to connect to Launchpad and check your jobs!');
    HOSTNAME = config.launchpad.host;

    % Legacy output: disp('Starting the ssh connection to Launchpad to check the job status  ... (be patient!)');
    pseudo_CT_output('INFO', output_context, 'Connecting to Launchpad to check job status.');
    ssh2_conn = ssh2_config(HOSTNAME, USERNAME, PASSWORD);
end
if nargin > 2
    pause_time = varargin{2};
end
if nargin > 3
    init_pause = varargin{3};
end
if nargin > 4
    jobnum = varargin{4};
end

% Legacy output: disp(sprintf('\nWaiting for %d seconds to start verifying ... ', init_pause));
pseudo_CT_output('INFO', output_context, 'Waiting %d seconds before the first status check.', init_pause);
pause(init_pause);
if ~iscell(jobname)
    aux = jobname;
    clear jobname;
    jobname{1, :} = aux;
end
ss_tot = [];
if isrow(jobname)
    jobname = jobname';
end
for ii=1:length(jobname)
    jobn = jobname{ii, :};
    jnum = jobnum(:, ii);
    ss = [];
    ssh2_conn = ssh2_command(ssh2_conn, sprintf('cat /pbs/%s/%s.status | grep compute', ssh2_conn.username, jobn));
    node = ssh2_command_response(ssh2_conn);
    counter = 0;
    f = 0;
    nodedown{1, 1} = '';
    while length(ss) == 0
        if counter * pause_time > 3000
            ssh2_conn = ssh2_command(ssh2_conn, sprintf('ping %s.nmr.mgh.harvard.edu -c 1 | grep "Destination Host Unreachable"', node{1, 1}));
            nodedown = ssh2_command_response(ssh2_conn);
            counter = 0;
        end

        ssh2_conn = ssh2_command(ssh2_conn, sprintf('cat /pbs/%s/%s.status', ssh2_conn.username, jobn));
        commando = ssh2_command_response(ssh2_conn);
        if length(nodedown{1, 1}) == 0
            commando = commando{end};
            ss = strfind(commando, 'status ');
            if length(ss) ~= 0
                break;
            end
            pause(pause_time);
            counter = counter + 1;
        else
            keep_command{f, :} = commando{4, :}; %#ok<AGROW>
            f = f + 1;
            commando(ss+7:end) = '';
            commando = [commando, '707'];
        end
    end
    ssh2_conn = ssh2_command(ssh2_conn, sprintf('jobinfo %i', jnum));
    ss_tot(ii) = str2num(commando(ss+7:end)); %#ok<ST2NM>
    if ss_tot(ii) ~= 0
        % Legacy output: disp(sprintf('\n##################################################\nSomething has gone wrong and the job %d has failed with code %d\n##################################################', jobn, ss_tot(ii)));
        detail_context = output_context;
        if isfield(detail_context, 'log_files')
            detail_context = rmfield(detail_context, 'log_files');
        end
        if isfield(output_context, 'subject_log_files') && ...
                length(output_context.subject_log_files) >= ii
            detail_context.log_file = output_context.subject_log_files{ii};
            detail_context.subject_index = ii;
            detail_context.subject_count = length(jobname);
        end
        detail_context.job_number = jnum;
        pseudo_CT_output('WARN', detail_context, ...
            'Failure detail: Launchpad job %s exited with code %d.', jobn, ss_tot(ii));
    end
    if pause_time > 60
        pause_time = 60;
    end
end
if sum(ss_tot(:)) ~= 0
    % Legacy output: disp(sprintf('Something has gone wrong with some of the jobs:\n'));
    for ii=1:length(jobname)
        % Legacy output: disp(sprintf('%s: %d\n', jobname{ii, :}, ss_tot(ii)));
    end
    return
end
% Legacy output: disp(sprintf('\n\nGood News Everyone!! The commands ran properly!\n\n'));
pseudo_CT_output('SUCCESS', output_context, 'All Launchpad jobs completed successfully.');

return
