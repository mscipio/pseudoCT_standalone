function [first, second] = mlsc_progress(action, arg1, arg2)
%MLSC_PROGRESS Per-submission progress artifact identity.
%   Each MLSC submission reserves one exact, non-secret artifact name derived
%   from its correlation identity:
%       fullfile(SHARED_TEMP, '.mlsc_progress_<correlation-id>')
%   The fixed name fullfile(SHARED_TEMP, '.mlsc_progress') is retained only for
%   direct generation and harmless best-effort cleanup of preserved-temp prior
%   runs. The batch shell writes no records into it: stage events come only
%   from the pipeline's native event file and liveness is observed from local
%   process or Slurm state. The correlation suffix contains only
%   [A-Za-z0-9_.-] (1-64 chars): no username, account, path, host key, or
%   other secret-bearing content is ever in the filename.
%
%   Usage:
%       NAME = MLSC_PROGRESS('filename')
%       PATH = MLSC_PROGRESS('path', SHARED_TEMP)
%       NAME = MLSC_PROGRESS('filename_for', CORRELATION_ID)
%       PATH = MLSC_PROGRESS('path_for', SHARED_TEMP, CORRELATION_ID)
%
%   Minimum supported MATLAB: R2010b.

if nargin < 1 || isempty(action)
    error('pseudo_CT:MLSCProgressAction', ...
        'An MLSC progress action is required.');
end
if ~ischar(action) || size(action, 1) ~= 1
    error('pseudo_CT:MLSCProgressAction', ...
        'The MLSC progress action must be text.');
end
if nargin < 2
    arg1 = [];
end
if nargin < 3
    arg2 = [];
end

second = [];
if strcmp(action, 'filename')
    first = '.mlsc_progress';
elseif strcmp(action, 'path')
    first = local_progress_path(arg1);
elseif strcmp(action, 'filename_for')
    first = local_filename_for(arg1);
elseif strcmp(action, 'path_for')
    first = local_progress_path_for(arg1, arg2);
else
    error('pseudo_CT:MLSCProgressAction', ...
        'The MLSC progress action is unknown.');
end
end

function progress_path = local_progress_path(shared_temp)
if ~ischar(shared_temp) || size(shared_temp, 1) ~= 1 || ...
        isempty(shared_temp) || any(shared_temp == char(0))
    error('pseudo_CT:MLSCProgressPath', ...
        'A shared subject temp is required for the MLSC progress path.');
end
progress_path = fullfile(shared_temp, '.mlsc_progress');
end

function filename = local_filename_for(correlation_id)
if ~local_is_correlation_id(correlation_id)
    error('pseudo_CT:MLSCProgressCorrelation', ...
        'A non-secret MLSC correlation identity is required.');
end
filename = ['.mlsc_progress_' correlation_id(:)'];
filename = reshape(filename, 1, numel(filename));
end

function progress_path = local_progress_path_for(shared_temp, correlation_id)
if ~ischar(shared_temp) || size(shared_temp, 1) ~= 1 || ...
        isempty(shared_temp) || any(shared_temp == char(0))
    error('pseudo_CT:MLSCProgressPath', ...
        'A shared subject temp is required for the MLSC progress path.');
end
filename = local_filename_for(correlation_id);
progress_path = fullfile(shared_temp, filename);
end

function valid = local_is_correlation_id(value)
valid = false;
try
    if ~ischar(value) || size(value, 1) ~= 1 || isempty(value)
        return;
    end
    if any(value == char(0))
        return;
    end
    if length(value) < 1 || length(value) > 64
        return;
    end
    if isempty(regexp(value, '^[A-Za-z0-9_.-]+$', 'once'))
        return;
    end
    valid = true;
catch %#ok<CTCH>
    valid = false;
end
end
