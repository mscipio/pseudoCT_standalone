function varargout = mlsc_release_gate(action, varargin)
%MLSC_RELEASE_GATE Shared exact-source release gate (MLSC CURRENT only).
%   Implements the fail-closed exact-source checks shared by the
%   opt-in release-candidate build path (scripts/build_mlsc_current.m)
%   and the publication validator (scripts/validate_mlsc_release.m).
%   Read-only git operations only, except ENSURE_WORKTREE which creates
%   an isolated clean checkout under scratch/release_gate/ (build host
%   only; never called by tests or by the validator).
%
%   Actions (deterministic, offline, no SSH/Slurm, no science, no mcc):
%     COMMIT = MLSC_RELEASE_GATE('resolve_commit', REPO_ROOT, TAG, COMMIT)
%       Resolve the expected release commit. TAG and COMMIT are character
%       rows ('' when absent); at least one is required. A given COMMIT
%       must be 40-hex. A given TAG is resolved read-only via
%       git rev-parse --verify <tag>^{commit} (unresolvable blocks); when
%       both are given they must agree (commit!=tag blocks).
%     TREE = MLSC_RELEASE_GATE('release_tree', REPO_ROOT, COMMIT)
%       Recomputed clean-tree fingerprint for COMMIT: git rev-parse
%       <commit>^{tree} (40-hex; unknown commit blocks). The tree hash is
%       the content identity of the exact release source.
%     TREE = MLSC_RELEASE_GATE('verify_clean_source', REPO_ROOT, COMMIT)
%       Fail-closed pre-compile gate: HEAD must equal COMMIT, the working
%       tree must be clean (empty porcelain status: no tracked mods and
%       no untracked non-ignored files), and HEAD^{tree} must equal
%       COMMIT^{tree}. Anything else blocks with an explicit reason.
%     PATH = MLSC_RELEASE_GATE('ensure_worktree', REPO_ROOT, COMMIT, LABEL)
%       Create a fresh detached clean worktree at
%       <repo>/scratch/release_gate/worktree-<LABEL> pinned at COMMIT,
%       or reuse an existing one ONLY after verifying its exact source:
%       the candidate directory must BE the repository top level
%       (canonical candidate path must equal controlled
%       `git -C <candidate> rev-parse --show-toplevel` with
%       GIT_DIR/GIT_WORK_TREE stripped; a plain subdirectory inside a
%       checkout reports its PARENT and is never trusted), worktree HEAD
%       must equal COMMIT, the worktree must have no uncommitted changes
%       (empty porcelain status), and HEAD^{tree} must equal
%       COMMIT^{tree}. A dirty, mismatched, or unverifiable
%       existing worktree is never reused (fail closed: the operator
%       removes it, then a fresh worktree is created on re-run).
%       Build-host only; tests and the validator never call this.
%     HEX = MLSC_RELEASE_GATE('sha256_file', PATH)
%       SHA-256 content hash of one file (Java, else sha256sum). Missing
%       or unhashable files block (no size/mtime fallback).
%     [FILES, CHECKSUMS, FP] = MLSC_RELEASE_GATE('inventory_dir', ROOT, EXCLUDE)
%       Complete SHA-256 inventory of every regular file under ROOT
%       (recursive, sorted, '/'-separated relpaths). FILES is a cell
%       vector of relpaths, CHECKSUMS parallels it as
%       '<rel> bytes=<N> sha256=<hex>', FP is the SHA-256 over canonical
%       '<rel>\t<hex>\n' text sorted by path. EXCLUDE lists relpaths to
%       skip (e.g. the self-describing manifest pair). Names containing
%       '.nfs' are skipped. Unreadable files block (no fallback).
%     FLAG = MLSC_RELEASE_GATE('is_valid_sha256', VALUE)
%       Strict 64-hex SHA-256 shape test (missing/empty/malformed false).
%
%   Every failure raises pseudo_CT:MLSCReleaseGate with an explicit
%   reason. Confinement: MLSC CURRENT release tooling only; LEGACY,
%   local, and Launchpad behavior are unchanged.
%
%   Minimum supported MATLAB: R2010b (era-safe idioms only).

