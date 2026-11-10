function seed_nii = pseudo_CT_prepare_input(input_file, output_file, context, source)
%PSEUDO_CT_PREPARE_INPUT Convert or copy one MPRAGE input for the pipeline.
%   SEED_NII = PSEUDO_CT_PREPARE_INPUT(INPUT_FILE, OUTPUT_FILE, CONTEXT, SOURCE)
%   performs manager-owned stage 1 through the existing quiet converter and
%   records its native STARTED/COMPLETED events without a second presenter.
%   SOURCE is 'local-orchestrator' or 'mlsc-lifecycle'. Minimum MATLAB: R2010b.

target = pseudo_CT_scientific_event_target(context);
if ~isempty(target.path)
    pseudo_CT_scientific_event(target, struct('event_type', 'stage', ...
        'stage_id', 'workflow.input_prepare', 'stage_index', 1, ...
        'status', 'STARTED', 'message', 'Input MPRAGE preparation started.', ...
        'source', source));
    local_present_orchestration_event(context);
end

seed_nii = pseudo_CT_convert_dicom_quiet(input_file, output_file, context);

if ~isempty(target.path)
    pseudo_CT_scientific_event(target, struct('event_type', 'stage', ...
        'stage_id', 'workflow.input_prepare', 'stage_index', 1, ...
        'status', 'COMPLETED', 'message', 'Input MPRAGE prepared.', ...
        'source', source));
    local_present_orchestration_event(context);
end
end

function local_present_orchestration_event(context)
% Deliver orchestration progress immediately without affecting computation.
if strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1')
    try
        pseudo_CT_present_native_events(context, true);
    catch ME
        fprintf(2, 'WARNING: progress presentation failed: %s\n', ME.message);
    end
end
end
