function [success, failure_detail] = pseudo_CT_finalize_subject(job, ...
        att_map_file, temp_working_dir, seed_nii, config, context, source)
%PSEUDO_CT_FINALIZE_SUBJECT Run manager-owned stages 9 and 10 after verification.
%   Both local and MLSC callers enter here only after their pipeline outputs
%   are verified locally. DICOM uses the original UMAP reference and siblings;
%   final NIfTI promotion and temporary cleanup remain on the submitting host.
%   Minimum supported MATLAB: R2010b.

success = 0;
failure_detail = '';
target = pseudo_CT_scientific_event_target(context);
write_events = ~isempty(target.path);
stage_event = struct('event_type', 'stage', 'stage_id', '', ...
    'stage_index', 0, 'status', '', 'message', '', 'source', source);

% Finalization diagnostics and output operations must not inherit stages 1-8.
output_context = context;
stale_fields = {'stage_index'; 'stage_count'; 'public_stage_total'; ...
    'stage_id'; 'stage_status'; 'stage_message'; 'stage_span'; ...
    'operation_ids'; 'operation_id'; 'event_kind'; 'event_category'; ...
    'reason'; 'workflow_event'; 'direct_scientific_stream'; 'source'; ...
    'source_file'; 'live'};
for ii = 1:length(stale_fields)
    if isfield(output_context, stale_fields{ii})
        output_context = rmfield(output_context, stale_fields{ii});
    end
end

mprage_only = isfield(config, 'io_policy') && ...
    isfield(config.io_policy, 'gui') && ...
    strcmp(config.io_policy.gui, 'mprage-only');
if strcmp(config.io_policy.output, 'nifti-and-dicom')
    stage_event.stage_id = 'workflow.dicom_output';
    stage_event.stage_index = 9;
    stage_event.status = 'STARTED';
    stage_event.message = 'Writing DICOM output.';
    if write_events
        pseudo_CT_scientific_event(target, stage_event);
    end
    converter_context = output_context;
    if strcmp(source, 'mlsc-lifecycle')
        converter_context.console_detail_remote = true;
    end
    try
        pseudo_CT_write_mu_map_dicom(att_map_file, job.save_dir, ...
            job.umap_fn, job.temp_dir, config.fwhm, converter_context);
    catch ME
        failure_detail = ME.message;
        stage_event.status = 'FAILED';
        stage_event.message = sprintf('DICOM output failed: %s', ME.message);
        if write_events
            pseudo_CT_scientific_event(target, stage_event);
        end
        if strcmp(source, 'local-orchestrator')
            pseudo_CT_output('ERROR', output_context, ...
                'DICOM output failed: %s', ME.message);
        end
        return;
    end
    stage_event.status = 'COMPLETED';
    stage_event.message = 'DICOM output written.';
    if write_events
        pseudo_CT_scientific_event(target, stage_event);
    end
else
    if mprage_only
        stage_event.stage_id = 'workflow.dicom_output';
        stage_event.stage_index = 9;
        stage_event.status = 'SKIPPED';
        stage_event.message = ...
            'DICOM output skipped by MPRAGE-only policy (profile_policy:mprage_only).';
        if write_events
            pseudo_CT_scientific_event(target, stage_event);
        end
    else
        pseudo_CT_output('INFO', output_context, ...
            'Skipping DICOM output by profile policy.');
    end
end

if mprage_only
    stage_event.stage_id = 'workflow.full_output_finalize';
    stage_event.stage_index = 10;
    stage_event.status = 'SKIPPED';
    stage_event.message = ...
        'Full-mode output finalization skipped by MPRAGE-only policy (profile_policy:mprage_only).';
    if write_events
        pseudo_CT_scientific_event(target, stage_event);
    end
else
    stage_event.stage_id = 'workflow.full_output_finalize';
    stage_event.stage_index = 10;
    stage_event.status = 'STARTED';
    stage_event.message = 'Promoting final NIfTI outputs.';
    if write_events
        pseudo_CT_scientific_event(target, stage_event);
    end
end

promotion_success = pseudo_CT_promote_final_outputs(temp_working_dir, ...
    job.processing_dir, seed_nii, output_context);
if ~promotion_success
    if ~mprage_only
        stage_event.status = 'FAILED';
        stage_event.message = 'Output promotion failed.';
        if write_events
            pseudo_CT_scientific_event(target, stage_event);
        end
    end
    pseudo_CT_output('ERROR', output_context, ...
        'Output promotion failed; temporary files were preserved.');
    pseudo_CT_output('INFO', output_context, '    %s', temp_working_dir);
    return;
end

if ~mprage_only
    stage_event.status = 'COMPLETED';
    stage_event.message = 'Outputs promoted.';
    if write_events
        pseudo_CT_scientific_event(target, stage_event);
    end
end
verify_context = output_context;
verify_context.workflow_event = true;
verify_context.operation_id = 'output.verify';
verify_context.event_kind = 'output_verified';
verify_context.stage_status = 'DONE';
verify_context.source = 'orchestrator';
verify_context.source_file = ...
    'src/orchestration/pseudo_CT_finalize_subject.m';
verify_context.live = true;
pseudo_CT_output('SUCCESS', verify_context, 'Promoted outputs verified.');

cleanup_context = output_context;
cleanup_context.workflow_event = true;
cleanup_context.operation_id = 'output.cleanup';
cleanup_context.event_kind = 'operation_started';
cleanup_context.stage_status = 'START';
cleanup_context.source = 'orchestrator';
cleanup_context.source_file = ...
    'src/orchestration/pseudo_CT_finalize_subject.m';
cleanup_context.live = true;
if strcmp(source, 'mlsc-lifecycle')
    pseudo_CT_output('INFO', cleanup_context, 'Cleaning up temporary files.');
end
if config.cleanup_on_success
    [remove_success, msg] = pseudo_CT_cleanup_subject_temp(temp_working_dir);
    if ~remove_success
        cleanup_context.event_kind = 'warning';
        cleanup_context.stage_status = 'WARN';
        pseudo_CT_output('WARN', cleanup_context, ...
            'Temporary cleanup failed: %s', msg);
    elseif strcmp(source, 'local-orchestrator')
        cleanup_context.event_kind = 'operation_completed';
        cleanup_context.stage_status = 'DONE';
        pseudo_CT_output('INFO', cleanup_context, 'Temporary files removed.');
    end
end
if strcmp(source, 'mlsc-lifecycle')
    cleanup_context.event_kind = 'operation_completed';
    cleanup_context.stage_status = 'DONE';
    pseudo_CT_output('SUCCESS', cleanup_context, 'Cleanup completed.');
end

success = 1;
end