if nargin < 1 || ~ischar(action) || size(action, 1) ~= 1
    error('pseudo_CT:MLSCReleaseGate', 'A release-gate action is required.');
end
action = strtrim(action);
if strcmp(action, 'resolve_commit')
    if numel(varargin) < 3
        error('pseudo_CT:MLSCReleaseGate', 'resolve_commit requires repo root, tag, and commit.');
    end
    varargout = {local_resolve_commit(varargin{1}, varargin{2}, varargin{3})};
    return;
end
if strcmp(action, 'release_tree')
    if numel(varargin) < 2
        error('pseudo_CT:MLSCReleaseGate', 'release_tree requires repo root and commit.');
    end
    varargout = {local_release_tree(varargin{1}, varargin{2})};
    return;
end
if strcmp(action, 'verify_clean_source')
    if numel(varargin) < 2
        error('pseudo_CT:MLSCReleaseGate', 'verify_clean_source requires repo root and commit.');
    end
    varargout = {local_verify_clean_source(varargin{1}, varargin{2})};
    return;
end
if strcmp(action, 'ensure_worktree')
    if numel(varargin) < 3
        error('pseudo_CT:MLSCReleaseGate', 'ensure_worktree requires repo root, commit, and label.');
    end
    varargout = {local_ensure_worktree(varargin{1}, varargin{2}, varargin{3})};
    return;
end
if strcmp(action, 'sha256_file')
    if numel(varargin) < 1
        error('pseudo_CT:MLSCReleaseGate', 'sha256_file requires a path.');
    end
    varargout = {local_sha256_file(varargin{1})};
    return;
end
if strcmp(action, 'inventory_dir')
    if numel(varargin) < 1
        error('pseudo_CT:MLSCReleaseGate', 'inventory_dir requires a root directory.');
    end
    exclude_here = {};
    if numel(varargin) >= 2
        exclude_here = varargin{2};
    end
    [files_out, sums_out, fp_out] = local_inventory_dir(varargin{1}, exclude_here);
    varargout = {files_out, sums_out, fp_out};
    return;
end
if strcmp(action, 'is_valid_sha256')
    if numel(varargin) < 1
        error('pseudo_CT:MLSCReleaseGate', 'is_valid_sha256 requires a value.');
    end
    varargout = {local_is_valid_sha256(varargin{1})};
    return;
end
error('pseudo_CT:MLSCReleaseGate', 'Unknown release-gate action: %s.', action);
end

function commit = local_resolve_commit(repo_root, tag, commit_arg)
tag = local_opt_row(tag);
commit_arg = local_opt_row(commit_arg);
if isempty(tag) && isempty(commit_arg)
    error('pseudo_CT:MLSCReleaseGate', ...
        'A release tag or release commit is required; missing release identity blocks publication.');
end
if ~isempty(commit_arg) && ~local_is_valid_commit(commit_arg)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Release commit must be 40-hex; got a malformed value.');
end
commit = lower(strtrim(commit_arg));
if ~isempty(tag)
    if isempty(regexp(tag, '^[A-Za-z0-9][A-Za-z0-9._/-]*$', 'once'))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Release tag has unexpected characters: %s.', tag);
    end
    if ~local_git_available(repo_root)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Cannot resolve release tag %s without a git repository; missing source evidence blocks publication.', tag);
    end
    [status, out] = system(sprintf('git -C "%s" --no-pager rev-parse --verify "%s^{commit}" 2>&1', ...
        strtrim(repo_root), tag));
    resolved = lower(strtrim(local_clean_git_text(out)));
    if status ~= 0 || ~local_is_valid_commit(resolved)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Release tag %s is unresolvable to a commit; wrong or missing tag blocks publication.', tag);
    end
    if ~isempty(commit) && ~strcmp(commit, resolved)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Release commit does not match tag %s (commit==tag failed); mismatch blocks publication.', tag);
    end
    commit = resolved;
