% Date: May/28/2026;
% Standalone copy of the piano_mMR Launchpad submission helper.

function [ssh2_conn, jobname, jobnum] = run_launchpad_cmd_return(cmd, varargin)

if strcmp(cmd(1), '"') == 0
    disp(sprintf('The command should start (and finish) with "'));
    disp(sprintf('For further details read: \nhttp://www.nmr.mgh.harvard.edu/martinos/userInfo/computer/launchpad.php'));
    return;
end

FS = 1;

if nargin > 1
    ssh2_conn = varargin{1};
else
    [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
        'WindowName', 'Enter your Martinos Login and Password to connect to Launchpad and use FreeSurfer!');
    HOSTNAME = defaults_pseudo_CT_launchpad('HOSTNAME');

    disp('Starting the ssh connection to Launchpad to run the Normalization process  ... (be patient!)');
    ssh2_conn = ssh2_config(HOSTNAME, USERNAME, PASSWORD);
end
if nargin > 2
    FS = varargin{2};
end

if nargin > 3
    queue_com = varargin{3};
else
    queue_com = '';
end

if FS
    source_command = defaults_pseudo_CT_launchpad('source_command');
else
    source_command = '';
end
disp('Starting Launchpad command (be patient) ...');
ssh2_conn = ssh2_command(ssh2_conn, sprintf('%spbsubmit %s -c %s', source_command, queue_com, cmd), 1);
commando = ssh2_command_response(ssh2_conn);
commando_tot = commando;
jobnumline = commando{end};
jobnumcells = strsplit(jobnumline, '.');
jobnum = str2double(jobnumcells{1});
commando = commando{end-1};
ss = strfind(commando, 'pbsjob_');
if length(ss) == 0
    for ii=length(commando_tot):-1:1
        commando = commando_tot{ii};
        ss = strfind(commando, 'pbsjob_');
        if length(ss) > 0
            break;
        end
    end
end
jobname = commando(ss:end-1);

return