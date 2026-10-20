function archive_path = assemble_mlsc_release(varargin)
%ASSEMBLE_MLSC_RELEASE Assemble a versioned MLSC CURRENT release archive (no mcc, no science).
%   ARCHIVE = ASSEMBLE_MLSC_RELEASE('PackageDir', DIR, 'ReleaseTag', TAG,
%   'ReleaseCommit', COMMIT, 'GateARecord', PATH, 'OutputDir', DIR,
%   'SourceVersion', VER, 'RepoRoot', DIR) stages a validated
%   release-candidate package plus the versioned source tree plus MCR
%   compat/provenance evidence into a versioned .tar.gz under scratch/.
%
%   Why this exists (package-assembly demonstration, evidence-backed):
%   no existing mechanism assembles a release archive containing the
%   compiled distribution. The maintainer recipe (deprecated/Makefile,
%   targets lint/test/tag only) states it does not build release
%   archives; its commented git-archive recipe carries source only.
%   scripts/build_mlsc_current.m explicitly rejects tarball outputs and
%   stages only an unpacked tree (dist/ ordinary builds,
%   scratch/release_gate/<label>/ release candidates). The release gate
%   (docs/mlsc_current_release_gate.md section 6) states "no tarball",
%   and dist/ is ignored/untracked so git archive can never carry the
%   compiled payload. This script is therefore the smallest assembly
%   mechanism: versioned source (git-archive-equivalent tree honoring
%   the committed .gitattributes export-ignore policy) + compiled dist
%   (payload_build, build/resource manifests, companions) + MCR compat
%   info + release provenance, verified from the actual archive bytes.
%
%   Name-value arguments (character rows; R2010b-safe idioms):
%     'PackageDir'    Staged release-candidate package root: payload_build/
%                     plus build/resource manifests (required; must live
%                     under <repo>/scratch/ -- dist/ is never a source).
%     'ReleaseTag'    Expected release tag (e.g. v3.0.0-rc.1). Resolved
%                     read-only against RepoRoot (commit==tag enforced by
%                     the shared gate helper). The tag must ALSO be
%                     file-safe (no '/'): the gate tag charset admits '/',
%                     the archive label charset does not.
%     'ReleaseCommit' Expected 40-hex release commit (required when no
%                     tag is given; cross-checked with the tag otherwise).
%     'GateARecord'   Finalized Gate-A record binding this exact
%                     candidate (required; passed through to the
%                     publication validator, never minted here).
%     'OutputDir'     Archive destination (default
%                     <repo>/scratch/release_gate/<label>/). Must live
%                     under <repo>/scratch/; /usr/pubsw, dist/, and
%                     tarball paths are rejected.
%     'SourceVersion' Expected CHANGELOG line-1 version (default derived
%                     from the tag: leading 'v' stripped, '-rc*' suffix
%                     stripped, e.g. v3.0.0-rc.1 -> 3.0.0). Required when
%                     no tag is given; an explicit value with a tag must
%                     equal the derived one. The staged source tree's
%                     CHANGELOG.md line 1 must equal it.
%     'RepoRoot'      Git repository used for tag/tree/archive resolution
%                     (default: this repository root).
%
%   Contract (no weakening): prepublication validation runs FIRST via
%   scripts/validate_mlsc_release.m with the same Gate-A record, so any
%   missing/stale/mismatched/incomplete staged evidence blocks before
%   anything is archived. The shared src/mlsc/mlsc_release_gate.m helper
%   resolves commit/tree, hashes files, and recomputes the packaged
%   inventory. After archiving, the ACTUAL archive bytes are inspected:
%   single top-level prefix, required members present, export-ignored
%   paths absent, and every packaged SHA-256 recomputed from an archive
%   extraction. Compiled artifacts stay out of git: outputs live under
%   ignored scratch/ and this script never stages, commits, tags,
%   publishes, deploys, or installs anything.
%
%   Minimum supported MATLAB: R2010b (era-safe idioms only).

repo_guess = fileparts(fileparts(mfilename('fullpath')));
if exist('mlsc_release_gate', 'file') ~= 2
    addpath(fullfile(repo_guess, 'src', 'mlsc'));
end
if exist('validate_mlsc_release', 'file') ~= 2
    addpath(repo_guess);
    addpath(fullfile(repo_guess, 'scripts'));