end
end

function tree = local_release_tree(repo_root, commit_arg)
commit_arg = local_opt_row(commit_arg);
if ~local_is_valid_commit(commit_arg)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Release commit must be 40-hex for tree fingerprinting.');
end
if ~local_git_available(repo_root)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Cannot fingerprint the release tree without a git repository; missing source evidence blocks publication.');
end
[status, out] = system(sprintf('git -C "%s" --no-pager rev-parse "%s^{tree}" 2>&1', ...
    strtrim(repo_root), lower(strtrim(commit_arg))));
tree = lower(strtrim(local_clean_git_text(out)));
if status ~= 0 || ~local_is_valid_commit(tree)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Release commit is unknown or its tree is unavailable; mismatch blocks publication.');
end
end

function tree = local_verify_clean_source(repo_root, expected_commit)
expected_commit = local_opt_row(expected_commit);
if ~local_is_valid_commit(expected_commit)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Release commit must be 40-hex for source verification.');
end
expected_commit = lower(strtrim(expected_commit));
if ~local_git_available(repo_root)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Cannot verify exact source without a git repository; missing source evidence blocks compilation.');
end
root_here = strtrim(repo_root);
[s_head, head_out] = system(sprintf('git -C "%s" --no-pager rev-parse HEAD 2>&1', root_here));
head = lower(strtrim(local_clean_git_text(head_out)));
if s_head ~= 0 || ~local_is_valid_commit(head)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Source HEAD is unavailable; exact-source verification blocks compilation.');
end
if ~strcmp(head, expected_commit)
    error('pseudo_CT:MLSCReleaseGate', ...
        'HEAD %s does not match the release commit %s; inexact source blocks compilation.', head, expected_commit);
end
[~, status_out] = system(sprintf('git -C "%s" -c color.ui=false --no-pager status --porcelain=v1 2>&1', root_here));
porcelain = strtrim(local_clean_git_text(status_out));
if ~isempty(porcelain)
    entries = regexp(porcelain, char(10), 'split');
    error('pseudo_CT:MLSCReleaseGate', ...
        'Working tree is not clean (%d status entries); release compilation requires the exact release source.', ...
        numel(entries));
end
[~, tree_head_out] = system(sprintf('git -C "%s" --no-pager rev-parse "HEAD^{tree}" 2>&1', root_here));
tree_head = lower(strtrim(local_clean_git_text(tree_head_out)));
tree_want = local_release_tree(root_here, expected_commit);
if ~local_is_valid_commit(tree_head) || ~strcmp(tree_head, tree_want)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Clean-tree fingerprint does not match the release source; inexact source blocks compilation.');
end
tree = tree_want;
end

function wt_path = local_ensure_worktree(repo_root, commit_arg, label)
commit_arg = local_opt_row(commit_arg);
label = local_opt_row(label);
if ~local_is_valid_commit(commit_arg)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Release commit must be 40-hex for worktree isolation.');
end
if isempty(label) || isempty(regexp(label, '^[A-Za-z0-9][A-Za-z0-9._-]*$', 'once'))
    error('pseudo_CT:MLSCReleaseGate', ...
        'Worktree label has unexpected characters; refusing to create an ambiguous checkout.');
end
if ~local_git_available(repo_root)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Cannot isolate a clean worktree without a git repository.');
end
root_here = strtrim(repo_root);
gate_dir = fullfile(root_here, 'scratch', 'release_gate');
if exist(gate_dir, 'dir') ~= 7
    [ok_mk, msg_mk] = mkdir(gate_dir);
    if ~ok_mk
        error('pseudo_CT:MLSCReleaseGate', ...
            'Cannot create release-gate staging dir: %s.', msg_mk);
    end
