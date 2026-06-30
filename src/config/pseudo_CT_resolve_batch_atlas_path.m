function batch_atlas_path = pseudo_CT_resolve_batch_atlas_path(repo_root)
% PSEUDO_CT_RESOLVE_BATCH_ATLAS_PATH  Resolve Batch_atlas location at runtime.
%   PATH = PSEUDO_CT_RESOLVE_BATCH_ATLAS_PATH(REPO_ROOT) resolves the
%   Batch_atlas directory via:
%     1. PSEUDOCT_BATCH_ATLAS environment variable
%     2. defaults_pseudo_CT('batch_atlas_path') config default
%     3. fullfile(REPO_ROOT, 'Batch_atlas') repo-adjacent fallback
%
%   Raises an error with every checked location if none exists.

candidates = struct('source', {}, 'path', {});

% 1. Environment variable
env_path = getenv('PSEUDOCT_BATCH_ATLAS');
if ~isempty(env_path)
    candidates(end + 1).source = 'env:PSEUDOCT_BATCH_ATLAS';
    candidates(end).path = env_path;
    if exist(env_path, 'dir') == 7
        batch_atlas_path = env_path;
        return;
    end
end

% 2. Config default
cfg_path = defaults_pseudo_CT('batch_atlas_path');
if ischar(cfg_path) && ~isempty(cfg_path)
    candidates(end + 1).source = 'defaults_pseudo_CT:batch_atlas_path';
    candidates(end).path = cfg_path;
    if exist(cfg_path, 'dir') == 7
        batch_atlas_path = cfg_path;
        return;
    end
end

% 3. Repo-adjacent fallback
fallback_path = fullfile(repo_root, 'Batch_atlas');
candidates(end + 1).source = 'repo-adjacent-fallback';
candidates(end).path = fallback_path;
if exist(fallback_path, 'dir') == 7
    batch_atlas_path = fallback_path;
    return;
end

% Resolution failed — list all checked locations
msg = sprintf('Batch_atlas not found. Checked locations:\n');
for ii = 1:length(candidates)
    msg = sprintf('%s  %s: %s\n', msg, candidates(ii).source, candidates(ii).path);
end
error('%s', msg);

return