end
if exist('mlsc_release_gate', 'file') ~= 2 || exist('validate_mlsc_release', 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', ...
        'Release tooling is unavailable; missing tooling blocks assembly.');
end

package_dir = '';
release_tag = '';
release_commit = '';
gate_a_record = '';
out_dir_arg = '';
source_version = '';
repo_root = repo_guess;
ii = 1;
while ii <= numel(varargin)
    if ~ischar(varargin{ii}) || size(varargin{ii}, 1) ~= 1
        error('pseudo_CT:MLSCReleaseGate', 'Assembly arguments must be name-value character rows.');
    end
    name_here = lower(strtrim(varargin{ii}));
    if ii + 1 > numel(varargin)
        error('pseudo_CT:MLSCReleaseGate', 'Missing value for assembly argument %s.', name_here);
    end
    val_here = varargin{ii + 1};
    if ~ischar(val_here) || size(val_here, 1) ~= 1
        error('pseudo_CT:MLSCReleaseGate', 'Assembly argument %s value must be a character row.', name_here);
    end
    switch name_here
        case 'packagedir'
            package_dir = strtrim(val_here);
        case 'releasetag'
            release_tag = strtrim(val_here);
        case 'releasecommit'
            release_commit = strtrim(val_here);
        case 'gatearecord'
            gate_a_record = strtrim(val_here);
        case 'outputdir'
            out_dir_arg = strtrim(val_here);
        case 'sourceversion'
            source_version = strtrim(val_here);
        case 'reporoot'
            repo_root = strtrim(val_here);
        otherwise
            error('pseudo_CT:MLSCReleaseGate', 'Unknown assembly argument %s.', name_here);
    end
    ii = ii + 2;
end

if isempty(package_dir)
    error('pseudo_CT:MLSCReleaseGate', 'PackageDir is required; missing staged package blocks assembly.');
end
if isempty(gate_a_record)
    error('pseudo_CT:MLSCReleaseGate', 'GateARecord is required; a candidate without Gate-A binding blocks assembly.');
end
if isempty(release_tag) && isempty(release_commit)
    error('pseudo_CT:MLSCReleaseGate', 'ReleaseTag or ReleaseCommit is required; missing release identity blocks assembly.');
end

% Path guards FIRST (fail closed before any git/validation work).
% dist/ is never an assembly source: the compiled tree is ignored and
% untracked, so only a validated scratch/-staged candidate qualifies.
local_require_scratch_tree(repo_root, package_dir, 'PackageDir');
local_reject_dist_source(package_dir, 'PackageDir');

% Label + expected source version. The archive label charset is the
% worktree-label rule (no '/'): v3.0.0-rc.1 satisfies both the gate tag
% charset and this label rule; a tag carrying '/' is refused here with
% an explicit reason instead of producing an ambiguous file name.
if ~isempty(release_tag)
    if isempty(regexp(release_tag, '^[A-Za-z0-9][A-Za-z0-9._-]*$', 'once'))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Release tag %s is not file-safe for an archive label (no ''/'' permitted); refusing ambiguous assembly.', ...
            release_tag);
    end
    label = release_tag;
    derived_version = local_version_from_tag(release_tag);
    if isempty(source_version)
        source_version = derived_version;
    elseif ~strcmp(source_version, derived_version)
        error('pseudo_CT:MLSCReleaseGate', ...
            'SourceVersion %s does not match the tag-derived version %s; version mismatch blocks assembly.', ...
            source_version, derived_version);
    end
else
    if isempty(source_version)
        error('pseudo_CT:MLSCReleaseGate', ...
            'SourceVersion is required when no ReleaseTag is given; missing version coherence blocks assembly.');
    end
    local_require_version_shape(source_version);
    if ~isempty(release_commit) && length(release_commit) >= 7
        label = ['commit-' lower(strtrim(release_commit(1:7)))];
    else
        label = 'commit-unknown';
    end
end
prefix = ['pseudoCT_mlsc-current-' label];

if isempty(out_dir_arg)
    out_dir_arg = fullfile(repo_root, 'scratch', 'release_gate', label);
