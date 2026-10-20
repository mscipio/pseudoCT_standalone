function ok = validate_mlsc_release(action, varargin)
%VALIDATE_MLSC_RELEASE Fail-closed MLSC CURRENT release-publication validator.
%   OK = VALIDATE_MLSC_RELEASE('prepublication', 'Name', VALUE, ...)
%   verifies a staged release-candidate package BEFORE publication, and
%   OK = VALIDATE_MLSC_RELEASE('postinstall', 'Name', VALUE, ...)
%   verifies a deployment copy AFTER installation at its exact runtime
%   path. Any missing or mismatched evidence BLOCKS with an explicit
%   reason (error id pseudo_CT:MLSCReleaseGate); success returns true.
%
%   Name-value arguments (character rows; R2010b-safe idioms):
%     'PackageDir'    Staged candidate root: payload_build/ plus the
%                     build/resource manifests (prepublication only).
%     'BuildManifest' Build manifest .mat (variable build). Defaults to
%                     <PackageDir>/mlsc_current_build.mat in prepublication;
%                     required explicitly in postinstall.
%     'ResourceManifest'
%                     Resource manifest .mat (variable resources). Defaults
%                     to <PackageDir>/mlsc_current_resources.mat in
%                     prepublication; required explicitly in postinstall.
%     'ReleaseTag'    Expected release tag (e.g. v2.8.5). Resolved
%                     read-only against RepoRoot (commit==tag enforced).
%     'ReleaseCommit' Expected 40-hex release commit (required when no
%                     tag is given; cross-checked with the tag otherwise).
%     'ExpectedFingerprint'
%                     Optional out-of-band source fingerprint the manifest
%                     must carry (wrong hash blocks).
%     'GateARecord'   Finalized Gate-A record .mat (variable gate_a,
%                     schema pseudo-CT.mlsc-current-gate-a/v1) binding this
%                     exact candidate. Always required (missing blocks).
%     'DeployRoot'    Exact production runtime root of the deployment
%                     copy (postinstall only; prepublication rejects it).
%                     The layout is pinned by the mlsc-current profile:
%                     the launcher sits directly at
%                     <DeployRoot>/run_mlsc_current_payload.sh (never
%                     nested under payload_build/), the compiled
%                     executable beside it, and the build/resource
%                     manifests alongside; BuildManifest/ResourceManifest
%                     must be exactly those alongside files. Any other
%                     layout blocks verification.
%     'McrRoot'       MCR_ROOT under test (default: pinned
%                     /usr/pubsw/common/matlab/26.1; substitutes block).
%     'RepoRoot'      Git repository used for tag/tree resolution
%                     (default: this repository root).
%
%   Checks (each fail-closed; the 10 publication requirements):
%     1. commit==tag: manifest source/release commit equals the resolved
%        tag commit (and ReleaseCommit when given).
%     2. artifacts-from-source: the release-tree fingerprint is ALWAYS
%        recomputed from the repository and must match the manifest; a
%        recompute failure propagates (never a recorded-only accept-note).
%        Only 'release-candidate' builds publish (ordinary local
%        manifests block as stale fallback).
%     3. compiler+MCR compat: R2026a/26.1/glnxa64/26.1 identities plus
%        disk-validated pinned MCR (VersionInfo.xml via the existing
%        mlsc_current_validate contract) and required toolboxes.
%     4. required files: payload_build (dist), compiled CTF/executable,
%        build manifest, resource manifest present and non-empty.
%     5. SHA match: every recorded SHA-256 recomputed from disk.
%     6. package==build: staged set equals the manifest inventory
%        exactly (extras block as stale dist).
%     7. runtime paths pinned: MCR_ROOT is the pinned tree; the staged
%        runner path equals the manifest (prepublication only).
%     8. Gate-A binding: the record binds this exact candidate under
%        the FULL mlsc_current_validate execution bar (all required
%        fields; pinned runtime identity disk-validated; recomputed
%        runner/executable/manifest/native SHA-256 with missing files
%        rejected, never skipped; every gate pass; no foreign records).
%     9. no stale/fallback: no extra files, no non-SHA identity, no
%        local-mode manifests.
%    10. missing=>block: every absent input or evidence blocks.
%
%   Deployment-copy provenance (postinstall): the deployment copy must
%   use the exact pinned runtime layout (launcher at the DeployRoot,
%   manifests alongside; staged payload_build nesting is rejected as a
%   mismatched layout), and each packaged inventory file must exist at
%   its mapped runtime path ('payload_build/<name>' deploys flat to
%   '<name>') with a matching SHA-256 (deploy-vs-package diff blocks).
%   Files outside the packaged inventory are NOT verified and no
%   whole-directory deployed-byte identity is claimed. Extras at
%   DeployRoot are reported, never treated as proof.
%
%   Confinement: MLSC CURRENT only. LEGACY, local, and Launchpad
%   behavior are unchanged. No SSH/Slurm, no science, no mcc, no
%   publish/deploy side effects; only reads files and git metadata.
%
%   Minimum supported MATLAB: R2010b (era-safe idioms where trivial;
%   release tooling runs under modern MATLAB).

if nargin < 1 || ~ischar(action) || size(action, 1) ~= 1
    error('pseudo_CT:MLSCReleaseGate', 'A validation action (prepublication|postinstall) is required.');
end
action = lower(strtrim(action));
is_pre = strcmp(action, 'prepublication');
is_post = strcmp(action, 'postinstall');
if ~is_pre && ~is_post
    error('pseudo_CT:MLSCReleaseGate', 'Unknown validation action: %s (want prepublication|postinstall).', action);
end

