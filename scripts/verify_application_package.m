function report = verify_application_package(package_dir)
%VERIFY_APPLICATION_PACKAGE Recompute the SHA-256 inventory of a package.
%   REPORT = VERIFY_APPLICATION_PACKAGE(PACKAGE_DIR) recomputes SHA-256 for
%   every file listed in SHA256SUMS and fails on any modified, missing, or
%   unexpected file (pseudo_CT:PackageTampered). SHA256SUMS lists every
%   package file except itself, including application_manifest.txt, so a
%   manifest edit is detected; the manifest file_count must equal the
%   inventory entry count. A coordinated rewrite of both files is detected
%   only if the printed SHA256SUMS digest was recorded elsewhere.
%   Verification only: nothing is compiled, executed, or modified.

manifest_path = fullfile(package_dir, 'application_manifest.txt');
inventory_path = fullfile(package_dir, 'SHA256SUMS');
if exist(package_dir, 'dir') ~= 7
    error('pseudo_CT:PackageIncomplete', 'Package directory missing: %s', package_dir);
end
if exist(manifest_path, 'file') ~= 2 || exist(inventory_path, 'file') ~= 2
    error('pseudo_CT:PackageIncomplete', ...
        'Package needs application_manifest.txt and SHA256SUMS: %s', package_dir);
end

% Parse SHA256SUMS ("<64 hex>  <relative path>" per line, sha256sum format).
listed = {};
expected = {};
lines = local_lines(fileread(inventory_path));
for kk = 1:numel(lines)
    line = lines{kk};
    if length(line) < 67 || ~isempty(regexp(line(1:64), '[^0-9a-f]', 'once')) || ...
            ~strcmp(line(65:66), '  ')
        error('pseudo_CT:PackageMalformed', 'Malformed SHA256SUMS line %d.', kk);
    end
    rel = line(67:end);
    if rel(1) == '/' || ~isempty(strfind(['/' rel '/'], '/../')) || ...
            ~isempty(strfind(rel, char(92)))
        error('pseudo_CT:PackageMalformed', 'Unsafe inventory path: %s', rel);
    end
    listed{end + 1, 1} = rel; %#ok<AGROW>
    expected{end + 1, 1} = line(1:64); %#ok<AGROW>
end
if isempty(listed) || numel(unique(listed)) ~= numel(listed)
    error('pseudo_CT:PackageMalformed', 'SHA256SUMS is empty or lists a path twice.');
end
if ~any(strcmp(listed, 'application_manifest.txt'))
    error('pseudo_CT:PackageMalformed', 'SHA256SUMS does not cover application_manifest.txt.');
end

% Manifest must agree with the inventory.
manifest = struct();
mlines = local_lines(fileread(manifest_path));
for kk = 1:numel(mlines)
    sp = find(mlines{kk} == ' ', 1);
    if isempty(sp)
        error('pseudo_CT:PackageMalformed', 'Malformed manifest line %d.', kk);
    end
    manifest.(mlines{kk}(1:sp - 1)) = mlines{kk}(sp + 1:end);
end
if ~isfield(manifest, 'schema') || ~strcmp(manifest.schema, 'pseudo-CT.application-package/v1')
    error('pseudo_CT:PackageMalformed', 'Unsupported or missing manifest schema.');
end
if ~isfield(manifest, 'file_count') || str2double(manifest.file_count) ~= numel(listed)
    error('pseudo_CT:PackageTampered', ...
        'Manifest file_count does not match SHA256SUMS (%d entries).', numel(listed));
end

% Every file on disk must be listed, and every listed file must match.
present = local_walk(package_dir, '');
present = present(~strcmp(present, 'SHA256SUMS'));
for kk = 1:numel(present)
    if ~any(strcmp(listed, present{kk}))
        error('pseudo_CT:PackageTampered', 'Unexpected file not in SHA256SUMS: %s', present{kk});
    end
end
for kk = 1:numel(listed)
    full_path = fullfile(package_dir, strrep(listed{kk}, '/', filesep));
    if exist(full_path, 'file') ~= 2
        error('pseudo_CT:PackageTampered', 'Listed file missing: %s', listed{kk});
    end
    actual = local_sha256(full_path);
    if isempty(actual) || ~strcmp(actual, expected{kk})
        error('pseudo_CT:PackageTampered', 'SHA-256 mismatch for %s.', listed{kk});
    end
end
% This verifies the build staging tree only (build_application.m calls it on its
% output), where the compiled dispatcher is nested under standalone/. Installed
% distributions are flat (runtimes/<LABEL>/pseudoct_standalone) and are verified
% by release_application.py. A standalone/ directory must contain its executable.
if exist(fullfile(package_dir, 'standalone'), 'dir') == 7 && ...
        exist(fullfile(package_dir, 'standalone', 'pseudoct_standalone'), 'file') ~= 2
    error('pseudo_CT:PackageIncomplete', ...
        'standalone/ lacks the compiled pseudoct_standalone dispatcher: %s', package_dir);
end

report = struct('passed', true, 'file_count', numel(listed), ...
    'release', local_field(manifest, 'release'), ...
    'source_commit', local_field(manifest, 'source_commit'), ...
    'inventory_sha256', local_sha256(inventory_path));
fprintf('PACKAGE_VERIFY_PASS files=%d release=%s inventory_sha256=%s\n', ...
    report.file_count, report.release, report.inventory_sha256);
end

function value = local_field(manifest, name)
value = '';
if isfield(manifest, name)
    value = manifest.(name);
end
end

function lines = local_lines(txt)
lines = regexp(txt, '\n', 'split');
for kk = 1:numel(lines)
    lines{kk} = regexprep(lines{kk}, char(13), '');
end
lines = lines(~cellfun(@isempty, lines));
end

function rels = local_walk(root_dir, prefix)
rels = {};
listed = dir(root_dir);
for kk = 1:numel(listed)
    name = listed(kk).name;
    if any(strcmp(name, {'.', '..'}))
        continue;
    end
    if isempty(prefix)
        rel = name;
    else
        rel = [prefix '/' name];
    end
    if listed(kk).isdir
        rels = [rels; local_walk(fullfile(root_dir, name), rel)]; %#ok<AGROW>
    else
        rels{end + 1, 1} = rel; %#ok<AGROW>
    end
end
end

function hex = local_sha256(path_text)
hex = '';
[status, out] = system(sprintf('sha256sum "%s"', path_text));
if status == 0
    token = regexp(out, '^[0-9a-fA-F]{64}', 'match', 'once');
    if ~isempty(token)
        hex = lower(token);
    end
end
end