end
local_require_scratch_tree(repo_root, out_dir_arg, 'OutputDir');
local_reject_dist_source(out_dir_arg, 'OutputDir');
if strcmp(local_canonical(out_dir_arg), local_canonical(package_dir))
    error('pseudo_CT:MLSCReleaseGate', ...
        'OutputDir must not equal PackageDir; refusing to archive a package into itself.');
end

% Shared exact-source resolution (commit==tag enforced; tree recomputed).
exp_commit = mlsc_release_gate('resolve_commit', repo_root, release_tag, release_commit);
release_tree_hash = mlsc_release_gate('release_tree', repo_root, exp_commit);
fprintf('ASSEMBLY_IDENTITY label=%s commit=%s tree=%s source_version=%s\n', ...
    label, exp_commit, release_tree_hash, source_version);

% Gate contract without weakening: the publication validator must PASS
% on the staged package before anything is archived.
if ~isempty(release_tag)
    validate_mlsc_release('prepublication', 'PackageDir', package_dir, ...
        'ReleaseTag', release_tag, 'ReleaseCommit', exp_commit, ...
        'GateARecord', gate_a_record, 'RepoRoot', repo_root);
else
    validate_mlsc_release('prepublication', 'PackageDir', package_dir, ...
        'ReleaseCommit', exp_commit, ...
        'GateARecord', gate_a_record, 'RepoRoot', repo_root);
end

build = local_load_build(package_dir);

if exist(out_dir_arg, 'dir') ~= 7
    [ok_out, msg_out] = mkdir(out_dir_arg);
    if ~ok_out
        error('pseudo_CT:MLSCReleaseGate', 'Cannot create assembly output dir %s: %s.', out_dir_arg, msg_out);
    end
end
stage_root = fullfile(out_dir_arg, ['stage-' label]);
verify_root = fullfile(out_dir_arg, ['verify-' label]);
if exist(stage_root, 'dir') == 7
    rmdir(stage_root, 's');
end
if exist(verify_root, 'dir') == 7
    rmdir(verify_root, 's');
end
mkdir(stage_root);
mkdir(verify_root);
cleanup_tmp = onCleanup(@() local_cleanup_dirs(stage_root, verify_root)); %#ok<NASGU>
asm_root = fullfile(stage_root, prefix);
source_stage = fullfile(asm_root, 'source');
compiled_stage = fullfile(asm_root, 'compiled');
mkdir(asm_root);
mkdir(source_stage);
mkdir(compiled_stage);

% Versioned source: git-archive-equivalent tree of the exact release
% commit (honors the committed .gitattributes export-ignore policy).
src_tar = fullfile(stage_root, 'source.tar');
[~, ~] = system(sprintf('rm -f %s 2>/dev/null', local_shell_quote(src_tar)));
[s_arc, ~] = system(sprintf('git -C %s --no-pager archive --format=tar -o %s %s 2>&1', ...
    local_shell_quote(repo_root), local_shell_quote(src_tar), exp_commit));
if s_arc ~= 0 || exist(src_tar, 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', ...
        'Versioned source archive of commit %s is unavailable; missing source blocks assembly.', exp_commit);
end
[s_unt, ~] = system(sprintf('tar -xf %s -C %s 2>&1', ...
    local_shell_quote(src_tar), local_shell_quote(source_stage)));
if s_unt ~= 0
    error('pseudo_CT:MLSCReleaseGate', ...
        'Versioned source extraction failed; incomplete source blocks assembly.');
end
delete(src_tar);
fprintf('ASSEMBLY_SOURCE staged versioned source tree of %s.\n', exp_commit);

% Compiled dist: byte copy of the validated staged package.
local_copy_tree(package_dir, compiled_stage);
fprintf('ASSEMBLY_COMPILED staged validated package from %s.\n', package_dir);

% MCR compat info + release provenance (generated from the bound manifest).
local_write_text(fullfile(asm_root, 'MCR_COMPAT.txt'), local_compat_text(build));
local_write_text(fullfile(asm_root, 'RELEASE_PROVENANCE.txt'), ...
    local_provenance_text(label, release_tag, exp_commit, release_tree_hash, source_version, build));

% Version coherence against the STAGED source (fail fast, before tar).
staged_changelog = fullfile(source_stage, 'CHANGELOG.md');
if exist(staged_changelog, 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', ...
        'Staged source lacks CHANGELOG.md; incomplete source blocks assembly.');