repo_guess = fileparts(fileparts(mfilename('fullpath')));
if exist('mlsc_current_validate', 'file') ~= 2
    addpath(fullfile(repo_guess, 'src', 'mlsc'));
end
if exist('mlsc_release_gate', 'file') ~= 2
    addpath(fullfile(repo_guess, 'src', 'mlsc'));
end
if exist('mlsc_current_validate', 'file') ~= 2 || exist('mlsc_release_gate', 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', 'MLSC current contract helpers are unavailable; missing tooling blocks publication.');
end

package_dir = '';
build_manifest = '';
resource_manifest = '';
release_tag = '';
release_commit = '';
expected_fp = '';
gate_a_record = '';
deploy_root = '';
mcr_root = mlsc_current_validate('pinned_mcr_root');
repo_root = repo_guess;
ii = 1;
while ii <= numel(varargin)
    if ~ischar(varargin{ii}) || size(varargin{ii}, 1) ~= 1
        error('pseudo_CT:MLSCReleaseGate', 'Validator arguments must be name-value character rows.');
    end
    name_here = lower(strtrim(varargin{ii}));
    if ii + 1 > numel(varargin)
        error('pseudo_CT:MLSCReleaseGate', 'Missing value for validator argument %s.', name_here);
    end
    val_here = varargin{ii + 1};
    if ~ischar(val_here) || size(val_here, 1) ~= 1
        error('pseudo_CT:MLSCReleaseGate', 'Validator argument %s value must be a character row.', name_here);
    end
    switch name_here
        case 'packagedir'
            package_dir = strtrim(val_here);
        case 'buildmanifest'
            build_manifest = strtrim(val_here);
        case 'resourcemanifest'
            resource_manifest = strtrim(val_here);
        case 'releasetag'
            release_tag = strtrim(val_here);
        case 'releasecommit'
            release_commit = strtrim(val_here);
        case 'expectedfingerprint'
            expected_fp = strtrim(val_here);
        case 'gatearecord'
            gate_a_record = strtrim(val_here);
        case 'deployroot'
            deploy_root = strtrim(val_here);
        case 'mcrroot'
            mcr_root = strtrim(val_here);
        case 'reporoot'
            repo_root = strtrim(val_here);
        otherwise
            error('pseudo_CT:MLSCReleaseGate', 'Unknown validator argument %s.', name_here);
    end
    ii = ii + 2;
end

if is_pre && ~isempty(deploy_root)
    error('pseudo_CT:MLSCReleaseGate', 'DeployRoot is a postinstall input; prepublication verifies the staged package only.');
end
if is_post && ~isempty(package_dir)
    error('pseudo_CT:MLSCReleaseGate', 'PackageDir is a prepublication input; postinstall verifies the deployment copy only.');
end
if is_pre
    if isempty(package_dir)
        error('pseudo_CT:MLSCReleaseGate', 'PackageDir is required for prepublication; missing package blocks publication.');
    end
    if exist(package_dir, 'dir') ~= 7
        error('pseudo_CT:MLSCReleaseGate', 'Staged package directory is missing: %s.', package_dir);
    end
    if isempty(build_manifest)
        build_manifest = fullfile(package_dir, 'mlsc_current_build.mat');
    end
    if isempty(resource_manifest)
        resource_manifest = fullfile(package_dir, 'mlsc_current_resources.mat');
    end
end
if is_post
    if isempty(deploy_root)
        error('pseudo_CT:MLSCReleaseGate', 'DeployRoot is required for postinstall; missing deployment path blocks verification.');
    end
    if isempty(build_manifest) || isempty(resource_manifest)
        error('pseudo_CT:MLSCReleaseGate', 'BuildManifest and ResourceManifest are required for postinstall; missing manifests block verification.');
    end
    if exist(deploy_root, 'dir') ~= 7
        error('pseudo_CT:MLSCReleaseGate', 'Deployment root is missing: %s.', deploy_root);
    end
end
if isempty(gate_a_record)
    error('pseudo_CT:MLSCReleaseGate', 'GateARecord is required; a candidate without Gate-A binding blocks publication.');
end
if isempty(release_tag) && isempty(release_commit)
    error('pseudo_CT:MLSCReleaseGate', 'ReleaseTag or ReleaseCommit is required; missing release identity blocks publication.');
end

build = local_load_manifest(build_manifest, 'build', 'pseudo-CT.mlsc-current-build/v1');
resources = local_load_manifest(resource_manifest, 'resources', 'pseudo-CT.mlsc-current-resources/v1');

% 1-2. Release source binding (commit==tag, artifacts-from-source).
eff_commit = mlsc_release_gate('resolve_commit', repo_root, release_tag, release_commit);
if ~isfield(build, 'source_commit') || ~ischar(build.source_commit) || ...
        ~strcmpi(strtrim(build.source_commit), eff_commit)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest source_commit does not match the release commit %s; wrong commit blocks publication.', eff_commit);
end
if ~isfield(build, 'release_commit') || ~ischar(build.release_commit) || ...
        ~strcmpi(strtrim(build.release_commit), eff_commit)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest release_commit does not match the release commit %s; manifest inconsistency blocks publication.', eff_commit);
end
if ~isempty(release_tag)
    if ~isfield(build, 'release_tag') || ~ischar(build.release_tag) || ...
            ~strcmp(strtrim(build.release_tag), release_tag)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest was not built for release tag %s; manifest inconsistency blocks publication.', release_tag);
    end
end
tree_recomputed = mlsc_release_gate('release_tree', repo_root, eff_commit);
if ~isfield(build, 'release_tree') || ~ischar(build.release_tree) || ...
        ~strcmpi(strtrim(build.release_tree), tree_recomputed)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest release_tree does not match the recomputed release-tree fingerprint; wrong source blocks publication.');
end
if ~isfield(build, 'build_mode') || ~ischar(build.build_mode) || ...
        ~strcmp(strtrim(build.build_mode), 'release-candidate')
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest is not a release-candidate build; ordinary local or stale manifests cannot publish.');
end
if ~isempty(expected_fp)
    if ~isfield(build, 'source_provenance_fingerprint') || ...
            ~ischar(build.source_provenance_fingerprint) || ...
            ~strcmpi(strtrim(build.source_provenance_fingerprint), strtrim(expected_fp))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest source fingerprint does not match the expected fingerprint; wrong hash blocks publication.');
    end
end
if ~isfield(build, 'required_outputs') || ~iscell(build.required_outputs)
    error('pseudo_CT:MLSCReleaseGate', 'Build manifest required outputs are invalid; manifest inconsistency blocks publication.');
end
local_require_outputs(build.required_outputs);

% 3. Compiler + MCR compatibility (existing contract is authoritative).
local_require_build_field(build, 'compiler_identity');
if ~strcmp(strtrim(build.compiler_identity), 'MATLAB Compiler 26.1 (R2026a)')
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build compiler identity is incompatible; compiler mismatch blocks publication.');
end
local_require_build_field(build, 'mcr_root');
pinned = mlsc_current_validate('pinned_mcr_root');
if ~strcmp(local_strip_sep(strtrim(build.mcr_root)), pinned)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest MCR_ROOT does not match the pinned %s; runtime path mismatch blocks publication.', pinned);
end
if ~strcmp(local_strip_sep(strtrim(mcr_root)), pinned)
    error('pseudo_CT:MLSCReleaseGate', ...
        'MCR_ROOT under test must be the pinned %s; substitutes block publication.', pinned);
end
mlsc_current_validate('structure', strtrim(mcr_root));
actual = mlsc_current_validate('actual_identity', strtrim(mcr_root));
local_require_build_field(build, 'release');
if ~strcmp(strtrim(build.release), actual.release)
    error('pseudo_CT:MLSCReleaseGate', 'Build release is incompatible with the pinned runtime; mismatch blocks publication.');
end
local_require_build_field(build, 'update_minimum');
if ~isnumeric(build.update_minimum) || ~isscalar(build.update_minimum) || ...
        actual.update < build.update_minimum
    error('pseudo_CT:MLSCReleaseGate', 'Pinned runtime update does not satisfy the build minimum; mismatch blocks publication.');
end
local_require_build_field(build, 'mcr_version');
if ~isnumeric(build.mcr_version) || numel(build.mcr_version) ~= 2 || ...
        build.mcr_version(1) ~= actual.mcr_version(1) || ...
        build.mcr_version(2) ~= actual.mcr_version(2)
    error('pseudo_CT:MLSCReleaseGate', 'Build numeric runtime version is incompatible; mismatch blocks publication.');
end
local_require_build_field(build, 'arch');
if ~strcmp(strtrim(build.arch), actual.arch)
    error('pseudo_CT:MLSCReleaseGate', 'Build architecture is incompatible; mismatch blocks publication.');
end
local_require_build_field(build, 'generation');
if ~strcmp(strtrim(build.generation), actual.generation)
    error('pseudo_CT:MLSCReleaseGate', 'Build generation is incompatible; mismatch blocks publication.');
end
if ~isfield(build, 'required_toolboxes') || ~iscell(build.required_toolboxes)
    error('pseudo_CT:MLSCReleaseGate', 'Build manifest required toolboxes are missing; manifest inconsistency blocks publication.');
end
wanted_toolboxes = {'Compiler'; 'Image_Toolbox'; 'Statistics_Toolbox'};
for kk = 1:numel(wanted_toolboxes)
    found = false;
    for jj = 1:numel(build.required_toolboxes)
        entry = build.required_toolboxes{jj};
        if ischar(entry) && strcmp(strtrim(entry), wanted_toolboxes{kk})
            found = true;
            break;
        end
    end
    if ~found
        error('pseudo_CT:MLSCReleaseGate', 'Build manifest is missing required toolbox Compiler/Image/Statistics; mismatch blocks publication.');
    end
end

% Resource contract (existence/schema/pending marker; science stays in payload).
if ~isfield(resources, 'native_platform') || ~ischar(resources.native_platform) || ...
        ~strcmp(strtrim(resources.native_platform), 'glnxa64')
    error('pseudo_CT:MLSCReleaseGate', 'Resource manifest platform is incompatible; mismatch blocks publication.');
end
if ~isfield(resources, 'native_arch') || ~ischar(resources.native_arch) || ...
        ~strcmp(strtrim(resources.native_arch), 'glnxa64')
    error('pseudo_CT:MLSCReleaseGate', 'Resource manifest architecture is incompatible; mismatch blocks publication.');
end
if ~isfield(resources, 'native_validation') || ~ischar(resources.native_validation) || ...
        ~strcmp(strtrim(resources.native_validation), ...
        't007-gate-a-pending: existence-only; production loadability evidence comes later')
    error('pseudo_CT:MLSCReleaseGate', 'Resource manifest native validation is unknown; evidence mismatch blocks publication.');
end

% 4-6. Required files, SHA match, package==build.
if is_pre
    local_check_package(package_dir, build);
else
    local_check_deploy(deploy_root, build, build_manifest, resource_manifest);
end

% 8. Gate-A binding (binds, never rewrites).
local_check_gate_a(gate_a_record, build_manifest, resource_manifest, build, resources, is_pre);

if is_pre
    fprintf('PREPUBLICATION PASS: staged package matches release %s (%s).\n', local_release_label(release_tag, eff_commit), eff_commit);
else
    fprintf('POSTINSTALL PASS: deployment copy at %s matches release %s (%s).\n', ...
        deploy_root, local_release_label(release_tag, eff_commit), eff_commit);
end
ok = true;
end

function local_require_build_field(build, field_name)
if ~isfield(build, field_name)
    error('pseudo_CT:MLSCReleaseGate', 'Build manifest is missing field %s; manifest inconsistency blocks publication.', field_name);
end
end

function local_require_outputs(outputs)
expected = {'att_map.nii'; 'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
for ii = 1:numel(expected)
    found = false;
    for jj = 1:numel(outputs)
        if ischar(outputs{jj}) && strcmp(strtrim(outputs{jj}), expected{ii})
            found = true;
            break;
        end
    end
    if ~found
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest is missing required output %s; manifest inconsistency blocks publication.', expected{ii});
    end
end
end

function value = local_load_manifest(manifest_path, variable_name, expected_schema)
if ~ischar(manifest_path) || isempty(strtrim(manifest_path)) || ...
        exist(strtrim(manifest_path), 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', 'Manifest file is missing: %s; missing evidence blocks publication.', manifest_path);
end
loaded = load(strtrim(manifest_path));
if ~isfield(loaded, variable_name)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Manifest %s is missing variable %s; manifest inconsistency blocks publication.', manifest_path, variable_name);
end
value = loaded.(variable_name);
if ~isstruct(value) || numel(value) ~= 1
    error('pseudo_CT:MLSCReleaseGate', ...
        'Manifest %s variable %s must be one scalar struct; manifest inconsistency blocks publication.', ...
        manifest_path, variable_name);
end
if ~isfield(value, 'schema') || ~ischar(value.schema) || ~strcmp(value.schema, expected_schema)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Manifest %s has an unexpected schema; manifest inconsistency blocks publication.', manifest_path);
end
if ~isfield(value, 'manifest_version') || ~isnumeric(value.manifest_version) || ...
        ~isscalar(value.manifest_version) || value.manifest_version ~= 1
    error('pseudo_CT:MLSCReleaseGate', ...
        'Manifest %s has an unsupported version; manifest inconsistency blocks publication.', manifest_path);
end
end

function local_check_package(root_dir, build)
runner_rel = 'payload_build/run_mlsc_current_payload.sh';
exe_rel = 'payload_build/mlsc_current_payload';
build_rel = 'mlsc_current_build.mat';
resources_rel = 'mlsc_current_resources.mat';
if exist(fullfile(root_dir, 'payload_build'), 'dir') ~= 7
    error('pseudo_CT:MLSCReleaseGate', ...
        'Staged distribution directory payload_build is missing under %s; missing dist blocks publication.', root_dir);
end
runner_path = fullfile(root_dir, strrep(runner_rel, '/', filesep));
exe_path = fullfile(root_dir, strrep(exe_rel, '/', filesep));
local_require_nonempty_file(runner_path, 'launcher payload_build/run_mlsc_current_payload.sh');
local_require_nonempty_file(exe_path, 'compiled CTF/executable payload_build/mlsc_current_payload');
local_require_nonempty_file(fullfile(root_dir, build_rel), 'build manifest mlsc_current_build.mat');
local_require_nonempty_file(fullfile(root_dir, resources_rel), 'resource manifest mlsc_current_resources.mat');
if ~isfield(build, 'runner') || ~ischar(build.runner) || isempty(strtrim(build.runner))
    error('pseudo_CT:MLSCReleaseGate', 'Build manifest runner is invalid; manifest inconsistency blocks publication.');
end
want_runner = fullfile(root_dir, strrep(runner_rel, '/', filesep));
if ~strcmp(local_strip_sep(strtrim(build.runner)), local_strip_sep(want_runner))
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest runner path does not match the staged package; runtime path mismatch blocks publication.');
end
hash_fields = {'runner_checksum', runner_path, 'runner'; ...
    'executable_fingerprint', exe_path, 'compiled CTF/executable'};
for kk = 1:size(hash_fields, 1)
    field_here = hash_fields{kk, 1};
    path_here = hash_fields{kk, 2};
    label_here = hash_fields{kk, 3};
    if ~isfield(build, field_here) || ~ischar(build.(field_here)) || ...
            ~mlsc_release_gate('is_valid_sha256', build.(field_here))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest %s must be SHA-256; manifest inconsistency blocks publication.', field_here);
    end
    actual_hex = mlsc_release_gate('sha256_file', path_here);
    if ~strcmpi(strtrim(build.(field_here)), actual_hex)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Staged %s hash does not match the manifest; package-vs-build diff blocks publication.', label_here);
    end
end
if ~isfield(build, 'resource_fingerprint') || ~ischar(build.resource_fingerprint) || ...
        ~mlsc_release_gate('is_valid_sha256', build.resource_fingerprint)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest resource_fingerprint must be SHA-256; manifest inconsistency blocks publication.');
end
resource_actual = mlsc_release_gate('sha256_file', fullfile(root_dir, resources_rel));
if ~strcmpi(strtrim(build.resource_fingerprint), resource_actual)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Staged resource manifest hash does not match the build manifest; wrong hash blocks publication.');
end
inventory_fields = {'packaged_files'; 'packaged_checksums'; 'packaged_files_fingerprint'};
for kk = 1:numel(inventory_fields)
    if ~isfield(build, inventory_fields{kk})
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest is missing the packaged-files inventory (%s); manifest inconsistency blocks publication.', ...
            inventory_fields{kk});
    end
end
if ~iscell(build.packaged_files) || ~iscell(build.packaged_checksums) || ...
        numel(build.packaged_files) ~= numel(build.packaged_checksums) || isempty(build.packaged_files)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest packaged-files inventory is inconsistent; manifest inconsistency blocks publication.');
end
if ~ischar(build.packaged_files_fingerprint) || ...
        ~mlsc_release_gate('is_valid_sha256', build.packaged_files_fingerprint)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest packaged-files fingerprint must be SHA-256; manifest inconsistency blocks publication.');
end
% Per-file: every inventoried file present with matching hash.
for kk = 1:numel(build.packaged_files)
    rel_here = build.packaged_files{kk};
    if ~ischar(rel_here) || isempty(strtrim(rel_here)) || ~isempty(strfind(rel_here, '..'))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest packaged inventory carries an unsafe path; manifest inconsistency blocks publication.');
    end
    disk_here = fullfile(root_dir, strrep(strtrim(rel_here), '/', filesep));
    if exist(disk_here, 'file') ~= 2
        error('pseudo_CT:MLSCReleaseGate', ...
            'Packaged file %s is missing from the staged package; package-vs-build diff blocks publication.', ...
            strtrim(rel_here));
    end
    recorded_sha = local_inventory_sha(build.packaged_checksums{kk});
    if isempty(recorded_sha)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest inventory entry for %s is malformed; manifest inconsistency blocks publication.', ...
            strtrim(rel_here));
    end
    actual_hex = mlsc_release_gate('sha256_file', disk_here);
    if ~strcmpi(recorded_sha, actual_hex)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Packaged file %s differs from the build manifest; package-vs-build diff blocks publication.', ...
            strtrim(rel_here));
    end
