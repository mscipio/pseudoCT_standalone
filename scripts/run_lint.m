function run_lint()
%RUN_LINT Developer-only MLINT pass over src/ and src/science/overrides.
%   RUN_LINT() runs MLINT on every .m file under src/ (recursive) and prints
%   each issue with its line and column. It writes no files.
%   Developer tool only, not part of the offline R2010b test suite. It uses
%   recursive dir('**') and the .folder field of dir output, which R2010b
%   does not provide, so run it in a newer MATLAB release. It is not
%   R2010b-compatible.

root_dir = fileparts(fileparts(mfilename('fullpath')));

source_dirs = {
    fullfile(root_dir, 'src')
    fullfile(root_dir, 'src', 'science', 'overrides')
};

matlab_files = {};
for i = 1:numel(source_dirs)
    files = dir(fullfile(source_dirs{i}, '**', '*.m'));
    for j = 1:numel(files)
        matlab_files{end+1} = fullfile(files(j).folder, files(j).name);
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