end
staged_version = local_first_line(staged_changelog);
if ~strcmp(staged_version, source_version)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Staged CHANGELOG version %s does not match SourceVersion %s; version mismatch blocks assembly.', ...
        staged_version, source_version);
end

archive_path = fullfile(out_dir_arg, [prefix '.tar.gz']);
[~, ~] = system(sprintf('rm -f %s 2>/dev/null', local_shell_quote(archive_path)));
[s_tar, ~] = system(sprintf('tar -czf %s -C %s %s 2>&1', ...
    local_shell_quote(archive_path), local_shell_quote(stage_root), local_shell_quote(prefix)));
if s_tar ~= 0 || exist(archive_path, 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', 'Release archive creation failed; missing archive blocks assembly.');
end
info_arc = dir(archive_path);
if isempty(info_arc) || info_arc(1).bytes <= 0
    error('pseudo_CT:MLSCReleaseGate', 'Release archive is empty; incomplete archive blocks assembly.');
end
fprintf('ASSEMBLY_ARCHIVE wrote %s (%d bytes).\n', archive_path, info_arc(1).bytes);

% Verify the ACTUAL archive bytes: listing, single prefix, required
% members, export-ignore absences, then extraction + recomputed hashes.
[s_list, list_out] = system(sprintf('tar -tzf %s 2>&1', local_shell_quote(archive_path)));
if s_list ~= 0
    error('pseudo_CT:MLSCReleaseGate', 'Release archive listing failed; unverifiable archive blocks assembly.');
end
members = local_lines(list_out);
if isempty(members)
    error('pseudo_CT:MLSCReleaseGate', 'Release archive member list is empty; incomplete archive blocks assembly.');
end
local_check_members(members, prefix);
[s_ext, ~] = system(sprintf('tar -xzf %s -C %s 2>&1', ...
    local_shell_quote(archive_path), local_shell_quote(verify_root)));
if s_ext ~= 0
    error('pseudo_CT:MLSCReleaseGate', 'Release archive extraction failed; unverifiable archive blocks assembly.');
end
local_check_hashes(fullfile(verify_root, prefix), build);

archive_sha = mlsc_release_gate('sha256_file', archive_path);
fprintf('ASSEMBLY_SUCCESS archive=%s sha256=%s members=%d\n', archive_path, archive_sha, numel(members));
end

function local_require_scratch_tree(repo_root, path_here, label)
if isempty(path_here)
    error('pseudo_CT:MLSCReleaseGate', '%s is required; missing path blocks assembly.', label);
end
repo_canon = local_canonical(repo_root);
scratch_canon = [repo_canon filesep 'scratch'];
path_canon = local_canonical(path_here);
if strcmp(path_canon, scratch_canon)
    return;
end
scratch_prefix = [scratch_canon filesep];
if strncmp(path_canon, scratch_prefix, length(scratch_prefix))
    return;
end
error('pseudo_CT:MLSCReleaseGate', ...
    '%s must live under <repo>/scratch/ (got %s); refusing non-scratch assembly I/O.', label, path_here);
end

function local_reject_dist_source(path_here, label)
canon = local_canonical(path_here);
if ~isempty(strfind(canon, '/usr/pubsw'))
    error('pseudo_CT:MLSCReleaseGate', ...
        '%s must not target /usr/pubsw: %s.', label, path_here);
end
segs = regexp(canon, '/', 'split');
for kk = 1:numel(segs)
    if strcmp(segs{kk}, 'dist')
        error('pseudo_CT:MLSCReleaseGate', ...
            '%s must never use dist/ as source or destination (ignored nonproduction tree): %s.', label, path_here);
    end
end
low = lower(strtrim(path_here));
if length(low) >= 7 && strcmp(low(end - 6:end), '.tar.gz')
    error('pseudo_CT:MLSCReleaseGate', '%s must be a directory, not a tarball: %s.', label, path_here);
end
if length(low) >= 4 && strcmp(low(end - 3:end), '.tgz')
    error('pseudo_CT:MLSCReleaseGate', '%s must be a directory, not a tarball: %s.', label, path_here);
end
end

function version = local_version_from_tag(tag)
s = strtrim(tag);
if ~isempty(s) && (s(1) == 'v' || s(1) == 'V')
    s = s(2:end);
end
rc_pos = strfind(lower(s), '-rc');
if ~isempty(rc_pos)
    s = s(1:rc_pos(1) - 1);
end
if isempty(regexp(s, '^[0-9]+\.[0-9]+\.[0-9]+$', 'once'))
    error('pseudo_CT:MLSCReleaseGate', ...
        'Release tag %s does not carry a version shape (want vX.Y.Z[-rcN]); version mismatch blocks assembly.', tag);
end
version = s;
end

function local_require_version_shape(value)
if ~ischar(value) || isempty(regexp(strtrim(value), '^[0-9]+\.[0-9]+\.[0-9]+$', 'once'))
    error('pseudo_CT:MLSCReleaseGate', ...
        'SourceVersion must have version shape X.Y.Z; version mismatch blocks assembly.');
end
end

function build = local_load_build(package_dir)
manifest_path = fullfile(package_dir, 'mlsc_current_build.mat');
if exist(manifest_path, 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest is missing: %s; missing evidence blocks assembly.', manifest_path);
end
loaded = load(manifest_path);
if ~isfield(loaded, 'build')
    error('pseudo_CT:MLSCReleaseGate', 'Build manifest is missing variable build; manifest inconsistency blocks assembly.');
end
build = loaded.build;
if ~isstruct(build) || numel(build) ~= 1
    error('pseudo_CT:MLSCReleaseGate', 'Build manifest variable build must be one scalar struct; manifest inconsistency blocks assembly.');
end
if ~isfield(build, 'schema') || ~ischar(build.schema) || ...
        ~strcmp(build.schema, 'pseudo-CT.mlsc-current-build/v1')
    error('pseudo_CT:MLSCReleaseGate', 'Build manifest has an unexpected schema; manifest inconsistency blocks assembly.');
end
end

function local_copy_tree(src_dir, dst_dir)
listed = dir(src_dir);
for kk = 1:numel(listed)
    nm = listed(kk).name;
    if strcmp(nm, '.') || strcmp(nm, '..')
        continue;
    end
    [ok_cp, msg_cp] = copyfile(fullfile(src_dir, nm), fullfile(dst_dir, nm));
    if ~ok_cp
        error('pseudo_CT:MLSCReleaseGate', ...
            'Staged file %s could not be copied into the assembly: %s.', nm, msg_cp);
    end
end
end

function lines = local_compat_text(build)
lines = {'# MCR compatibility (generated from the bound build manifest; .mat is authority)'};
fields = {'compiler_identity'; 'release'; 'mcr_root'; 'arch'; 'generation'; ...
    'update_minimum'; 'runner_contract'; 'gate_a_status'};
for kk = 1:numel(fields)
    if ~isfield(build, fields{kk})
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest is missing MCR compat field %s; manifest inconsistency blocks assembly.', fields{kk});
    end
    value = build.(fields{kk});
    if isnumeric(value)
        value = mat2str(value);
    end
    if ~ischar(value)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest MCR compat field %s is not text; manifest inconsistency blocks assembly.', fields{kk});
    end
    lines{end + 1, 1} = sprintf('%s %s', fields{kk}, strtrim(value)); %#ok<AGROW>
end
if ~isfield(build, 'mcr_version') || ~isnumeric(build.mcr_version) || numel(build.mcr_version) ~= 2
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest mcr_version is invalid; manifest inconsistency blocks assembly.');
end
lines{end + 1, 1} = sprintf('mcr_version [%d %d]', build.mcr_version(1), build.mcr_version(2)); %#ok<AGROW>
if ~isfield(build, 'required_toolboxes') || ~iscell(build.required_toolboxes)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest required toolboxes are invalid; manifest inconsistency blocks assembly.');
end
for kk = 1:numel(build.required_toolboxes)
    entry = build.required_toolboxes{kk};
    if ~ischar(entry)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest required toolboxes carry a non-text entry; manifest inconsistency blocks assembly.');
    end
    lines{end + 1, 1} = sprintf('toolbox %s', strtrim(entry)); %#ok<AGROW>
end
end

function lines = local_provenance_text(label, tag, commit, tree, version, build)
stamp = '';
try
    [~, out] = system('date -u +%Y-%m-%dT%H:%M:%SZ 2>&1');
    stamp = strtrim(out);
catch %#ok<CTCH>
end
lines = {'# Release provenance (generated at assembly; build manifest is authority for hashes)'; ...
    sprintf('assembly_label %s', label); ...
    sprintf('release_tag %s', tag); ...
    sprintf('release_commit %s', commit); ...
    sprintf('release_tree %s', tree); ...
    sprintf('source_version %s', version); ...
    sprintf('assembled_utc %s', stamp)};
if isfield(build, 'source_provenance_fingerprint') && ischar(build.source_provenance_fingerprint)
    lines{end + 1, 1} = sprintf('source_provenance_fingerprint %s', ... %#ok<AGROW>
        strtrim(build.source_provenance_fingerprint));
end
if isfield(build, 'packaged_files_fingerprint') && ischar(build.packaged_files_fingerprint)
    lines{end + 1, 1} = sprintf('packaged_files_fingerprint %s', ... %#ok<AGROW>
        strtrim(build.packaged_files_fingerprint));
end
end

function first = local_first_line(path_text)
first = '';
fid = fopen(path_text, 'r');
if fid == -1
    error('pseudo_CT:MLSCReleaseGate', 'Cannot read %s; missing source blocks assembly.', path_text);
end
try
    line = fgetl(fid);
    fclose(fid);
catch %#ok<CTCH>
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    error('pseudo_CT:MLSCReleaseGate', 'Cannot read %s; missing source blocks assembly.', path_text);
end
if ~ischar(line)
    error('pseudo_CT:MLSCReleaseGate', 'Version source %s is empty; incomplete source blocks assembly.', path_text);
end
first = strtrim(line);
end

function lines = local_lines(txt)
lines = {};
if isempty(txt)
    return;
end
parts = strsplit(strtrim(txt), char(10));
for kk = 1:numel(parts)
    t = strtrim(parts{kk});
    if ~isempty(t)
        lines{end + 1, 1} = t; %#ok<AGROW>
    end
end
end

function local_check_members(members, prefix)
root_prefix = [prefix '/'];
for kk = 1:numel(members)
    entry = members{kk};
    if isempty(strfind(entry, root_prefix)) || strncmp(entry, '/', 1)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Archive member %s escapes the versioned prefix; mismatched layout blocks assembly.', entry);
    end
    if ~strncmp(entry, root_prefix, length(root_prefix))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Archive carries more than one top-level directory (%s); mismatched layout blocks assembly.', entry);
    end
    if ~isempty(strfind(entry, '..'))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Archive member %s carries an unsafe path; mismatched layout blocks assembly.', entry);
    end
    if ~isempty(strfind(entry, '.nfs'))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Archive member %s is environmental; stale content blocks assembly.', entry);
    end
    if ~isempty(strfind(entry, [root_prefix 'source/scripts/'])) || ...
            ~isempty(strfind(entry, [root_prefix 'source/docs/'])) || ...
            ~isempty(strfind(entry, [root_prefix 'source/deprecated/']))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Archive member %s violates the export-ignore policy; mismatched source blocks assembly.', entry);
    end
end
required = {'source/CHANGELOG.md'; 'source/run_pseudo_CT.m'; ...
    'compiled/payload_build/run_mlsc_current_payload.sh'; ...
    'compiled/payload_build/mlsc_current_payload'; ...
    'compiled/mlsc_current_build.mat'; 'compiled/mlsc_current_resources.mat'; ...
    'MCR_COMPAT.txt'; 'RELEASE_PROVENANCE.txt'};
for kk = 1:numel(required)
    want = [root_prefix required{kk}];
    found = false;
    for jj = 1:numel(members)
        if strcmp(members{jj}, want)
            found = true;
            break;
        end
    end
    if ~found
        error('pseudo_CT:MLSCReleaseGate', ...
            'Archive is missing required member %s; incomplete archive blocks assembly.', required{kk});
    end
end
end

function local_check_hashes(extract_root, build)
if ~isfield(build, 'packaged_files') || ~iscell(build.packaged_files) || ...
        ~isfield(build, 'packaged_checksums') || ~iscell(build.packaged_checksums) || ...
        numel(build.packaged_files) ~= numel(build.packaged_checksums) || isempty(build.packaged_files)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest packaged-files inventory is inconsistent; manifest inconsistency blocks assembly.');
end
for kk = 1:numel(build.packaged_files)
    rel_here = build.packaged_files{kk};
    if ~ischar(rel_here) || isempty(strtrim(rel_here)) || ~isempty(strfind(rel_here, '..'))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest packaged inventory carries an unsafe path; manifest inconsistency blocks assembly.');
    end
    disk_here = fullfile(extract_root, 'compiled', strrep(strtrim(rel_here), '/', filesep));
    if exist(disk_here, 'file') ~= 2
        error('pseudo_CT:MLSCReleaseGate', ...
            'Archived file %s is missing after extraction; incomplete archive blocks assembly.', strtrim(rel_here));
    end
    recorded = local_inventory_sha(build.packaged_checksums{kk});
    if isempty(recorded)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest inventory entry for %s is malformed; manifest inconsistency blocks assembly.', ...
            strtrim(rel_here));
    end
    actual_hex = mlsc_release_gate('sha256_file', disk_here);
    if ~strcmpi(recorded, actual_hex)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Archived file %s differs from the build manifest; archive-vs-build mismatch blocks assembly.', ...
            strtrim(rel_here));
    end