end
% Set equality: no extras beyond the inventory (stale dist blocks).
[disk_files, ~, disk_fp] = mlsc_release_gate('inventory_dir', root_dir, ...
    {'mlsc_current_build.mat', 'mlsc_current_build.txt'});
for kk = 1:numel(disk_files)
    covered = false;
    for jj = 1:numel(build.packaged_files)
        if ischar(build.packaged_files{jj}) && strcmp(strtrim(build.packaged_files{jj}), disk_files{kk})
            covered = true;
            break;
        end
    end
    if ~covered
        error('pseudo_CT:MLSCReleaseGate', ...
            'Stale extra file %s is staged beyond the packaged inventory; stale dist blocks publication.', ...
            disk_files{kk});
    end
end
if ~strcmpi(strtrim(build.packaged_files_fingerprint), disk_fp)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Recomputed packaged-files fingerprint differs from the manifest; package-vs-build diff blocks publication.');
end
end

function local_check_deploy(deploy_root, build, build_manifest_arg, resource_manifest_arg)
%LOCAL_CHECK_DEPLOY Verify the deployment copy at its exact runtime path.
%   The production layout is pinned by the mlsc-current profile: the
%   launcher sits directly at <DeployRoot>/run_mlsc_current_payload.sh
%   (never nested under payload_build/), the compiled executable sits
%   beside it, and the build/resource manifests sit alongside. The
%   BuildManifest/ResourceManifest arguments must be exactly those
%   alongside files; any other layout (nested payload_build staging
%   copied verbatim, manifests from elsewhere) is a mismatched layout
%   and blocks verification. Every packaged inventory file is verified
%   at its mapped runtime path ('payload_build/<name>' deploys flat to
%   '<name>'); a deploy-vs-package diff blocks. Files outside the
%   packaged inventory are reported, never treated as proof.
launcher_name = 'run_mlsc_current_payload.sh';
exe_name = 'mlsc_current_payload';
build_name = 'mlsc_current_build.mat';
resources_name = 'mlsc_current_resources.mat';
launcher_path = fullfile(deploy_root, launcher_name);
exe_path = fullfile(deploy_root, exe_name);
want_build = fullfile(deploy_root, build_name);
want_resources = fullfile(deploy_root, resources_name);
if ~strcmp(local_strip_sep(strtrim(build_manifest_arg)), local_strip_sep(want_build))
    error('pseudo_CT:MLSCReleaseGate', ...
        'BuildManifest must be the alongside %s at the deployment root; mismatched runtime layout blocks verification.', build_name);
