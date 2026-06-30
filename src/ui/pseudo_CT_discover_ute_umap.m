function [ute_fn, umap_fn] = pseudo_CT_discover_ute_umap(mprage_fn)
% PSEUDO_CT_DISCOVER_UTE_UMAP  Shared UTE/UMAP autodiscovery for batch and GUI.
%   [UTE_FN, UMAP_FN] = PSEUDO_CT_DISCOVER_UTE_UMAP(MPRAGE_FN) scans sibling
%   folders under the MR/ parent for UTE and UMAP content using dir()-only
%   calls (no ls wildcards).  Returns 0 for each absent reference.
%
%   UTE search:  case-insensitive match 'ute' → validate *0001* content.
%   UMAP search: case-insensitive match 'umap|ute|mu_map|mumap' → validate
%                *0001* content → first alphabetically sorted match.
%
%   Diagnostic messages are written to stdout; the function never calls
%   warndlg or errors.

ute_fn = 0;
umap_fn = 0;

[patha, ~, ~] = fileparts(deblank(mprage_fn));
ss = strfind(patha, strcat(filesep, 'MR', filesep));
if isempty(ss)
    fprintf(1, 'WARNING: No MR/ parent in %s\n', patha);
    return;
end

dir_b = patha(1:(ss(end) + 3));  % includes trailing 'MR'

% --- gather sibling directories (skip . and ..) ---
all_entries = dir(fullfile(dir_b, '*'));
siblings = all_entries([all_entries.isdir] & ~ismember({all_entries.name}, {'.', '..'}));

% ===== UTE discovery =====
ute_candidates = {};
for ii = 1:length(siblings)
    name = siblings(ii).name;
    if isempty(regexpi(name, 'ute'))
        continue;
    end
    content = dir(fullfile(dir_b, name, '*0001*'));
    for jj = 1:length(content)
        ute_candidates{end + 1} = fullfile(dir_b, name, content(jj).name);
    end
end

if isempty(ute_candidates)
    fprintf(1, 'WARNING: No UTE found in %s\n', dir_b);
elseif length(ute_candidates) == 1
    ute_fn = ute_candidates{1};
else
    ute_candidates = sort(ute_candidates);
    ute_fn = ute_candidates{1};
    fprintf(1, 'WARNING: %d UTE candidates in %s, using %s\n', ...
        length(ute_candidates), dir_b, ute_fn);
end

% ===== UMAP discovery =====
umap_candidates = {};
for ii = 1:length(siblings)
    name = siblings(ii).name;
    if isempty(regexpi(name, 'umap|ute|mu_map|mumap'))
        continue;
    end
    content = dir(fullfile(dir_b, name, '*0001*'));
    for jj = 1:length(content)
        umap_candidates{end + 1} = fullfile(dir_b, name, content(jj).name);
    end
end

if isempty(umap_candidates)
    fprintf(1, 'WARNING: No UMAP found in %s\n', dir_b);
elseif length(umap_candidates) == 1
    umap_fn = umap_candidates{1};
else
    umap_candidates = sort(umap_candidates);
    umap_fn = umap_candidates{1};
    [~, folder_name] = fileparts(fileparts(umap_fn));
    fprintf(1, 'WARNING: %d UMAP candidates in %s%s/, using %s\n', ...
        length(umap_candidates), dir_b, folder_name, umap_fn);
end

return