end
[~, ~, disk_fp] = mlsc_release_gate('inventory_dir', fullfile(extract_root, 'compiled'), ...
    {'mlsc_current_build.mat', 'mlsc_current_build.txt'});
if ~isfield(build, 'packaged_files_fingerprint') || ...
        ~strcmpi(strtrim(build.packaged_files_fingerprint), disk_fp)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Recomputed packaged-files fingerprint differs after extraction; archive-vs-build mismatch blocks assembly.');
end
pairs = {'runner_checksum', fullfile(extract_root, 'compiled', 'payload_build', 'run_mlsc_current_payload.sh'); ...
    'executable_fingerprint', fullfile(extract_root, 'compiled', 'payload_build', 'mlsc_current_payload'); ...
    'resource_fingerprint', fullfile(extract_root, 'compiled', 'mlsc_current_resources.mat')};
for kk = 1:size(pairs, 1)
    if ~isfield(build, pairs{kk, 1}) || ~ischar(build.(pairs{kk, 1}))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest %s is invalid; manifest inconsistency blocks assembly.', pairs{kk, 1});
    end
    if ~strcmpi(strtrim(build.(pairs{kk, 1})), mlsc_release_gate('sha256_file', pairs{kk, 2}))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Archived %s differs from the build manifest; archive-vs-build mismatch blocks assembly.', pairs{kk, 1});
    end
