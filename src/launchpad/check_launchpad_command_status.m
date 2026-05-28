% Date: May/28/2026;
% Standalone copy of the piano_mMR Launchpad status helper.

function [ss_tot, queue_time, run_time] = check_launchpad_command_status(jobname, varargin)

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
    HOSTNAME = defaults_pseudo_CT_launchpad('HOSTNAME');

    disp('Starting the ssh connection to Launchpad to check the job status  ... (be patient!)');
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

disp(sprintf('\nWaiting for %d seconds to start verifying ... ', init_pause));
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
        disp(sprintf('\n##################################################\nSomething has gone wrong and the job %d has failed with code %d\n##################################################', jobn, ss_tot(ii)));
    end
    if pause_time > 60
        pause_time = 60;
    end
end
if sum(ss_tot(:)) ~= 0
    disp(sprintf('Something has gone wrong with some of the jobs:\n'));
    for ii=1:length(jobname)
        disp(sprintf('%s: %d\n', jobname{ii, :}, ss_tot(ii)));
    end
    return
end
disp(sprintf('\n\nGood News Everyone!! The commands ran properly!\n\n'));

return