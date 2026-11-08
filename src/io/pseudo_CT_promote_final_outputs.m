function success = pseudo_CT_promote_final_outputs(temp_dir, processing_dir, seed_nii, varargin)
%PSEUDO_CT_PROMOTE_FINAL_OUTPUTS Copy the final outputs from the subject temp folder to MR_PET.
%   SUCCESS = PSEUDO_CT_PROMOTE_FINAL_OUTPUTS(TEMP_DIR, PROCESSING_DIR, SEED_NII, CONTEXT)
%   TEMP_DIR is the subject working folder (MR_PET/tmp). PROCESSING_DIR is the
%   MR_PET folder that receives the outputs; it is created when missing. SEED_NII
%   is the input NIfTI, used to find the MPRAGE outputs. CONTEXT is an optional
%   logging struct for pseudo_CT_output.
%   Copies the available outputs (NIfTI files, the QC TIFF, the version text and
%   the MPRAGE_spm files) into PROCESSING_DIR. att_map.nii is required and is
%   committed last, after all staging succeeds. Existing final files are not
%   deleted before the copy.
%   SUCCESS is 1 when the required outputs were promoted, and 0 otherwise.
%   Side effects: creates PROCESSING_DIR and copies files into it. The temporary
%   folder is kept when promotion fails. Logs failures through pseudo_CT_output.
%   Minimum supported MATLAB: R2010b.

success = 0;
context = struct();
if ~isempty(varargin) && isstruct(varargin{1})
    context = varargin{1};
end

if exist(temp_dir, 'dir') ~= 7
    pseudo_CT_output('ERROR', context, 'Temporary folder was not found.');
    pseudo_CT_output('INFO', context, '    %s', temp_dir);
    return;
end

if exist(processing_dir, 'dir') ~= 7
    [mkdir_success, msg] = mkdir(processing_dir);
    if mkdir_success == 0
        pseudo_CT_output('ERROR', context, 'Could not create output directory: %s', msg);
        return;
    end
end

copy_specs = {
    fullfile(temp_dir, 'att_map.nii'), fullfile(processing_dir, 'att_map.nii'), 1;
    fullfile(temp_dir, 'Pseudo_CT_AC_Version.txt'), fullfile(processing_dir, 'Pseudo_CT_AC_Version.txt'), 0;
    fullfile(temp_dir, 'Fusion_MR_Pseudo_CT_validation.tiff'), fullfile(processing_dir, 'Fusion_MR_Pseudo_CT_validation.tiff'), 0;
    };

seed_source = local_find_seed_source(temp_dir, seed_nii);
if ~isempty(seed_source)
    copy_specs(end+1, :) = {seed_source, fullfile(processing_dir, 'MPRAGE_spm.nii'), 0};
end

normalized_source = local_find_normalized_source(temp_dir, seed_nii);
if ~isempty(normalized_source)
    copy_specs(end+1, :) = {normalized_source, fullfile(processing_dir, 'MPRAGE_spm_normalized.nii'), 0};
end

required_att_map = fullfile(processing_dir, 'att_map.nii');
stage_specs = cell(0, 4);

% Stage every available output without deleting an existing final file. The
% required attenuation map is committed last, after all staging succeeds.
for ii=1:size(copy_specs, 1)
    source_file = copy_specs{ii, 1};
    destination_file = copy_specs{ii, 2};
    is_required = copy_specs{ii, 3};

    if exist(source_file, 'file') ~= 2
        if is_required
            pseudo_CT_output('ERROR', context, 'Required output file was not found.');
            pseudo_CT_output('INFO', context, '    %s', source_file);
            return;
        end
        continue;
    end

    stage_file = [destination_file '.stage'];
    if exist(stage_file, 'file') == 2
        delete(stage_file);
    end
    [copy_success, msg] = copyfile(source_file, stage_file);
    if copy_success == 0
        pseudo_CT_output('ERROR', context, 'Could not promote output file: %s', msg);
        pseudo_CT_output('INFO', context, '    %s', source_file);
        pseudo_CT_output('INFO', context, '    %s', destination_file);
        local_cleanup_stages(stage_specs, stage_file);
        return;
    end
    if exist(stage_file, 'file') ~= 2
        pseudo_CT_output('ERROR', context, 'Staged output was not created.');
        pseudo_CT_output('INFO', context, '    %s', stage_file);
        local_cleanup_stages(stage_specs, stage_file);
        return;
    end
    stage_specs(end + 1, :) = {stage_file, destination_file, is_required, source_file}; %#ok<AGROW>
end

% Commit optional diagnostics first; leave the prior final map untouched if
% an optional replacement fails. Commit the required map only at the end.
for ii=1:size(stage_specs, 1)
    if stage_specs{ii, 3}
        continue;
    end
    [move_success, msg] = movefile(stage_specs{ii, 1}, stage_specs{ii, 2}, 'f');
    if move_success == 0
        pseudo_CT_output('ERROR', context, 'Could not promote output file: %s', msg);
        local_cleanup_stages(stage_specs);
        return;
    end
end

required_index = 1;
for ii=1:size(stage_specs, 1)
    if stage_specs{ii, 3}
        required_index = ii;
        break;
    end
end
[move_success, msg] = movefile(stage_specs{required_index, 1}, ...
    required_att_map, 'f');
if move_success == 0
    pseudo_CT_output('ERROR', context, 'Could not promote attenuation map: %s', msg);
    local_cleanup_stages(stage_specs);
    return;
end

if exist(required_att_map, 'file') ~= 2
    pseudo_CT_output('ERROR', context, 'Promoted attenuation map was not found.');
    pseudo_CT_output('INFO', context, '    %s', required_att_map);
    local_cleanup_stages(stage_specs);
    return;
end

success = 1;

return
end

function local_cleanup_stages(stage_specs, extra_stage)
if nargin < 2
    extra_stage = '';
end
for ii=1:size(stage_specs, 1)
    if exist(stage_specs{ii, 1}, 'file') == 2
        delete(stage_specs{ii, 1});
    end
end
if ~isempty(extra_stage) && exist(extra_stage, 'file') == 2
    delete(extra_stage);
end
end

function source_file = local_find_seed_source(temp_dir, seed_nii)

source_file = '';

if nargin < 2 || ~ischar(seed_nii) || isempty(strtrim(seed_nii))
    return;
end

[pathr, fnr, extr] = fileparts(deblank(seed_nii)); %#ok<ASGLU>
candidate = fullfile(temp_dir, strcat(fnr, extr));
if exist(candidate, 'file') == 2
    source_file = candidate;
end

return
end

function source_file = local_find_normalized_source(temp_dir, seed_nii)

source_file = '';
candidate_list = {};

if nargin >= 2 && ischar(seed_nii) && ~isempty(strtrim(seed_nii))
    [pathr, fnr, extr] = fileparts(deblank(seed_nii)); %#ok<ASGLU>
    candidate_list = {strcat(fnr, '_normalized.nii'), strcat(fnr, '_moved_normalized.nii')};
end

for ii=1:length(candidate_list)
    candidate = fullfile(temp_dir, candidate_list{ii});
    if exist(candidate, 'file') == 2
        source_file = candidate;
        return;
    end
end

list_norm = dir(fullfile(temp_dir, '*_normalized.nii'));
for ii=1:length(list_norm)
    if list_norm(ii).isdir
        continue;
    end
    if strncmpi(list_norm(ii).name, 's', 1)
        continue;
    end
    if ~isempty(strfind(lower(list_norm(ii).name), 'atlas'))
        continue;
    end
    source_file = fullfile(temp_dir, list_norm(ii).name);
    return;
end

return
end