end
wt_path = fullfile(gate_dir, ['worktree-' label]);
if exist(wt_path, 'dir') == 7
    % Anchor guard (strict top-level equality): the candidate must BE
    % the repository top level, not a plain subdirectory of one.
    % A .git-existence check alone is bypassable (a bogus .git entry
    % planted in a plain subdirectory still lets git discovery report
    % the CONTAINING repository's pristine state). Resolve the
    % candidate to a canonical absolute path, ask git in a
    % controlled environment (GIT_DIR/GIT_WORK_TREE stripped) for
    % the candidate's own top level, canonicalize that answer the
    % same way, and require EQUALITY. Every candidate-scoped git
    % read below uses the same controlled environment so conflicting
    % overrides cannot substitute another repository's state for the
    % candidate's. Standalone checkouts (.git
    % directory) and linked worktrees (.git file) both satisfy
    % equality; plain subdirectories (parent match), errors, and
    % unexpected values all refuse reuse as unverifiable.
    cand_canon = local_canonical_path(wt_path);
    top_canon = local_git_show_toplevel(wt_path);
    if isempty(cand_canon) || isempty(top_canon)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Existing worktree %s source is unverifiable; remove it before rebuilding the release candidate.', wt_path);
    end
    if ~strcmp(cand_canon, top_canon)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Existing worktree %s is not the repository top level (plain subdirectory is unverifiable); remove it before rebuilding the release candidate.', wt_path);
    end
    [s_wt, wt_out] = system(sprintf('env -u GIT_DIR -u GIT_WORK_TREE git -C "%s" --no-pager rev-parse HEAD 2>&1', wt_path));
    wt_head = lower(strtrim(local_clean_git_text(wt_out)));
    if s_wt ~= 0 || ~local_is_valid_commit(wt_head)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Existing worktree %s source is unverifiable; remove it before rebuilding the release candidate.', wt_path);
    end
    if ~strcmp(wt_head, lower(strtrim(commit_arg)))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Existing worktree %s pins another source; remove it before rebuilding the release candidate.', wt_path);
    end
    [~, wt_status_out] = system(sprintf('env -u GIT_DIR -u GIT_WORK_TREE git -C "%s" -c color.ui=false --no-pager status --porcelain=v1 2>&1', wt_path));
    wt_porcelain = strtrim(local_clean_git_text(wt_status_out));
    if ~isempty(wt_porcelain)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Existing worktree %s is not pristine (uncommitted changes); remove it before rebuilding the release candidate.', wt_path);
    end
    [~, wt_tree_out] = system(sprintf('env -u GIT_DIR -u GIT_WORK_TREE git -C "%s" --no-pager rev-parse "HEAD^{tree}" 2>&1', wt_path));
    wt_tree = lower(strtrim(local_clean_git_text(wt_tree_out)));
    want_tree = local_release_tree(root_here, commit_arg);
    if ~local_is_valid_commit(wt_tree) || ~strcmp(wt_tree, want_tree)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Existing worktree %s clean-tree fingerprint does not match the release source; remove it before rebuilding the release candidate.', wt_path);
    end
    return;
end
[s_add, ~] = system(sprintf('env -u GIT_DIR -u GIT_WORK_TREE git -C "%s" --no-pager worktree add --detach "%s" %s 2>&1', ...
    root_here, wt_path, lower(strtrim(commit_arg))));
if s_add ~= 0 || exist(wt_path, 'dir') ~= 7
    error('pseudo_CT:MLSCReleaseGate', ...
        'Clean worktree creation failed; refusing to compile from a possibly contaminated tree.');