end
if ~strcmp(local_strip_sep(strtrim(resource_manifest_arg)), local_strip_sep(want_resources))
    error('pseudo_CT:MLSCReleaseGate', ...
        'ResourceManifest must be the alongside %s at the deployment root; mismatched runtime layout blocks verification.', resources_name);
end
if exist(fullfile(deploy_root, 'payload_build'), 'dir') == 7
    error('pseudo_CT:MLSCReleaseGate', ...
        'Deployment root carries a nested payload_build staging tree; the exact runtime layout keeps the launcher at the root; mismatched runtime layout blocks verification.');
end
local_require_nonempty_file(launcher_path, 'deployed launcher run_mlsc_current_payload.sh');
local_require_nonempty_file(exe_path, 'deployed compiled executable mlsc_current_payload');
local_require_nonempty_file(want_build, 'deployed build manifest mlsc_current_build.mat');
local_require_nonempty_file(want_resources, 'deployed resource manifest mlsc_current_resources.mat');
if ~isfield(build, 'runner_checksum') || ~ischar(build.runner_checksum) || ...
        ~mlsc_release_gate('is_valid_sha256', build.runner_checksum)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest runner_checksum must be SHA-256; manifest inconsistency blocks verification.');
end
if ~strcmpi(strtrim(build.runner_checksum), mlsc_release_gate('sha256_file', launcher_path))
    error('pseudo_CT:MLSCReleaseGate', ...
        'Deployed launcher hash does not match the packaged inventory; deploy-vs-package diff blocks verification.');
