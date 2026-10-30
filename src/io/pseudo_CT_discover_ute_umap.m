function [ute_fn, umap_fn] = pseudo_CT_discover_ute_umap(mprage_fn)
%PSEUDO_CT_DISCOVER_UTE_UMAP Shared UTE/UMAP autodiscovery for batch workflows.
%   [UTE_FN, UMAP_FN] = PSEUDO_CT_DISCOVER_UTE_UMAP(MPRAGE_FN) scans sibling
%   folders under the MR/ parent for UTE and UMAP content using dir()-only
%   calls (no ls wildcards). Returns 0 for each absent reference.
%
%   UTE search: case-insensitive match 'ute' and *0001* content.
%   UMAP search: case-insensitive match 'umap|ute|mu_map|mumap' and *0001*
%                content; first alphabetically sorted match is selected.
%   Diagnostic messages are written to stdout; this function never calls
%   warndlg or errors. Minimum supported MATLAB: R2010b.

ute_fn = 0;
umap_fn = 0;

[patha, ~, ~] = fileparts(deblank(mprage_fn));
ss = strfind(patha, strcat(filesep, 'MR', filesep));
dir_b = '';
if ~isempty(ss)
    dir_b = patha(1:(ss(end) + 3));
else
    mr_parent = fileparts(patha);
    potential_mr = fullfile(mr_parent, 'MR');
    if isdir(potential_mr)
        dir_b = [potential_mr, filesep];
    end
end

if isempty(dir_b)
    pseudo_CT_output('WARN', struct('scope', 'discovery'), 'No MR parent was found.');
    pseudo_CT_output('INFO', struct('scope', 'discovery'), '    %s', patha);
    return;
end

all_entries = dir(fullfile(dir_b, '*'));
siblings = all_entries([all_entries.isdir] & ~ismember({all_entries.name}, {'.', '..'}));

ute_candidates = {};
for ii = 1:length(siblings)
    name = siblings(ii).name;
    if isempty(regexpi(name, 'ute'))
        continue;
    end
    content = dir(fullfile(dir_b, name, '*0001*'));
    for jj = 1:length(content)
        ute_candidates{end + 1} = fullfile(dir_b, name, content(jj).name); %#ok<AGROW>
    end
end
if isempty(ute_candidates)
    pseudo_CT_output('WARN', struct('scope', 'discovery'), 'No UTE reference was found.');
elseif length(ute_candidates) == 1
    ute_fn = ute_candidates{1};
else
    ute_candidates = sort(ute_candidates);
    ute_fn = ute_candidates{1};
    pseudo_CT_output('WARN', struct('scope', 'discovery'), ...
        '%d UTE candidates were found; using the first sorted match.', length(ute_candidates));
end

umap_candidates = {};
for ii = 1:length(siblings)
    name = siblings(ii).name;
    if isempty(regexpi(name, 'umap|ute|mu_map|mumap'))
        continue;
    end
    content = dir(fullfile(dir_b, name, '*0001*'));
    for jj = 1:length(content)
        umap_candidates{end + 1} = fullfile(dir_b, name, content(jj).name); %#ok<AGROW>
    end
end
if isempty(umap_candidates)
    pseudo_CT_output('WARN', struct('scope', 'discovery'), 'No UMAP reference was found.');
elseif length(umap_candidates) == 1
    umap_fn = umap_candidates{1};
else
    umap_candidates = sort(umap_candidates);
    umap_fn = umap_candidates{1};
    pseudo_CT_output('WARN', struct('scope', 'discovery'), ...
        '%d UMAP candidates were found; using the first sorted match.', length(umap_candidates));
end
end
