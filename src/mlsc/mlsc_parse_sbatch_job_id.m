function job_id = mlsc_parse_sbatch_job_id(response)
%MLSC_PARSE_SBATCH_JOB_ID Parse one numeric ID from sbatch --parsable output.
%   JOB_ID = MLSC_PARSE_SBATCH_JOB_ID(RESPONSE) accepts the machine-readable
%   sbatch form JOBID or JOBID;CLUSTER.  Human-readable submission output,
%   arrays, missing output, and ambiguous output fail closed.
%
%   Minimum supported MATLAB: R2010b.

lines = local_response_lines(response);
matches = {};
for ii = 1:length(lines)
    line = strtrim(lines{ii});
    if isempty(line)
        continue;
    end
    token = regexp(line, '^([0-9]+)(;[A-Za-z0-9_.:-]+)?$', ...
        'tokens', 'once');
    if ~isempty(token)
        matches{end + 1} = token{1}; %#ok<AGROW>
    end
end

if length(matches) ~= 1
    error('pseudo_CT:MLSCSbatchParse', ...
        'sbatch --parsable did not return exactly one numeric job ID.');
end
job_id = str2double(matches{1});
if ~isfinite(job_id) || job_id < 1 || job_id ~= floor(job_id)
    error('pseudo_CT:MLSCSbatchParse', ...
        'The sbatch job ID is not a positive numeric value.');
end
end

function lines = local_response_lines(response)
if ischar(response)
    lines = cellstr(response);
elseif iscell(response)
    lines = {};
    for ii = 1:numel(response)
        if ~ischar(response{ii})
            error('pseudo_CT:MLSCSbatchParse', ...
                'The sbatch response must contain text lines.');
        end
        lines{end + 1} = response{ii}; %#ok<AGROW>
    end
else
    error('pseudo_CT:MLSCSbatchParse', ...
        'The sbatch response must be text.');
end
end