end
if ~isfield(build, 'executable_fingerprint') || ~ischar(build.executable_fingerprint) || ...
        ~mlsc_release_gate('is_valid_sha256', build.executable_fingerprint)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest executable_fingerprint must be SHA-256; manifest inconsistency blocks verification.');
end
if ~strcmpi(strtrim(build.executable_fingerprint), mlsc_release_gate('sha256_file', exe_path))
    error('pseudo_CT:MLSCReleaseGate', ...
        'Deployed compiled executable hash does not match the packaged inventory; deploy-vs-package diff blocks verification.');
end
if ~isfield(build, 'resource_fingerprint') || ~ischar(build.resource_fingerprint) || ...
        ~mlsc_release_gate('is_valid_sha256', build.resource_fingerprint)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest resource_fingerprint must be SHA-256; manifest inconsistency blocks verification.');
end
if ~strcmpi(strtrim(build.resource_fingerprint), mlsc_release_gate('sha256_file', want_resources))
    error('pseudo_CT:MLSCReleaseGate', ...
        'Deployed resource manifest hash does not match the packaged inventory; deploy-vs-package diff blocks verification.');
end
inventory_fields = {'packaged_files'; 'packaged_checksums'; 'packaged_files_fingerprint'};
for kk = 1:numel(inventory_fields)
    if ~isfield(build, inventory_fields{kk})
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest is missing the packaged-files inventory (%s); manifest inconsistency blocks verification.', ...
            inventory_fields{kk});
    end
