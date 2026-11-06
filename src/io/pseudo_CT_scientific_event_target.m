function target = pseudo_CT_scientific_event_target(output_context)
%PSEUDO_CT_SCIENTIFIC_EVENT_TARGET Resolve the per-run scientific event file.
%   TARGET = PSEUDO_CT_SCIENTIFIC_EVENT_TARGET(OUTPUT_CONTEXT) derives the
%   JSONL event file from the owner-only run log of the same run:
%       <MR_PET>/pseudoct-run-<RUN_ID>.jsonl
%   where RUN_ID is "<UTC>-<invocationUUID>" exactly as in the run log name
%   pseudoct-run-<RUN_ID>.log. The file lives directly in MR_PET, never in
%   MR_PET/tmp, and is retained after success, failure and cancellation
%   (cleanup empties MR_PET/tmp only and never removes MR_PET itself).
%   TARGET.path is '' when no run log is known or the run id is malformed; the
%   emitter then writes nothing. subject_id is the 1-based subject index, never
%   a patient-derived directory name. profile is the console profile key.
%   Minimum supported MATLAB: R2010b.

target = struct('path', '', 'run_id', '', 'subject_id', '', 'profile', '');
try
    if ~isstruct(output_context) || numel(output_context) ~= 1 || ...
            ~isfield(output_context, 'log_file') || ...
            ~ischar(output_context.log_file) || ...
            size(output_context.log_file, 1) ~= 1
        return;
    end
    log_file = strtrim(output_context.log_file);
    [folder, base, ext] = fileparts(log_file);
    if isempty(folder) || ~strcmp(ext, '.log') || ...
            ~strncmp(base, 'pseudoct-run-', 13)
        return;
    end
    run_id = base(14:end);
    if isempty(regexp(run_id, ...
            '^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', ...
            'once'))
        return;
    end
    target.path = fullfile(folder, [base '.jsonl']);
    target.run_id = run_id;
    if isfield(output_context, 'subject_index') && ...
            isnumeric(output_context.subject_index) && ...
            isscalar(output_context.subject_index) && ...
            isfinite(output_context.subject_index) && ...
            output_context.subject_index >= 1
        target.subject_id = sprintf('subject-%d', output_context.subject_index);
    end
    if isfield(output_context, 'console_profile') && ...
            ischar(output_context.console_profile) && ...
            size(output_context.console_profile, 1) <= 1
        target.profile = output_context.console_profile;
    end
catch %#ok<CTCH>
    target.path = '';
end
end