end
end

function sha = local_inventory_sha(entry)
sha = '';
try
    if ~ischar(entry) || size(entry, 1) ~= 1
        return;
    end
    tok = regexp(entry, 'sha256=([0-9a-fA-F]{64})(?![0-9a-fA-F])', 'tokens', 'once');
    if isempty(tok)
        return;
    end
    candidate = lower(strtrim(tok{1}));
    if mlsc_release_gate('is_valid_sha256', candidate)
        sha = candidate;
    end
catch %#ok<CTCH>
    sha = '';
end
end

function p = local_canonical(path_text)
p = strtrim(path_text);
try
    jf = java.io.File(p);
    p = char(jf.getCanonicalPath());
catch %#ok<CTCH>
end
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

function local_write_text(path_text, lines)
fid = fopen(path_text, 'w');
if fid == -1
    error('pseudo_CT:MLSCReleaseGate', 'Cannot write %s.', path_text);
end
cleanup_fid = onCleanup(@() local_close_fid(fid)); %#ok<NASGU>
for kk = 1:numel(lines)
    count = fprintf(fid, '%s\n', lines{kk});
    if count ~= length(lines{kk}) + 1
        error('pseudo_CT:MLSCReleaseGate', 'Incomplete write %s.', path_text);
    end
end
end

function local_close_fid(fid)
try
    fclose(fid);
catch %#ok<CTCH>
end
end

function local_cleanup_dirs(varargin)
for kk = 1:numel(varargin)
    try
        if exist(varargin{kk}, 'dir') == 7
            rmdir(varargin{kk}, 's');
        end
    catch %#ok<CTCH>
    end
end
end