end
if ~iscell(build.packaged_files) || ~iscell(build.packaged_checksums) || ...
        numel(build.packaged_files) ~= numel(build.packaged_checksums) || isempty(build.packaged_files)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest packaged-files inventory is inconsistent; manifest inconsistency blocks verification.');
end
if ~ischar(build.packaged_files_fingerprint) || ...
        ~mlsc_release_gate('is_valid_sha256', build.packaged_files_fingerprint)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Build manifest packaged-files fingerprint must be SHA-256; manifest inconsistency blocks verification.');
end
for kk = 1:numel(build.packaged_files)
    rel_here = build.packaged_files{kk};
    if ~ischar(rel_here) || isempty(strtrim(rel_here)) || ~isempty(strfind(rel_here, '..'))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest packaged inventory carries an unsafe path; manifest inconsistency blocks verification.');
    end
    deploy_rel = local_deploy_rel(strtrim(rel_here));
    disk_here = fullfile(deploy_root, strrep(deploy_rel, '/', filesep));
    if exist(disk_here, 'file') ~= 2
        error('pseudo_CT:MLSCReleaseGate', ...
            'Packaged file %s is missing from the deployment copy (want %s); deploy-vs-package diff blocks verification.', ...
            strtrim(rel_here), deploy_rel);
    end
    recorded_sha = local_inventory_sha(build.packaged_checksums{kk});
    if isempty(recorded_sha)
        error('pseudo_CT:MLSCReleaseGate', ...
            'Build manifest inventory entry for %s is malformed; manifest inconsistency blocks verification.', ...
            strtrim(rel_here));
    end
    if ~strcmpi(recorded_sha, mlsc_release_gate('sha256_file', disk_here))
        error('pseudo_CT:MLSCReleaseGate', ...
            'Deployed file %s differs from the packaged inventory; deploy-vs-package diff blocks verification.', ...
            deploy_rel);
    end
end
fprintf('GATE-NOTE deployment extras outside the packaged inventory are reported, never proof.\n');
end

function mapped = local_deploy_rel(rel_here)
%LOCAL_DEPLOY_REL Map a staged inventory relpath to the runtime layout.
%   Staged 'payload_build/<name>' deploys flat to '<name>' at the
%   deployment root (launcher at root per the pinned profile); every
%   other relpath keeps its relative position.
mapped = rel_here;
prefix = 'payload_build/';
if strncmp(rel_here, prefix, length(prefix))
    mapped = rel_here(length(prefix) + 1:end);
end
end

