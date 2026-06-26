% Date: 06/21/2013;
% Name: run_launchpad_cmd.m;
% Function to run a command in launchpad (cluster) using the ssh commands
% from matlab;
% Inputs: - cmd: the command to run on launchpad. It needs to be starting
%           with a " (and eventually finish with another ", except for
%           other flags);
%         - ssh2_conn: (optional) if available, the ssh connection to a
%         host;
%         - pause_time: (optional) the waiting time in sec between consecutive
%         checks of the command to finish. Default value 30 sec.
%         - init_pause: (optional) the initial waiting time in sec to start
%         checking for the command to finish. Default value: 90 sec.
%
% Output: - sts: the exit status of the command (from launchpad). If 0 then
%           command finshed properly, otherwise there was some problem.
%
% To use: [sts] = run_launchpad_cmd(cmd, ssh2_conn, pause_time, init_pause)
%
% By David Izquierdo-Garcia.
% Athinoula A. Martinos Center.
% Harvard University / Mass. General Hospital. Boston.

function [sts] = run_launchpad_cmd(cmd, varargin)

if strcmp(cmd(1), '"') == 0
    disp(sprintf('The command should start (and finish) with "'));
    disp(sprintf('For further details read: \nhttp://www.nmr.mgh.harvard.edu/martinos/userInfo/computer/launchpad.php'));
    return;
end

pause_time = 30; % Default pause time between consecutive checks for end of command execution!
init_pause = 90; % Initial time to pause before start looking for the end of the job!

if nargin > 1
    ssh2_conn = varargin{1};
else
    [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
        'WindowName', 'Enter your Martinos Login and Password to connect to Launchpad and use FreeSurfer!');
    HOSTNAME = defaults_pseudo_CT('HOSTNAME'); % Address of Launchpad computer!

    ssh_log = {USERNAME, PASSWORD, HOSTNAME};

    disp('Starting the ssh connection to Launchpad to run the Normalization process  ... (be patient!)');
    ssh2_conn = ssh2_config(HOSTNAME,USERNAME,PASSWORD);
end
if nargin > 2
    if ~isdeployed
        pause_time = varargin{2};
    else
        defaults = varargin{2};
    end
end

if nargin > 3
    init_pause = varargin{3} - pause_time;
    init_pause = init_pause.*(init_pause > 0); % To avoid negative numbers!
end

%source_command = 'source /usr/local/freesurfer/nmr-stable53-env'; % To run FreeSurfer!
source_command = defaults_pseudo_CT('source_command'); % To run FreeSurfer!
if isdeployed
    source_command = defaults.source_command;
end
disp('Starting Launchpad command (be patient) ...');
ssh2_conn = ssh2_command(ssh2_conn, sprintf('%s; pbsubmit -c %s', source_command, cmd), 1);
commando = ssh2_command_response(ssh2_conn);
commando = commando{end-1}; % We just need the one before the last line as it contains the job name!
ss = strfind(commando, 'pbsjob_');
jobname = commando(ss:end-1); % To get the jobname!
pause(init_pause); % Pause for 1 minute while the command runs and then start checking:
ss = [];
while length(ss) == 0
    pause(pause_time);
    ssh2_conn = ssh2_command(ssh2_conn, sprintf('cat /pbs/%s/%s.status', ssh2_conn.username, jobname));
    commando = ssh2_command_response(ssh2_conn);
    commando = commando{end}; % Just the last line, where the status should appear when finishing!
    ss = strfind(commando, 'status ');    
end
% Check the status:
sts = str2num(commando(ss+7:end));
if sts ~= 0
    disp(sprintf('Something has gone wrong and the command failed with code %d', sts));
    return
end
disp('Good News Everyone!! The command ran properly!');

return