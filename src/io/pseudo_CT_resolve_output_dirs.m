function [processing_dir, temp_dir, save_dir] = pseudo_CT_resolve_output_dirs(series_dir)

mr_dir = '';
processing_root = '';
search_dir = series_dir;
while ~isempty(search_dir)
    [parent_dir, dir_name] = fileparts(search_dir);
    if strcmpi(dir_name, 'MR')
        mr_dir = search_dir;
        break;
    end
    if isempty(processing_root) && strcmpi(dir_name, 'MR_PET')
        processing_root = search_dir;
    end
    if strcmp(parent_dir, search_dir)
        break;
    end
    search_dir = parent_dir;
end

if isempty(mr_dir)
    % Headers can already be staged below MR_PET/tmp (including a private
    % conversion directory). Resolve from MR_PET itself, not its descendants.
    % An actual MR ancestor above still takes precedence, as before.
    if ~isempty(processing_root)
        series_dir = processing_root;
    end
    % The up-walk didn't find an MR/ ancestor, but MR/ may be a sibling
    % of the input directory (e.g., NIfTI in MR_PET/, MR/ next to it).
    mr_parent = fileparts(series_dir);
    potential_mr = fullfile(mr_parent, 'MR');
    if isdir(potential_mr)
        mr_dir = potential_mr;
        subject_root = mr_parent;
    else
        if isempty(mr_parent)
            mr_dir = series_dir;
            subject_root = mr_dir;
        else
            mr_dir = mr_parent;
            subject_root = mr_dir;
        end
    end
else
    subject_root = fileparts(mr_dir);
end

processing_dir = fullfile(subject_root, 'MR_PET');
temp_dir = fullfile(processing_dir, 'tmp');
save_dir = fullfile(mr_dir, 'pseudo_muMAP');