function local_require_nonempty_file(path_here, label)
if exist(path_here, 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', '%s is missing; missing evidence blocks publication.', label);
end
info = dir(path_here);
if isempty(info) || info(1).isdir || info(1).bytes <= 0
    error('pseudo_CT:MLSCReleaseGate', '%s is empty; missing evidence blocks publication.', label);
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

function local_check_gate_a(record_path, build_manifest, resource_manifest, build, resources, bind_paths)
% bind_paths true verifies the record was minted for these exact manifest
% paths (prepublication staged layout); false verifies content binding
% only, for byte-copies at a deployment root (postinstall).
%   The Gate-A bar is the FULL mlsc_current_validate execution gate, no
%   subset: schema/version, every required record field (source, pinned
%   runtime identity, runner, executable, manifests, natives, run
%   evidence), provenance binding, disk-validated runtime binding,
%   recomputed file bindings (runner/exe/manifests/natives, SHA-256
%   mandatory, missing files rejected, never skipped), and all gates
%   pass. Incomplete records and foreign records block publication.
if exist(strtrim(record_path), 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record is missing: %s; missing Gate-A binding blocks publication.', record_path);
end
loaded = load(strtrim(record_path));
if ~isfield(loaded, 'gate_a')
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record is missing variable gate_a; binding failure blocks publication.');
end
record = loaded.gate_a;
if ~isstruct(record) || numel(record) ~= 1
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record variable gate_a must be one scalar struct; binding failure blocks publication.');
end
if ~isfield(record, 'schema') || ~ischar(record.schema) || ...
        ~strcmp(record.schema, 'pseudo-CT.mlsc-current-gate-a/v1')
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record has an unexpected schema; binding failure blocks publication.');
end
if ~isfield(record, 'manifest_version') || ~isnumeric(record.manifest_version) || ...
        ~isscalar(record.manifest_version) || record.manifest_version ~= 1
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record has an unsupported version; binding failure blocks publication.');
end
required_gate_a = {'source_commit'; 'source_provenance_fingerprint'; ...
    'mcr_root'; 'release'; 'version'; 'update_minimum'; ...
    'update_actual'; 'mcr_version'; 'arch'; 'generation'; ...
    'runner'; 'runner_checksum'; 'build_exe'; 'build_exe_checksum'; ...
    'build_manifest'; 'build_manifest_checksum'; ...
    'resource_manifest'; 'resource_manifest_checksum'; ...
    'native_names'; 'native_paths'; 'native_checksums'; ...
    'native_results'; 'launcher_result'; 'runtime_lib_result'; ...
    'prepare_result'; 'compute_result'; 'overall_result'};
for kk = 1:numel(required_gate_a)
    if ~isfield(record, required_gate_a{kk})
        error('pseudo_CT:MLSCReleaseGate', ...
            'Gate-A record is missing field %s; incomplete Gate-A evidence blocks publication.', ...
            required_gate_a{kk});
    end
end
if ~isfield(record, 'source_commit') || ~ischar(record.source_commit) || ...
        ~strcmpi(strtrim(record.source_commit), strtrim(build.source_commit))
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record source commit does not match the build manifest; binding failure blocks publication.');
end
if ~isfield(record, 'source_provenance_fingerprint') || ...
        ~ischar(record.source_provenance_fingerprint) || ...
        ~mlsc_release_gate('is_valid_sha256', record.source_provenance_fingerprint) || ...
        ~strcmpi(strtrim(record.source_provenance_fingerprint), strtrim(build.source_provenance_fingerprint))
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record provenance does not match the build manifest; binding failure blocks publication.');
end
% Runtime binding: pinned root with disk-validated actual identity (the
% same actual_identity contract section 3 uses; constants never prove it).
pinned = mlsc_current_validate('pinned_mcr_root');
if ~ischar(record.mcr_root) || ...
        ~strcmp(local_strip_sep(strtrim(record.mcr_root)), pinned)
    error('pseudo_CT:MLSCReleaseGate', ...
        'Gate-A record MCR_ROOT does not match the pinned %s; binding failure blocks publication.', pinned);
end
actual = mlsc_current_validate('actual_identity', pinned);
if ~ischar(record.release) || ~strcmp(strtrim(record.release), actual.release)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record release is incompatible; binding failure blocks publication.');
end
if ~ischar(record.version) || ~strcmp(strtrim(record.version), actual.version)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record runtime version is incompatible; binding failure blocks publication.');
end
if ~isnumeric(record.update_minimum) || ~isscalar(record.update_minimum) || ...
        record.update_minimum ~= build.update_minimum
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record update minimum does not match the build manifest; binding failure blocks publication.');
end
if ~isnumeric(record.update_actual) || ~isscalar(record.update_actual) || ...
        record.update_actual ~= actual.update
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record runtime update does not match the pinned runtime; binding failure blocks publication.');
end
if ~isnumeric(record.mcr_version) || numel(record.mcr_version) ~= 2 || ...
        record.mcr_version(1) ~= actual.mcr_version(1) || ...
        record.mcr_version(2) ~= actual.mcr_version(2)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record numeric runtime version is incompatible; binding failure blocks publication.');
end
if ~ischar(record.arch) || ~strcmp(strtrim(record.arch), actual.arch)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record architecture is incompatible; binding failure blocks publication.');
end
if ~ischar(record.generation) || ~strcmp(strtrim(record.generation), actual.generation)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record generation is incompatible; binding failure blocks publication.');
end
if ~isfield(record, 'runner') || ~ischar(record.runner) || ...
        ~strcmp(local_strip_sep(strtrim(record.runner)), local_strip_sep(strtrim(build.runner)))
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record runner does not match the build manifest; binding failure blocks publication.');
end
if ~isfield(record, 'runner_checksum') || ~ischar(record.runner_checksum) || ...
        ~strcmpi(strtrim(record.runner_checksum), strtrim(build.runner_checksum))
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record runner checksum does not match the build manifest; binding failure blocks publication.');
end
% (Runner identity against disk is proven in section 5, where the staged
% or deployed runner hash must equal build.runner_checksum; equality here
% transitively binds the record to that exact file.)
if ~isfield(record, 'build_exe') || ~ischar(record.build_exe) || ...
        isempty(strtrim(record.build_exe))
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record executable path is invalid; binding failure blocks publication.');
end
if ~isfield(record, 'build_exe_checksum') || ~ischar(record.build_exe_checksum) || ...
        ~mlsc_release_gate('is_valid_sha256', record.build_exe_checksum)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record executable checksum must be SHA-256; binding failure blocks publication.');
end
if ~strcmpi(strtrim(record.build_exe_checksum), strtrim(build.executable_fingerprint))
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record executable identity does not match the build manifest; binding failure blocks publication.');
end
if exist(strtrim(record.build_exe), 'file') ~= 2
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record executable file is missing: %s; missing executable evidence blocks publication.', strtrim(record.build_exe));
end
exe_actual = mlsc_release_gate('sha256_file', strtrim(record.build_exe));
if ~strcmpi(strtrim(record.build_exe_checksum), exe_actual)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record executable identity does not match the file; binding failure blocks publication.');
end
if ~isfield(record, 'build_manifest') || ~ischar(record.build_manifest) || ...
        (bind_paths && ~strcmp(local_strip_sep(strtrim(record.build_manifest)), local_strip_sep(build_manifest)))
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record was minted for another build manifest; foreign record blocks publication.');
end
if ~isfield(record, 'build_manifest_checksum') || ...
        ~ischar(record.build_manifest_checksum) || ...
        ~mlsc_release_gate('is_valid_sha256', record.build_manifest_checksum)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record build manifest checksum must be SHA-256; binding failure blocks publication.');
end
build_actual = mlsc_release_gate('sha256_file', build_manifest);
if ~strcmpi(strtrim(record.build_manifest_checksum), build_actual)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record build manifest identity does not match the file; binding failure blocks publication.');
end
if ~isfield(record, 'resource_manifest') || ~ischar(record.resource_manifest) || ...
        (bind_paths && ~strcmp(local_strip_sep(strtrim(record.resource_manifest)), local_strip_sep(resource_manifest)))
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record was minted for another resource manifest; foreign record blocks publication.');
end
if ~isfield(record, 'resource_manifest_checksum') || ...
        ~ischar(record.resource_manifest_checksum) || ...
        ~mlsc_release_gate('is_valid_sha256', record.resource_manifest_checksum)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record resource manifest checksum must be SHA-256; binding failure blocks publication.');
end
resource_actual = mlsc_release_gate('sha256_file', resource_manifest);
if ~strcmpi(strtrim(record.resource_manifest_checksum), resource_actual)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record resource identity does not match the file; binding failure blocks publication.');
end
if ~isfield(record, 'native_names') || ~iscell(record.native_names) || isempty(record.native_names) || ...
        ~isfield(record, 'native_paths') || ~iscell(record.native_paths) || ...
        ~isfield(record, 'native_checksums') || ~iscell(record.native_checksums) || ...
        ~isfield(record, 'native_results') || ~iscell(record.native_results)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record native evidence is invalid; binding failure blocks publication.');
end
if numel(record.native_names) ~= numel(record.native_paths) || ...
        numel(record.native_names) ~= numel(record.native_checksums) || ...
        numel(record.native_names) ~= numel(record.native_results)
    error('pseudo_CT:MLSCReleaseGate', 'Gate-A record native evidence is inconsistent; binding failure blocks publication.');
end
for kk = 1:numel(record.native_names)
    if ~ischar(record.native_names{kk}) || isempty(strtrim(record.native_names{kk}))
        error('pseudo_CT:MLSCReleaseGate', 'Gate-A record native evidence is invalid; binding failure blocks publication.');
    end
    if ~ischar(record.native_results{kk}) || ~strcmp(strtrim(record.native_results{kk}), 'pass')
        error('pseudo_CT:MLSCReleaseGate', 'Gate-A native evidence did not pass; binding failure blocks publication.');
    end
    if ~ischar(record.native_checksums{kk}) || ...
            ~mlsc_release_gate('is_valid_sha256', record.native_checksums{kk})
        error('pseudo_CT:MLSCReleaseGate', 'Gate-A record native checksum must be SHA-256; binding failure blocks publication.');
    end
    if ~ischar(record.native_paths{kk}) || isempty(strtrim(record.native_paths{kk}))
        error('pseudo_CT:MLSCReleaseGate', 'Gate-A record native path is invalid; binding failure blocks publication.');
    end
    if exist(strtrim(record.native_paths{kk}), 'file') ~= 2
        error('pseudo_CT:MLSCReleaseGate', ...
            'Gate-A native evidence file is missing: %s; missing native evidence blocks publication.', ...
            strtrim(record.native_paths{kk}));
    end
    native_actual = mlsc_release_gate('sha256_file', strtrim(record.native_paths{kk}));
    if ~strcmpi(strtrim(record.native_checksums{kk}), native_actual)
        error('pseudo_CT:MLSCReleaseGate', 'Gate-A native identity does not match the file; binding failure blocks publication.');
    end
end
if isfield(resources, 'native_names') && iscell(resources.native_names) && ...
        ~isempty(resources.native_names)
    for kk = 1:numel(resources.native_names)
        required_name = resources.native_names{kk};
        if ~ischar(required_name) || isempty(strtrim(required_name))
            continue;
        end
        covered = false;
        for jj = 1:numel(record.native_names)
            entry = record.native_names{jj};
            result_entry = record.native_results{jj};
            if ischar(entry) && strcmp(strtrim(entry), strtrim(required_name)) && ...
                    ischar(result_entry) && strcmp(strtrim(result_entry), 'pass')
                covered = true;
                break;
            end
        end
        if ~covered
            error('pseudo_CT:MLSCReleaseGate', ...
                'Gate-A record is missing native %s; binding failure blocks publication.', ...
                strtrim(required_name));
        end
    end
end
evidence_fields = {'launcher_result'; 'runtime_lib_result'; 'prepare_result'; 'compute_result'; 'overall_result'};
for kk = 1:numel(evidence_fields)
    field_here = evidence_fields{kk};
    if ~isfield(record, field_here) || ~ischar(record.(field_here)) || ...
            ~strcmp(strtrim(record.(field_here)), 'pass')
        error('pseudo_CT:MLSCReleaseGate', ...
            'Gate-A %s did not pass; binding failure blocks publication.', field_here);
    end
end
fprintf('GATE-A BINDING OK: record %s binds this candidate.\n', strtrim(record_path));
end

function label = local_release_label(tag, commit)
if ~isempty(tag)
    label = tag;
else
    label = commit;
end
end

function value = local_strip_sep(value)
value = strtrim(value);
while length(value) > 1 && (value(end) == '/' || value(end) == char(92))
    value(end) = '';
end
end
