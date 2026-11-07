function umap_fn = pseudo_CT_discover_umap(mprage_fn)
%PSEUDO_CT_DISCOVER_UMAP UMAP reference beside an MPRAGE, or 0 when none.
%   Same sibling-folder rule as src/io/pseudo_CT_discover_ute_umap (UMAP
%   half only, without its logger, so it ships without src/): the folders
%   under the MR ancestor whose names match umap|ute|mu_map|mumap, first file
%   matching *0001*. Several candidates resolve to the first sorted one.
%   Minimum supported MATLAB: R2010b.

umap_fn = 0;
[patha, ~, ~] = fileparts(deblank(mprage_fn));
ss = strfind(patha, strcat(filesep, 'MR', filesep));
dir_b = '';
if ~isempty(ss)
    dir_b = patha(1:(ss(end) + 3));
else
    potential_mr = fullfile(fileparts(patha), 'MR');
    if isdir(potential_mr)
        dir_b = [potential_mr, filesep];
    end
end
if isempty(dir_b)
    return;
end
all_entries = dir(fullfile(dir_b, '*'));
siblings = all_entries([all_entries.isdir] & ~ismember({all_entries.name}, {'.', '..'}));
candidates = {};
for ii = 1:length(siblings)
    name = siblings(ii).name;
    if isempty(regexpi(name, 'umap|ute|mu_map|mumap'))
        continue;
    end
    content = dir(fullfile(dir_b, name, '*0001*'));
    for jj = 1:length(content)
        candidates{end + 1} = fullfile(dir_b, name, content(jj).name); %#ok<AGROW>
    end
end
if length(candidates) == 1
    umap_fn = candidates{1};
elseif length(candidates) > 1
    candidates = sort(candidates);
    umap_fn = candidates{1};
end
end
