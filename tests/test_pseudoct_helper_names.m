function test_pseudoct_helper_names()
%TEST_PSEUDOCT_HELPER_NAMES Offline name-resolution checks for renamed helpers.
%   Each renamed helper must live in a file whose name matches its declared
%   function name and must resolve from the repository. The QC overlay and
%   legacy PCA dispatch paths are exercised on tiny synthetic inputs only.

root_dir = fileparts(fileparts(mfilename('fullpath')));
dirs = {'src/science/current', 'src/science/shared', 'src/science/legacy', ...
    'src/qc', 'src/io', 'src/backends/shared', 'src/gui'};
old_path = path();
cleanup = onCleanup(@() path(old_path)); %#ok<NASGU>
for ii = 1:length(dirs)
    addpath(fullfile(root_dir, dirs{ii}));
end

helpers = {
    'src/science/current/pseudo_CT_ct_to_att_map.m', 'pseudo_CT_ct_to_att_map'; ...
    'src/science/current/pseudo_CT_move_image_2_mni.m', 'pseudo_CT_move_image_2_mni'; ...
    'src/science/current/pseudo_CT_head_mask_mprage.m', 'pseudo_CT_head_mask_mprage'; ...
    'src/science/current/pseudo_CT_reduce_bone_segment.m', 'pseudo_CT_reduce_bone_segment'; ...
    'src/science/legacy/pseudo_CT_princomp_legacy.m', 'pseudo_CT_princomp_legacy'; ...
    'src/qc/pseudo_CT_quick_fusion.m', 'pseudo_CT_quick_fusion'; ...
    'src/qc/pseudo_CT_overlay2.m', 'pseudo_CT_overlay2'; ...
    'src/io/pseudo_CT_nii2dcm_header_copy.m', 'pseudo_CT_nii2dcm_header_copy'; ...
    'src/io/pseudo_CT_mmr_nii2mu_dicom.m', 'pseudo_CT_mmr_nii2mu_dicom'; ...
    'src/backends/shared/pseudo_CT_run_normalization_cmd.m', 'pseudo_CT_run_normalization_cmd'; ...
    'src/backends/shared/pseudo_CT_ssh2_command.m', 'pseudo_CT_ssh2_command'; ...
    'src/gui/pseudo_CT_password_entry_dialog.m', 'pseudo_CT_password_entry_dialog'};

for ii = 1:size(helpers, 1)
    file_path = fullfile(root_dir, helpers{ii, 1});
    expected = helpers{ii, 2};
    assert(exist(file_path, 'file') == 2, ...
        sprintf('Renamed helper file is missing: %s', helpers{ii, 1}));
    [~, file_base] = fileparts(file_path);
    assert(strcmp(file_base, expected), ...
        sprintf('File base name %s does not match %s', file_base, expected));
    declared = local_declared_name(file_path);
    assert(strcmp(declared, expected), ...
        sprintf('Declared function %s does not match file %s', declared, file_base));
    assert(exist(expected, 'file') == 2, ...
        sprintf('Renamed helper does not resolve: %s', expected));
end

% QC overlay and the repo_legacy PCA dispatch both reach the renamed functions.
rand('state', 7);
out = pseudo_CT_overlay2(rand(4, 5), rand(4, 5), 0.5, 0, hot(8));
assert(isequal(size(out), [4 5 3]), 'QC overlay output shape changed.');
[pca_fn, backend] = pseudo_CT_pca_resolver(struct('pca_order', {{'repo_legacy'}}));
assert(strcmp(backend, 'repo_legacy'), 'repo_legacy PCA backend not selected.');
assert(strcmp(func2str(pca_fn), 'pseudo_CT_princomp_legacy'), ...
    'repo_legacy PCA handle does not resolve to pseudo_CT_princomp_legacy.');

fprintf('Helper name tests passed.\n');
end

function name = local_declared_name(file_path)
fid = fopen(file_path, 'r');
assert(fid ~= -1, sprintf('Cannot read %s', file_path));
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
name = '';
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    tok = regexp(line, '^function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?(\w+)', 'tokens', 'once');
    if ~isempty(tok)
        name = tok{1};
        break;
    end
end
end
