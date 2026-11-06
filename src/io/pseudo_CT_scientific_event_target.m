function target = pseudo_CT_scientific_event_target(output_context)
%PSEUDO_CT_SCIENTIFIC_EVENT_TARGET Resolve the per-run scientific event file.
%   TARGET = PSEUDO_CT_SCIENTIFIC_EVENT_TARGET(OUTPUT_CONTEXT) places the
%   JSONL event file beside the owner-only run log of the same run:
%       <MR_PET>/pseudoct-run-<UTC>-<uuid>.events.jsonl
%   Removal never reaches it: cleanup only empties MR_PET/tmp (preserving
%   pseudoct-runtime-* and pseudoct-run-* entries) and removes
%   pseudoct-runtime-* directories, and nothing removes MR_PET itself.
%   TARGET.path is '' when no run log is known; the emitter then writes nothing.
%   subject_id is the 1-based subject index (never a patient-derived directory
%   name). Minimum supported MATLAB: R2010b.

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
    target.path = fullfile(folder, [base '.events.jsonl']);
    target.run_id = base;
    if isfield(output_context, 'subject_index') && ...
            isnumeric(output_context.subject_index) && ...
            isscalar(output_context.subject_index) && ...
            isfinite(output_context.subject_index)
        target.subject_id = sprintf('subject-%d', output_context.subject_index);
    end
    if isfield(output_context, 'console_profile') && ...
            ischar(output_context.console_profile)
        target.profile = output_context.console_profile;
    end
catch %#ok<CTCH>
    target.path = '';
end
end
