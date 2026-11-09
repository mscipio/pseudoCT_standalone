function [sts] = pseudo_CT_run_normalization_cmd(cmd, output_context, config)
%PSEUDO_CT_RUN_NORMALIZATION_CMD Run the controlled local FreeSurfer child command.
%   STS = PSEUDO_CT_RUN_NORMALIZATION_CMD(CMD, OUTPUT_CONTEXT, CONFIG)
%   CMD is the normalization command. Its last space-separated token is the
%   normalized NIfTI path that the command must create. CONFIG supplies the
%   existing FreeSurfer source command and optional child library path. The child
%   starts with LD_LIBRARY_PATH unset before the environment is sourced.
%   STS is 0 only when the FreeSurfer command exits zero and the normalized file exists; otherwise it is -1. Failure
%   detail is logged through pseudo_CT_output.
%   Side effects: runs the external FreeSurfer command locally. Errors:
%   pseudo_CT:ProfileRequired when CONFIG is missing.
%   Origin: David Izquierdo-Garcia (Athinoula A. Martinos Center, MGH), 2014.
%   Minimum supported MATLAB: R2010b.

sts = 0;
if nargin ~= 3 || ~isstruct(config)
    error('pseudo_CT:ProfileRequired', ...
        'pseudo_CT_run_normalization_cmd requires the selected profile config.');
end

source_command = config.normalization.source_command;
child_lib_path = config.normalization.child_lib_path;

aa = strfind(cmd, ' ');
norm_fn = strtrim(cmd((aa(end)+1):end));
[status, command_result] = system(local_prepare_source_command( ...
    source_command, cmd, child_lib_path));

output_created = exist(norm_fn, 'file') == 2;
% A nonzero FreeSurfer exit is a failure even when a nonempty output file exists.
if ~output_created || status ~= 0
    if ~output_created
        pseudo_CT_output('ERROR', output_context, 'FreeSurfer did not create the normalized NIfTI file.');
    end
    if ~isempty(command_result)
        pseudo_CT_output('ERROR', output_context, 'FreeSurfer failure detail: %s', strtrim(command_result));
    end
    if status ~= 0
        pseudo_CT_output('ERROR', output_context, 'FreeSurfer exit status: %d.', status);
    end
    sts = -1;
    return
end
    

return

function local_cmd = local_prepare_source_command(source_command, cmd, child_lib_path)

source_command = strtrim(source_command);
if isempty(source_command)
    local_cmd = ['env -u LD_LIBRARY_PATH ' cmd];
    return;
end

if source_command(end) == ';'
    source_command = strtrim(source_command(1:end-1));
end

% --- Shell-safe input validation for ALL interpolated command strings ---
% child_lib_path, source_command, and cmd are all interpolated into tcsh/sh
% command strings below.  Validate each for shell metacharacters before
% ANY interpolation, not just child_lib_path.  (R1-001 full remediation.)
shell_meta = '[;&|`$(){\}\[\]<>!\\''"]';
if ~isempty(regexp(child_lib_path, shell_meta, 'once'))
    error('pseudo_CT:UnsafeNormalizationCommand', ...
        'Normalization library path contains shell metacharacters: %s', child_lib_path);
end
if ~isempty(regexp(source_command, shell_meta, 'once'))
    error('pseudo_CT:UnsafeNormalizationCommand', ...
        'Normalization source command contains shell metacharacters: %s', source_command);
end
if ~isempty(regexp(cmd, shell_meta, 'once'))
    error('pseudo_CT:UnsafeNormalizationCommand', ...
        'Normalization command contains shell metacharacters: %s', cmd);
end

% Empty child_lib_path means no LD_LIBRARY_PATH prepend (no empty colon component).
if length(source_command) >= 6 && strcmpi(source_command(1:6), 'source')
    if isempty(child_lib_path)
        local_cmd = sprintf('env -u LD_LIBRARY_PATH tcsh -f -c "%s; %s"', source_command, cmd);
    else
        % The child starts with LD_LIBRARY_PATH unset (env -u), so the configured path is the whole value.
        % Expanding $LD_LIBRARY_PATH here is unsafe: the parent shell expands it before env -u runs, and tcsh rejects an undefined variable.
        local_cmd = sprintf('env -u LD_LIBRARY_PATH tcsh -f -c "setenv LD_LIBRARY_PATH %s; %s; %s"', child_lib_path, source_command, cmd);
    end
else
    if isempty(child_lib_path)
        local_cmd = sprintf('env -u LD_LIBRARY_PATH /bin/sh -c "%s; %s"', source_command, cmd);
    else
        % The child starts with LD_LIBRARY_PATH unset (env -u), so the configured path is the whole value.
        % Expanding $LD_LIBRARY_PATH here is unsafe: the parent shell expands it before env -u runs, and tcsh rejects an undefined variable.
        local_cmd = sprintf('env -u LD_LIBRARY_PATH /bin/sh -c "LD_LIBRARY_PATH=%s; export LD_LIBRARY_PATH; %s; %s"', child_lib_path, source_command, cmd);
    end
end
