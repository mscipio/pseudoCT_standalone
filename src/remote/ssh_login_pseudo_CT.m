function [ssh2_conn,HOSTNAME,USERNAME] = ssh_login_pseudo_CT(varargin)
HOSTNAME = defaults_pseudo_CT('HOSTNAME');
if nargin > 0
    HOSTNAME = varargin{1};
end
ssh2_conn_exist = evalin('caller','exist(''ssh2_conn'',''var'')');
if ssh2_conn_exist; ssh2_conn = evalin('caller','ssh2_conn'); end
if strcmp(HOSTNAME, '127.0.0.1') || strcmpi(HOSTNAME, 'localhost')
    USERNAME = '';
    if ssh2_conn_exist && isstruct(ssh2_conn) && isfield(ssh2_conn, 'username')
        USERNAME = ssh2_conn.username;
    end
    if isempty(USERNAME)
        USERNAME = getenv('USER');
    end
    if isempty(USERNAME)
        USERNAME = getenv('LOGNAME');
    end
    if isempty(USERNAME)
        USERNAME = 'local';
    end
    ssh2_conn = struct('hostname', HOSTNAME, 'username', USERNAME, 'password', '', 'autoreconnect', 0);
    return;
end
if ~ssh2_conn_exist || ~isstruct(ssh2_conn) || (ssh2_conn_exist && ~strcmp(ssh2_conn.hostname, HOSTNAME))
    auth = 0;
    while auth == 0
        [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', false, 'PasswordLengthMax', 50, ...
            'WindowName', 'Enter your Martinos Login and Password to connect to Launchpad and use FreeSurfer!');
        if PASSWORD == -1
            error('Authentication Canceled. Quitting...');
        end
        %HOSTNAME = '172.27.25.134'; % Address of Launchpad computer!
        disp('Starting the ssh connection to Launchpad to run commands  ... (be patient!)');
        ssh2_conn = ssh2_config(HOSTNAME,USERNAME,PASSWORD);
        try
            ssh2_conn = ssh2_command(ssh2_conn, sprintf('echo Password Authenticated'));
            auth = 1;
        catch
            fprintf('Authentication Failed. Try Again.\n');
        end
    end
    ssh2_conn.autoreconnect = 1;
    clear PASSWORD;
else
    HOSTNAME = ssh2_conn.hostname;
    USERNAME = ssh2_conn.username;
end
end