end
[s_new, new_out] = system(sprintf('env -u GIT_DIR -u GIT_WORK_TREE git -C "%s" --no-pager rev-parse HEAD 2>&1', wt_path));
new_head = lower(strtrim(local_clean_git_text(new_out)));
if s_new ~= 0 || ~strcmp(new_head, lower(strtrim(commit_arg)))
    error('pseudo_CT:MLSCReleaseGate', ...
        'Fresh worktree %s does not pin the release source; refusing to compile from a possibly contaminated tree.', wt_path);
end
end

function hex = local_sha256_file(path_text)
if ~ischar(path_text) || size(path_text, 1) ~= 1 || isempty(strtrim(path_text))
    error('pseudo_CT:MLSCReleaseGate', 'A file path is required for hashing.');
end
if exist(strtrim(path_text), 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', 'File is missing, so its hash cannot match: %s.', strtrim(path_text));
end
hex = '';
try
    fid = fopen(strtrim(path_text), 'r');
    if fid == -1
        error('pseudo_CT:MLSCReleaseGate', 'File is unreadable: %s.', strtrim(path_text));
    end
    raw = fread(fid, inf, '*uint8')';
    fclose(fid);
    try
        digest = java.security.MessageDigest.getInstance('SHA-256');
        if ~isempty(raw)
            digest.update(raw);
        end
        bytes = typecast(digest.digest(), 'uint8');
        candidate = lower(reshape(dec2hex(bytes, 2)', 1, []));
        if local_is_valid_sha256(candidate)
            hex = candidate;
            return;
        end
    catch %#ok<CTCH>
    end
    try
        quoted = local_shell_quote(strtrim(path_text));
        [status, out] = system(['sha256sum ' quoted ' 2>/dev/null']);
        if status == 0 && ischar(out) && ~isempty(strtrim(out))
            tok = regexp(strtrim(out), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', 'tokens', 'once');
            if ~isempty(tok) && local_is_valid_sha256(tok{1})
                hex = lower(strtrim(tok{1}));
                return;
            end
        end
    catch %#ok<CTCH>
    end
catch ME
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    if strncmp(ME.identifier, 'pseudo_CT:', length('pseudo_CT:'))
        rethrow(ME);
    end
end
if ~local_is_valid_sha256(hex)
    error('pseudo_CT:MLSCReleaseGate', ...
        'File hashing is unavailable, so no hash fallback is permitted: %s.', strtrim(path_text));
end
end

function [files_out, sums_out, fp_out] = local_inventory_dir(root_dir, exclude_arg)
if ~ischar(root_dir) || size(root_dir, 1) ~= 1 || isempty(strtrim(root_dir)) || ...
        exist(strtrim(root_dir), 'dir') ~= 7
    error('pseudo_CT:MLSCReleaseGate', 'Inventory root is unavailable.');
end
excluded = {};
if ischar(exclude_arg) && size(exclude_arg, 1) == 1 && ~isempty(strtrim(exclude_arg))
    excluded = {strtrim(exclude_arg)};
elseif iscell(exclude_arg)
    for kk = 1:numel(exclude_arg)
        if ischar(exclude_arg{kk}) && size(exclude_arg{kk}, 1) == 1 && ~isempty(strtrim(exclude_arg{kk}))
            excluded{end + 1, 1} = strtrim(exclude_arg{kk}); %#ok<AGROW>
        end
    end
end
root_here = strtrim(root_dir);
rels = local_walk(root_here, '');
rels = sort(rels(:));
keep = {};
for kk = 1:numel(rels)
    rel_here = rels{kk};
    if ~isempty(strfind(rel_here, '.nfs'))
        continue;
    end
    skip = false;
    for jj = 1:numel(excluded)
        if strcmp(rel_here, excluded{jj})
            skip = true;
            break;
        end
    end
    if ~skip
        keep{end + 1, 1} = rel_here; %#ok<AGROW>
    end
end
files_out = keep;
sums_out = cell(size(keep));
canonical = '';
for kk = 1:numel(keep)
    full_here = fullfile(root_here, strrep(keep{kk}, '/', filesep));
    h = local_sha256_file(full_here);
    info = dir(full_here);
    if isempty(info)
        error('pseudo_CT:MLSCReleaseGate', 'Packaged file vanished during inventory: %s.', keep{kk});
    end
    sums_out{kk, 1} = sprintf('%s bytes=%d sha256=%s', keep{kk}, info(1).bytes, h);
    canonical = [canonical keep{kk} char(9) h char(10)]; %#ok<AGROW>
end
try
    digest = java.security.MessageDigest.getInstance('SHA-256');
    if ~isempty(canonical)
        digest.update(uint8(canonical));
    end
    bytes = typecast(digest.digest(), 'uint8');
    candidate = lower(reshape(dec2hex(bytes, 2)', 1, []));
    if local_is_valid_sha256(candidate)
        fp_out = candidate;
        return;
    end
catch %#ok<CTCH>
end
error('pseudo_CT:MLSCReleaseGate', 'Packaged-files fingerprint is unavailable; no fallback is permitted.');
end

function rels = local_walk(root_here, prefix)
rels = {};
listed = dir(fullfile(root_here, prefix, '*'));
names = {};
for kk = 1:numel(listed)
    nm = listed(kk).name;
    if strcmp(nm, '.') || strcmp(nm, '..')
        continue;
    end
    names{end + 1, 1} = nm; %#ok<AGROW>
end
names = sort(names);
for kk = 1:numel(names)
    if isempty(prefix)
        rel_here = names{kk};
    else
        rel_here = [prefix '/' names{kk}]; %#ok<AGROW>
    end
    full_here = fullfile(root_here, strrep(rel_here, '/', filesep));
    if exist(full_here, 'dir') == 7
        sub = local_walk(root_here, rel_here);
        for jj = 1:numel(sub)
            rels{end + 1, 1} = sub{jj}; %#ok<AGROW>
        end
    elseif exist(full_here, 'file') == 2
        rels{end + 1, 1} = rel_here; %#ok<AGROW>
    end
end
end

function flag = local_is_valid_sha256(value)
flag = false;
try
    if ~ischar(value) || size(value, 1) ~= 1
        return;
    end
    trimmed = strtrim(value);
    if length(trimmed) ~= 64
        return;
    end
    if isempty(regexp(trimmed, '^[0-9a-fA-F]{64}$', 'once'))
        return;
    end
    flag = true;
catch %#ok<CTCH>
    flag = false;
end
end

function flag = local_is_valid_commit(value)
flag = false;
try
    if ~ischar(value) || size(value, 1) ~= 1
        return;
    end
    trimmed = strtrim(value);
    if length(trimmed) ~= 40
        return;
    end
    if isempty(regexp(trimmed, '^[0-9a-fA-F]{40}$', 'once'))
        return;
    end
    flag = true;
catch %#ok<CTCH>
    flag = false;
end
end

function top_canon = local_git_show_toplevel(candidate_dir)
top_canon = '';
try
    if ~ischar(candidate_dir) || size(candidate_dir, 1) ~= 1 || ...
            isempty(strtrim(candidate_dir))
        return;
    end
    if exist(strtrim(candidate_dir), 'dir') ~= 7
        return;
    end
    % Controlled environment: strip conflicting GIT_DIR/GIT_WORK_TREE
    % overrides so the answer is the candidate's own top level.
    [status, out] = system(sprintf('env -u GIT_DIR -u GIT_WORK_TREE git -C "%s" --no-pager rev-parse --show-toplevel 2>&1', ...
        strtrim(candidate_dir)));
    if status ~= 0
        return;
    end
    top_raw = strtrim(local_clean_git_text(out));
    if isempty(top_raw)
        return;
    end
    top_canon = local_canonical_path(top_raw);
catch %#ok<CTCH>
    top_canon = '';
end
end

function canon = local_canonical_path(path_text)
canon = '';
try
    if ~ischar(path_text) || size(path_text, 1) ~= 1 || ...
            isempty(strtrim(path_text))
        return;
    end
    trimmed = strtrim(path_text);
    try
        jf = java.io.File(trimmed);
        try
            if ~jf.isAbsolute()
                jf = java.io.File(fullfile(pwd, trimmed));
            end
        catch %#ok<CTCH>
        end
        resolved = char(jf.getCanonicalPath());
        resolved = strrep(resolved, '\', '/');
        while length(resolved) > 1 && resolved(end) == '/'
            resolved(end) = '';
        end
        canon = strtrim(resolved);
        return;
    catch %#ok<CTCH>
    end
    abs_here = trimmed;
    if isempty(abs_here) || abs_here(1) ~= '/'
        abs_here = fullfile(pwd, abs_here);
    end
    abs_here = strrep(abs_here, '\', '/');
    parts = regexp(abs_here, '/', 'split');
    stack = {};
    for kk = 1:numel(parts)
        piece = parts{kk};
        if isempty(piece) || strcmp(piece, '.')
            continue;
        end
        if strcmp(piece, '..')
            if ~isempty(stack)
                stack(end) = [];
            end
            continue;
        end
        stack{end + 1, 1} = piece; %#ok<AGROW>
    end
    if isempty(stack)
        canon = '/';
    else
        canon = '';
        for kk = 1:numel(stack)
            canon = [canon '/' stack{kk}]; %#ok<AGROW>
        end
    end
catch %#ok<CTCH>
    canon = '';
end
end

function flag = local_git_available(repo_root)
flag = false;
try
    if ~ischar(repo_root) || size(repo_root, 1) ~= 1 || isempty(strtrim(repo_root))
        return;
    end
    if exist(strtrim(repo_root), 'dir') ~= 7
        return;
    end
    [status, ~] = system(sprintf('git -C "%s" --no-pager rev-parse --git-dir 2>&1', strtrim(repo_root)));
    flag = (status == 0);
catch %#ok<CTCH>
    flag = false;
end
end

function row = local_opt_row(value)
row = '';
try
    if ischar(value) && size(value, 1) == 1
        row = strtrim(value);
    end
catch %#ok<CTCH>
    row = '';
end
end

function clean = local_clean_git_text(txt)
clean = '';
if ~ischar(txt) || isempty(txt)
    return;
end
esc = char(27);
cr = char(13);
kk = 1;
n = length(txt);
while kk <= n
    ch = txt(kk);
    if ch == esc
        kk = kk + 1;
        if kk <= n && txt(kk) == '['
            kk = kk + 1;
            while kk <= n && ~((txt(kk) >= 'A' && txt(kk) <= 'Z') || ...
                    (txt(kk) >= 'a' && txt(kk) <= 'z') || txt(kk) == '~' || txt(kk) == '=')
                kk = kk + 1;
            end
            if kk <= n
                kk = kk + 1;
            end
        end
        continue;
    end
    if ch == cr
        kk = kk + 1;
        continue;
    end
    clean(end + 1) = ch; %#ok<AGROW>
    kk = kk + 1;
end
clean = strtrim(clean);
end

function quoted = local_shell_quote(value)
single_quote = char(39);
double_quote = char(34);
quoted = [single_quote single_quote];
try
    if ~ischar(value) || size(value, 1) ~= 1 || isempty(value)
        return;
    end
    quoted = single_quote;
    for ii = 1:length(value)
        if value(ii) == single_quote
            quoted = [quoted single_quote double_quote single_quote ...
                double_quote single_quote]; %#ok<AGROW>
        else
            quoted = [quoted value(ii)]; %#ok<AGROW>
        end
    end
    quoted = [quoted single_quote]; %#ok<AGROW>
catch %#ok<CTCH>
    quoted = [single_quote single_quote];
end
end
