function success = pseudo_CT_promote_final_outputs(temp_dir, processing_dir, seed_nii, varargin)

success = 0;
context = struct();
if ~isempty(varargin) && isstruct(varargin{1})
    context = varargin{1};
end

if exist(temp_dir, 'dir') ~= 7
    % Legacy output: disp(sprintf('Temporary folder not found:\n%s\n', temp_dir));
    pseudo_CT_output('ERROR', context, 'Temporary folder was not found.');
    pseudo_CT_output('INFO', context, '    %s', temp_dir);
    return;
end

if exist(processing_dir, 'dir') ~= 7
    [mkdir_success, msg] = mkdir(processing_dir);
    if mkdir_success == 0
        % Legacy output: disp(sprintf('There was an error creating the directory %s\n%s', processing_dir, msg));
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

for ii=1:size(copy_specs, 1)
    source_file = copy_specs{ii, 1};
    destination_file = copy_specs{ii, 2};
    is_required = copy_specs{ii, 3};

    if exist(source_file, 'file') ~= 2
        if is_required
            % Legacy output: disp(sprintf('Required output file not found:\n%s\n', source_file));
            pseudo_CT_output('ERROR', context, 'Required output file was not found.');
            pseudo_CT_output('INFO', context, '    %s', source_file);
            return;
        end
        continue;
    end

    if exist(destination_file, 'file') == 2
        delete(destination_file);
    end

    [copy_success, msg] = copyfile(source_file, destination_file);
    if copy_success == 0
        % Legacy output: disp(sprintf('There was an error copying the output file\n%s\nto\n%s\n%s', source_file, destination_file, msg));
        pseudo_CT_output('ERROR', context, 'Could not promote output file: %s', msg);
        pseudo_CT_output('INFO', context, '    %s', source_file);
        pseudo_CT_output('INFO', context, '    %s', destination_file);
        return;
    end
end

if exist(required_att_map, 'file') ~= 2
    % Legacy output: disp(sprintf('Required output file not found:\n%s\n', required_att_map));
    pseudo_CT_output('ERROR', context, 'Promoted attenuation map was not found.');
    pseudo_CT_output('INFO', context, '    %s', required_att_map);
    return;
end

success = 1;

return

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
