function run_lint()

root_dir = fileparts(fileparts(mfilename('fullpath')));

source_dirs = {
    fullfile(root_dir, 'src')
    fullfile(root_dir, 'vers')
};

matlab_files = {};
for i = 1:numel(source_dirs)
    files = dir(fullfile(source_dirs{i}, '**', '*.m'));
    for j = 1:numel(files)
        matlab_files{end+1} = fullfile(files(j).folder, files(j).name);
    end
end

entry_files = {
    fullfile(root_dir, 'run_pseudo_CT_local.m')
    fullfile(root_dir, 'run_pseudo_CT_launchpad.m')
};
for i = 1:numel(entry_files)
    if exist(entry_files{i}, 'file') == 2
        matlab_files{end+1} = entry_files{i};
    end
end

num_issues = 0;
for i = 1:numel(matlab_files)
    result = mlint(matlab_files{i});
    if ~isempty(result)
        num_issues = num_issues + numel(result);
        [~, name, ext] = fileparts(matlab_files{i});
        fprintf('Lint issues in %s%s:\n', name, ext);
        for j = 1:numel(result)
            fprintf('  L%d C%d: %s\n', ...
                result(j).line, result(j).column, result(j).message);
        end
        fprintf('\n');
    end
end

fprintf('Total files checked: %d\n', numel(matlab_files));
if num_issues == 0
    fprintf('No lint issues found.\n');
else
    fprintf('Total lint issues: %d\n', num_issues);
end

end
