function varargout = mlsc_current_validate(action, varargin)
%MLSC_CURRENT_VALIDATE Pinned current artifact contract (T004, T014).
%   Implements the T014 pinned MCR_ROOT correction, which is authoritative
%   over the stale T004 catalog/resolver wording. There is no generic
%   catalog, no dynamic discovery, no MCR 7.11 fallback, no workstation
%   inference, no latest/current-label authority, and no submitting-MATLAB
%   substitute. The only accepted MCR_ROOT is the pinned version-specific
%   tree /usr/pubsw/common/matlab/26.1 (never the current symlink). The
%   generated launcher owns the Runtime environment; this file never
%   constructs a global LD_LIBRARY_PATH.
%
%   Actions (R2010b-compatible, deterministic offline, no live SSH/Slurm):
%     PINNED = MLSC_CURRENT_VALIDATE('pinned_mcr_root')
%     FLAG = MLSC_CURRENT_VALIDATE('is_current', CONFIG)
%     MLSC_CURRENT_VALIDATE('validate_contract', CONFIG)
%       Fail-closed pre-submission contract: missing runner/MCR_ROOT/
%       manifests, malformed MCR_ROOT structure, validated actual MCR_ROOT
%       identity from disk (VersionInfo.xml proving R2026a/26.1/glnxa64,
%       never assumed constants), identity/arch/release/
%       generation/update mismatch, missing outputs contract. Allows the
%       T007-pending native marker offline (production loadability comes
%       later); any other native marker is rejected as unknown.
%     MLSC_CURRENT_VALIDATE('validate_for_execution', CONFIG)
%       Same as contract plus production gate: a separately finalized
%       structured Gate-A record (config.current.gate_a_record, schema
%       pseudo-CT.mlsc-current-gate-a/v1, minted by mlsc_finalize_gate_a
%       AFTER a human-authorized Gate-A run) must exist and bind exactly
%       the referenced candidate: schema/generation, recomputed SHA-256
%       of runner/exe/build/resource manifests, source-provenance
%       fingerprint plus base HEAD, pinned MCR_ROOT with disk-validated
%       release/version/update/numeric/arch, every native identity plus
%       per-native pass, launcher/library pass, PREPARE/COMPUTE pass and
%       overall pass. Missing/malformed/unknown-schema records,
%       mismatched bindings, missing or failed natives, and foreign
%       records (minted for another candidate) stay blocked. Pending and
%       no-record stay blocked without a Gate-A run. Never marks pending
%       as validated. Arbitrary native_validation strings (including any
%       legacy validated-marker strings) are rejected; the resource
%       manifest keeps the pending marker because finalization binds but
%       never rewrites manifests or provenance.
%     INFO = MLSC_CURRENT_VALIDATE('gate_a_schema')
%       Returns the exact expected Gate-A record schema string.
%     MLSC_CURRENT_VALIDATE('structure', MCR_ROOT)
%       Malformed-structure guard for one MCR_ROOT path (dir plus
%       runtime/glnxa64). Used by contract and directly by offline fixtures.
%     INFO = MLSC_CURRENT_VALIDATE('expected_actual')
%       Returns the pinned actual identity (release R2026a, update 2,
%       mcr_version [26 1], arch glnxa64, generation 26.1) used for
%       update/release/arch/generation comparison after disk validation.
%       Callers must not treat these constants as proof without the
%       disk-backed actual-identity check in local_validate_build.
%     INFO = MLSC_CURRENT_VALIDATE('actual_identity', MCR_ROOT)
%       Returns the disk-validated actual MCR_ROOT identity (same fields
%       as expected_actual) after proving VersionInfo.xml content.
%       Fails closed when metadata is missing or mismatched.
%
%   Build manifest (.mat, scalar struct BUILD):
%     schema 'pseudo-CT.mlsc-current-build/v1', manifest_version 1,
%     runner (full path as built, must equal config.current.runner),
%     mcr_root (pinned), release (R-prefixed), update_minimum,
%     mcr_version [major minor], arch, generation, runner_checksum
%     (SHA-256), source_commit (base HEAD),
%     source_provenance_fingerprint (SHA-256 over commit plus
%     tracked/untracked lists), required_outputs (canonical 3).
%   Resource manifest (.mat, scalar struct RESOURCES):
%     schema 'pseudo-CT.mlsc-current-resources/v1', manifest_version 1
%     (T003 authority; fingerprints/TPM/QC/natives validated by payload).
%     Contract checks existence/schema/version plus native platform/arch
%     and the exact pending marker; execution additionally requires the
%     separate Gate-A record below. Detailed atlas/fingerprint checks
%     stay in mlsc_current_payload (no duplicated science).
%   Gate-A record (.mat, scalar struct GATE_A, separate from manifests):
%     schema 'pseudo-CT.mlsc-current-gate-a/v1', manifest_version 1,
%     source_commit plus source_provenance_fingerprint, pinned mcr_root,
%     release/version/update_minimum/update_actual/mcr_version/arch/
%     generation, runner plus runner_checksum, build_exe plus
%     build_exe_checksum, build_manifest plus build_manifest_checksum,
%     resource_manifest plus resource_manifest_checksum, native_names/
%     native_paths/native_checksums/native_results, launcher_result,
%     runtime_lib_result, prepare_result, compute_result, overall_result.
%     Minted only by mlsc_finalize_gate_a from the exact Gate-A candidate
%     plus observed Gate-A evidence; fixtures are test-only and unusable
%     as production evidence.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 1 || ~ischar(action) || size(action, 1) ~= 1
    error('pseudo_CT:MLSCCurrentContract', ...
        'A current validation action is required.');
end
action = strtrim(action);
if strcmp(action, 'pinned_mcr_root')
    varargout = {local_pinned_mcr_root()};
    return;
end
if strcmp(action, 'is_current')
    if length(varargin) < 1
        varargout = {false};
        return;
    end
    varargout = {local_is_current(varargin{1})};
    return;
end
if strcmp(action, 'expected_actual')
    varargout = {local_expected_actual()};
    return;
end
if strcmp(action, 'actual_identity')
    if length(varargin) < 1
        error('pseudo_CT:MLSCCurrentMCR', ...
            'An MCR_ROOT path is required for actual identity validation.');
    end
    varargout = {local_actual_runtime_identity(varargin{1})};
    return;
end
if strcmp(action, 'structure')
    if length(varargin) < 1
        error('pseudo_CT:MLSCCurrentMCR', ...
            'An MCR_ROOT path is required for structure validation.');
    end
    local_validate_structure(varargin{1});
    varargout = {true};
    return;
end
if strcmp(action, 'validate_contract')
    if length(varargin) < 1
        error('pseudo_CT:MLSCCurrentContract', ...
            'A current config is required for contract validation.');
    end
    local_validate_contract(varargin{1}, false);
    varargout = {true};
    return;
end
if strcmp(action, 'validate_for_execution')
    if length(varargin) < 1
        error('pseudo_CT:MLSCCurrentContract', ...
            'A current config is required for execution validation.');
    end
    local_validate_contract(varargin{1}, true);
    varargout = {true};
    return;
end
if strcmp(action, 'output_filename_map')
    varargout = {local_output_filename_map()};
    return;
end
if strcmp(action, 'gate_a_schema')
    varargout = {local_gate_a_schema()};
    return;
end
if strcmp(action, 'verify_output_verification')
    if length(varargin) < 1
        error('pseudo_CT:MLSCCurrentContract', ...
            'A verification path is required.');
    end
    varargout = {local_verify_output_verification(varargin{1})};
    return;
end
if strcmp(action, 'verify_copyback_identity')
    if length(varargin) < 2
        error('pseudo_CT:MLSCCurrentContract', ...
            'Shared temp and verification path are required.');
    end
    varargout = {local_verify_copyback_identity(varargin{1}, varargin{2})};
    return;
end
if strcmp(action, 'verify_att_map_semantic')
    if length(varargin) < 2
        error('pseudo_CT:MLSCCurrentContract', ...
            'Att_map path and verification path are required.');
    end
    varargout = {local_verify_att_map_semantic(varargin{1}, varargin{2})};
    return;
end
error('pseudo_CT:MLSCCurrentContract', ...
    'Unknown current validation action: %s.', action);
end

function pinned = local_pinned_mcr_root()
pinned = '/usr/pubsw/common/matlab/26.1';
end

function flag = local_is_current(config)
flag = false;
try
    if ~isstruct(config) || numel(config) ~= 1
        return;
    end
    if ~isfield(config, 'implementation') || ~ischar(config.implementation)
        return;
    end
    if ~strcmp(config.implementation, 'current')
        return;
    end
    if isfield(config, 'mode') && ischar(config.mode)
        flag = strcmp(config.mode, 'mlsc');
    else
        flag = true;
    end
catch %#ok<CTCH>
    flag = false;
end
end

function actual = local_expected_actual()
actual = struct();
actual.release = 'R2026a';
actual.update = 2;
actual.mcr_version = [26 1];
actual.arch = 'glnxa64';
actual.generation = '26.1';
actual.version = '26.1.0.3251617';
end

function actual = local_actual_runtime_identity(mcr_root)
%LOCAL_ACTUAL_RUNTIME_IDENTITY Disk-validated MCR_ROOT identity.
%   Parses ACTUAL installation metadata from VersionInfo.xml beneath
%   MCR_ROOT (authoritative): release (e.g. R2026a), full version/build
%   (e.g. 26.1.0.3251617), update (numeric, e.g. 2), arch/platform
%   (glnxa64). Folder names never prove identity; dir-name inference is
%   forbidden. Unknown/malformed/unreadable/absent metadata fails closed.
%   Release, full version/build, numeric mcrversion, and runtime-lib
%   identity are kept distinct (see local_parse_version_info). No catalog.
%   R2010b only.
if ~ischar(mcr_root) || size(mcr_root, 1) ~= 1 || ...
        isempty(strtrim(mcr_root)) || any(mcr_root == char(0))
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT path is invalid.');
end
trimmed = strtrim(mcr_root);
if exist(trimmed, 'dir') ~= 7
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT directory is unavailable.');
end
version_info = fullfile(trimmed, 'VersionInfo.xml');
if exist(version_info, 'file') ~= 2
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT identity metadata is unavailable.');
end
content = '';
try
    fid = fopen(version_info, 'r');
    if fid == -1
        error('pseudo_CT:MLSCCurrentMCR', ...
            'The current MCR_ROOT identity metadata is unreadable.');
    end
    raw = fread(fid, inf, '*char')';
    fclose(fid);
    content = raw;
catch %#ok<CTCH>
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT identity metadata is unreadable.');
end
if ~ischar(content) || isempty(strtrim(content))
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT identity metadata is malformed.');
end
parsed = local_parse_version_info(content);
% Architecture/platform: VersionInfo.xml is authoritative when it carries
% an arch/platform tag (must equal glnxa64); otherwise the
% runtime/glnxa64 structure guard proves the platform. Either way the
% directory name alone never proves release/update/version.
arch_from_disk = parsed.arch;
if isempty(arch_from_disk)
    runtime_glnxa64 = fullfile(trimmed, 'runtime', 'glnxa64');
    if exist(runtime_glnxa64, 'dir') ~= 7
        error('pseudo_CT:MLSCCurrentMCR', ...
            'The current MCR_ROOT architecture is unknown.');
    end
    arch_from_disk = 'glnxa64';
else
    if ~strcmp(arch_from_disk, 'glnxa64')
        error('pseudo_CT:MLSCCurrentMCR', ...
            'The current MCR_ROOT architecture is mismatched.');
    end
    runtime_glnxa64 = fullfile(trimmed, 'runtime', 'glnxa64');
    if exist(runtime_glnxa64, 'dir') ~= 7
        error('pseudo_CT:MLSCCurrentMCR', ...
            'The current MCR_ROOT structure is malformed.');
    end
end
actual = struct();
actual.release = parsed.release;
actual.version = parsed.version;
actual.update = parsed.update;
actual.mcr_version = parsed.mcr_version;
actual.arch = arch_from_disk;
actual.generation = parsed.generation;
end

function parsed = local_parse_version_info(content)
%LOCAL_PARSE_VERSION_INFO Parse ACTUAL metadata from VersionInfo.xml text.
%   Returns release/version/update/mcr_version/arch/generation with
%   release vs full version/build vs numeric mcrversion vs runtime-lib kept
%   distinct. Fails closed on unknown/malformed/absent fields. R2010b only.
parsed = struct('release', '', 'version', '', 'update', -1, ...
    'mcr_version', [], 'arch', '', 'generation', '');
if ~ischar(content) || size(content, 1) ~= 1 || isempty(strtrim(content))
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT identity metadata is malformed.');
end
% Release: explicit <release>R2026a</release> (case-insensitive tag).
release_tok = regexp(content, '<\s*release\s*>\s*(R[0-9]{4}[ab])\s*<\s*/\s*release\s*>', ...
    'tokens', 'once', 'ignorecase');
if isempty(release_tok) || isempty(release_tok{1})
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT release identity is unknown.');
end
release_text = strtrim(release_tok{1});
if isempty(regexp(release_text, '^R[0-9]{4}[ab]$', 'once'))
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT release identity is malformed.');
end
parsed.release = release_text;
% Full version/build: explicit <version>26.1.0.3251617</version>.
version_tok = regexp(content, '<\s*version\s*>\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s*<\s*/\s*version\s*>', ...
    'tokens', 'once', 'ignorecase');
if isempty(version_tok) || isempty(version_tok{1})
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT version identity is unknown.');
end
version_text = strtrim(version_tok{1});
parts = regexp(version_text, '^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$', ...
    'tokens', 'once');
if isempty(parts)
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT version identity is malformed.');
end
parsed.version = version_text;
major_v = str2double(parts{1});
minor_v = str2double(parts{2});
if ~isfinite(major_v) || ~isfinite(minor_v)
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT version identity is malformed.');
end
% Numeric mcrversion is [major minor] derived from the full version, kept
% distinct from the full version/build string and from the update level.
parsed.mcr_version = [double(major_v) double(minor_v)];
parsed.generation = sprintf('%d.%d', double(major_v), double(minor_v));
% Update: numeric level from explicit update tags or 'Update N' text.
% Supports <update>2</update>, <update>Update 2</update>,
% <update_level>Update 2</update_level>, <Update>Update 2</Update>.
update_value = -1;
update_tok = regexp(content, '<\s*update[^>]*>\s*([^<]*)\s*<\s*/\s*update[^>]*>', ...
    'tokens', 'once', 'ignorecase');
if ~isempty(update_tok) && ~isempty(strtrim(update_tok{1}))
    update_text = strtrim(update_tok{1});
    % Bare integer inside update tags.
    if ~isempty(regexp(update_text, '^[0-9]+$', 'once'))
        update_value = str2double(update_text);
    else
        num_tok = regexp(update_text, 'Update[^0-9]*([0-9]+)', ...
            'tokens', 'once', 'ignorecase');
        if ~isempty(num_tok)
            update_value = str2double(num_tok{1});
        end
    end
end
if update_value < 0 || ~isfinite(update_value)
    % Fallback: any 'Update N' text in the document (still explicit).
    num_tok = regexp(content, 'Update[^0-9]*([0-9]+)', ...
        'tokens', 'once', 'ignorecase');
    if ~isempty(num_tok)
        update_value = str2double(num_tok{1});
    end
end
if update_value < 0 || ~isfinite(update_value) || ...
        update_value ~= floor(update_value)
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT update identity is unknown.');
end
parsed.update = double(update_value);
% Arch/platform: explicit tag when present (<arch>, <platform>,
% <architecture>). Absent is allowed here (structure guard proves it);
% present-but-wrong fails in the caller. Never infer from dir names.
arch_text = '';
arch_tok = regexp(content, '<\s*(arch|platform|architecture)\s*>\s*([A-Za-z0-9_.-]+)\s*<\s*/\s*\1\s*>', ...
    'tokens', 'once', 'ignorecase');
if ~isempty(arch_tok) && length(arch_tok) >= 2 && ~isempty(strtrim(arch_tok{2}))
    arch_text = strtrim(arch_tok{2});
end
parsed.arch = arch_text;
end

function marker = local_pending_native_marker()
marker = 't007-gate-a-pending: existence-only; production loadability evidence comes later';
end

function schema = local_gate_a_schema()
schema = 'pseudo-CT.mlsc-current-gate-a/v1';
end

function local_validate_gate_a_record(current, build, resources)
%LOCAL_VALIDATE_GATE_A_RECORD Strict structured Gate-A record gate.
%   The record is a separate immutable .mat (variable gate_a) minted only
%   by mlsc_finalize_gate_a from the exact Gate-A candidate plus observed
%   Gate-A evidence; it binds but never rewrites manifests or provenance.
%   Every binding is recomputed from disk here: schema/generation,
%   runner/exe/build/resource SHA-256, source-provenance fingerprint plus
%   base HEAD, pinned MCR_ROOT with disk-validated release/version/update/
%   numeric/arch, every native identity plus per-native pass, launcher and
%   library pass, PREPARE/COMPUTE pass, overall pass. Missing, malformed,
%   unknown-schema, mismatched, missing/failed-native, and foreign records
%   fail closed. No basename/size fallback, no legacy/catalog/resolver.
%   Structural record problems raise MLSCCurrentManifest; failed production
%   evidence raises MLSCCurrentNativeEvidence. R2010b only.
if ~isfield(current, 'gate_a_record') || ~ischar(current.gate_a_record) || ...
        size(current.gate_a_record, 1) ~= 1 || ...
        isempty(strtrim(current.gate_a_record)) || ...
        any(current.gate_a_record == char(0))
    error('pseudo_CT:MLSCCurrentNativeEvidence', ...
        'The Gate-A record is absent; real execution is blocked.');
end
record_path = strtrim(current.gate_a_record);
if exist(record_path, 'file') ~= 2
    error('pseudo_CT:MLSCCurrentNativeEvidence', ...
        'The Gate-A record is unavailable; real execution is blocked.');
end
loaded = load(record_path);
if ~isfield(loaded, 'gate_a')
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record %s is missing variable gate_a.', record_path);
end
record = loaded.gate_a;
if ~isstruct(record) || numel(record) ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record %s variable gate_a must be one scalar struct.', ...
        record_path);
end
if ~isfield(record, 'schema') || ~ischar(record.schema) || ...
        size(record.schema, 1) ~= 1 || ...
        ~strcmp(record.schema, local_gate_a_schema())
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record %s has an unexpected schema.', record_path);
end
if ~isfield(record, 'manifest_version') || ...
        ~isnumeric(record.manifest_version) || ...
        ~isscalar(record.manifest_version) || record.manifest_version ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record %s has an unsupported version.', record_path);
end
required = {'source_commit'; 'source_provenance_fingerprint'; ...
    'mcr_root'; 'release'; 'version'; 'update_minimum'; ...
    'update_actual'; 'mcr_version'; 'arch'; 'generation'; ...
    'runner'; 'runner_checksum'; 'build_exe'; 'build_exe_checksum'; ...
    'build_manifest'; 'build_manifest_checksum'; ...
    'resource_manifest'; 'resource_manifest_checksum'; ...
    'native_names'; 'native_paths'; 'native_checksums'; ...
    'native_results'; 'launcher_result'; 'runtime_lib_result'; ...
    'prepare_result'; 'compute_result'; 'overall_result'};
for ii = 1:length(required)
    if ~isfield(record, required{ii})
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Gate-A record is missing field %s.', required{ii});
    end
end
% Provenance binding: base HEAD plus fingerprint must equal the build
% manifest (finalization binds, never rewrites).
if ~ischar(record.source_commit) || size(record.source_commit, 1) ~= 1 || ...
        ~strcmp(strtrim(record.source_commit), strtrim(build.source_commit))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record source commit does not match the build manifest.');
end
if ~local_is_valid_sha256(record.source_provenance_fingerprint) || ...
        ~strcmp(lower(strtrim(record.source_provenance_fingerprint)), ...
        lower(strtrim(build.source_provenance_fingerprint)))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record provenance does not match the build manifest.');
end
% Runtime binding: pinned root with disk-validated actual identity.
pinned = local_pinned_mcr_root();
if ~ischar(record.mcr_root) || size(record.mcr_root, 1) ~= 1 || ...
        ~strcmp(local_strip_sep(strtrim(record.mcr_root)), pinned)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record MCR_ROOT does not match the pinned %s.', pinned);
end
actual = local_actual_runtime_identity(strtrim(current.mcr_root));
if ~ischar(record.release) || size(record.release, 1) ~= 1 || ...
        ~strcmp(strtrim(record.release), actual.release)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record release is incompatible (expected %s).', ...
        actual.release);
end
if ~ischar(record.version) || size(record.version, 1) ~= 1 || ...
        ~strcmp(strtrim(record.version), actual.version)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record runtime version is incompatible.');
end
if ~isnumeric(record.update_minimum) || ~isscalar(record.update_minimum) || ...
        record.update_minimum ~= build.update_minimum
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record update minimum does not match the build manifest.');
end
if ~isnumeric(record.update_actual) || ~isscalar(record.update_actual) || ...
        ~isfinite(record.update_actual) || ...
        record.update_actual ~= floor(record.update_actual) || ...
        record.update_actual ~= actual.update
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record runtime update does not match the pinned runtime.');
end
if ~isnumeric(record.mcr_version) || numel(record.mcr_version) ~= 2 || ...
        record.mcr_version(1) ~= actual.mcr_version(1) || ...
        record.mcr_version(2) ~= actual.mcr_version(2)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record numeric runtime version is incompatible.');
end
if ~ischar(record.arch) || size(record.arch, 1) ~= 1 || ...
        ~strcmp(strtrim(record.arch), actual.arch)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record architecture is incompatible.');
end
if ~ischar(record.generation) || size(record.generation, 1) ~= 1 || ...
        ~strcmp(strtrim(record.generation), actual.generation)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record generation is incompatible.');
end
% File bindings: every identity recomputed from disk (SHA-256 mandatory).
if ~ischar(record.runner) || size(record.runner, 1) ~= 1 || ...
        ~strcmp(strtrim(record.runner), strtrim(current.runner)) || ...
        ~strcmp(strtrim(record.runner), strtrim(build.runner))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record runner does not match the current artifact.');
end
if ~local_is_valid_sha256(record.runner_checksum)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record runner checksum must be SHA-256.');
end
runner_actual = local_fingerprint(strtrim(current.runner));
if isempty(runner_actual) || ...
        ~strcmp(lower(strtrim(record.runner_checksum)), ...
        lower(strtrim(runner_actual))) || ...
        ~strcmp(lower(strtrim(build.runner_checksum)), ...
        lower(strtrim(runner_actual)))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record runner identity does not match the runner file.');
end
if ~ischar(record.build_exe) || size(record.build_exe, 1) ~= 1 || ...
        isempty(strtrim(record.build_exe))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record executable path is invalid.');
end
if ~local_is_valid_sha256(record.build_exe_checksum)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record executable checksum must be SHA-256.');
end
exe_actual = local_fingerprint(strtrim(record.build_exe));
if isempty(exe_actual) || ...
        ~strcmp(lower(strtrim(record.build_exe_checksum)), ...
        lower(strtrim(exe_actual)))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record executable identity does not match the file.');
end
if ~ischar(record.build_manifest) || size(record.build_manifest, 1) ~= 1 || ...
        ~strcmp(strtrim(record.build_manifest), ...
        strtrim(current.build_manifest))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record build manifest does not match the artifact.');
end
if ~local_is_valid_sha256(record.build_manifest_checksum)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record build manifest checksum must be SHA-256.');
end
build_actual = local_fingerprint(strtrim(current.build_manifest));
if isempty(build_actual) || ...
        ~strcmp(lower(strtrim(record.build_manifest_checksum)), ...
        lower(strtrim(build_actual)))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record build manifest identity does not match the file.');
end
if ~ischar(record.resource_manifest) || ...
        size(record.resource_manifest, 1) ~= 1 || ...
        ~strcmp(strtrim(record.resource_manifest), ...
        strtrim(current.resource_manifest))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record resource manifest does not match the artifact.');
end
if ~local_is_valid_sha256(record.resource_manifest_checksum)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record resource manifest checksum must be SHA-256.');
end
resource_actual = local_fingerprint(strtrim(current.resource_manifest));
if isempty(resource_actual) || ...
        ~strcmp(lower(strtrim(record.resource_manifest_checksum)), ...
        lower(strtrim(resource_actual)))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A record resource identity does not match the file.');
end
% Native bindings: every listed native recomputed, every result pass.
if ~iscell(record.native_names) || isempty(record.native_names) || ...
        ~iscell(record.native_paths) || ~iscell(record.native_checksums) || ...
        ~iscell(record.native_results)
    error('pseudo_CT:MLSCCurrentNativeEvidence', ...
        'Gate-A record native evidence is invalid.');
end
if numel(record.native_names) ~= numel(record.native_paths) || ...
        numel(record.native_names) ~= numel(record.native_checksums) || ...
        numel(record.native_names) ~= numel(record.native_results)
    error('pseudo_CT:MLSCCurrentNativeEvidence', ...
        'Gate-A record native evidence is inconsistent.');
end
for ii = 1:numel(record.native_names)
    name_here = record.native_names{ii};
    path_here = record.native_paths{ii};
    sum_here = record.native_checksums{ii};
    result_here = record.native_results{ii};
    if ~ischar(name_here) || size(name_here, 1) ~= 1 || ...
            isempty(strtrim(name_here))
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Gate-A record native evidence is invalid.');
    end
    if ~ischar(result_here) || size(result_here, 1) ~= 1 || ...
            ~strcmp(strtrim(result_here), 'pass')
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Gate-A native %s did not pass.', strtrim(name_here));
    end
    if ~ischar(path_here) || size(path_here, 1) ~= 1 || ...
            isempty(strtrim(path_here)) || ...
            ~local_is_valid_sha256(sum_here)
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Gate-A record native identity is invalid.');
    end
    native_actual = local_fingerprint(strtrim(path_here));
    if isempty(native_actual) || ...
            ~strcmp(lower(strtrim(sum_here)), lower(strtrim(native_actual)))
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Gate-A native %s identity does not match the file.', ...
            strtrim(name_here));
    end
end
if isfield(resources, 'native_names') && iscell(resources.native_names) && ...
        ~isempty(resources.native_names)
    for ii = 1:numel(resources.native_names)
        required_name = resources.native_names{ii};
        if ~ischar(required_name) || size(required_name, 1) ~= 1
            continue;
        end
        covered = false;
        for jj = 1:numel(record.native_names)
            entry = record.native_names{jj};
            result_entry = record.native_results{jj};
            if ischar(entry) && size(entry, 1) == 1 && ...
                    strcmp(strtrim(entry), strtrim(required_name)) && ...
                    ischar(result_entry) && ...
                    strcmp(strtrim(result_entry), 'pass')
                covered = true;
                break;
            end
        end
        if ~covered
            error('pseudo_CT:MLSCCurrentNativeEvidence', ...
                'Gate-A record is missing native %s.', ...
                strtrim(required_name));
        end
    end
end
% Observed Gate-A run evidence: every gate must report pass.
evidence_fields = {'launcher_result'; 'runtime_lib_result'; ...
    'prepare_result'; 'compute_result'; 'overall_result'};
for ii = 1:length(evidence_fields)
    value = record.(evidence_fields{ii});
    if ~ischar(value) || size(value, 1) ~= 1 || ...
            ~strcmp(strtrim(value), 'pass')
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Gate-A %s did not pass.', evidence_fields{ii});
    end
end
end

function value = local_strip_sep(value)
value = strtrim(value);
while length(value) > 1 && (value(end) == '/' || value(end) == char(92))
    value(end) = '';
end
end

function local_validate_contract(config, for_execution)
if ~isstruct(config) || numel(config) ~= 1
    error('pseudo_CT:MLSCCurrentContract', ...
        'A current config struct is required.');
end
if ~local_is_current(config)
    error('pseudo_CT:MLSCCurrentContract', ...
        'The selected profile is not an MLSC current profile.');
end
if ~isfield(config, 'current') || ~isstruct(config.current) || ...
        numel(config.current) ~= 1
    error('pseudo_CT:MLSCCurrentContract', ...
        'The MLSC current profile has no valid current artifact block.');
end
current = config.current;
required = {'runner'; 'mcr_root'; 'build_manifest'; 'resource_manifest'};
for ii = 1:length(required)
    if ~isfield(current, required{ii})
        error('pseudo_CT:MLSCCurrentContract', ...
            'The current artifact block is missing %s.', required{ii});
    end
end
text_fields = {'runner'; 'mcr_root'; 'build_manifest'; 'resource_manifest'};
for ii = 1:length(text_fields)
    value = current.(text_fields{ii});
    if ~ischar(value) || size(value, 1) ~= 1 || isempty(strtrim(value)) || ...
            any(value == char(0))
        error('pseudo_CT:MLSCCurrentContract', ...
            'The current artifact %s is invalid.', text_fields{ii});
    end
end
% Pinned exactness: version-specific 26.1 only. Rejects current symlink,
% MCR 7.11, latest/current labels, workstation inference, and any other
% substituted root by string inequality (no dynamic discovery).
pinned = local_pinned_mcr_root();
if ~strcmp(local_strip_sep(current.mcr_root), pinned)
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT must be the pinned %s.', pinned);
end
if exist(strtrim(current.runner), 'file') ~= 2
    error('pseudo_CT:MLSCCurrentRunner', ...
        'The current runner is unavailable.');
end
local_validate_structure(current.mcr_root);
if exist(strtrim(current.build_manifest), 'file') ~= 2
    error('pseudo_CT:MLSCCurrentManifest', ...
        'The current build manifest is unavailable.');
end
if exist(strtrim(current.resource_manifest), 'file') ~= 2
    error('pseudo_CT:MLSCCurrentManifest', ...
        'The current resource manifest is unavailable.');
end
build = local_load_scalar(current.build_manifest, 'build', ...
    'pseudo-CT.mlsc-current-build/v1');
local_validate_build(build, current);
resources = local_load_scalar(current.resource_manifest, 'resources', ...
    'pseudo-CT.mlsc-current-resources/v1');
local_validate_resources_contract(resources, for_execution, current, build);
% Build/resource compatibility: native platform/arch must equal the build
% arch so a mismatched resource set cannot satisfy the artifact contract.
if isfield(resources, 'native_platform') && ischar(resources.native_platform)
    if ~strcmp(strtrim(resources.native_platform), strtrim(build.arch))
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Build and resource architecture are incompatible.');
    end
end
if isfield(resources, 'native_arch') && ischar(resources.native_arch)
    if ~strcmp(strtrim(resources.native_arch), strtrim(build.arch))
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Build and resource architecture are incompatible.');
    end
end
end

function local_validate_structure(mcr_root)
if ~ischar(mcr_root) || size(mcr_root, 1) ~= 1 || ...
        isempty(strtrim(mcr_root)) || any(mcr_root == char(0))
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT path is invalid.');
end
trimmed = strtrim(mcr_root);
if exist(trimmed, 'dir') ~= 7
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT directory is unavailable.');
end
% Malformed-structure guard: the pinned full-install tree must expose the
% runtime libs beneath it. The generated launcher proves behavior with
% loaded-library evidence; folder names alone never prove execution.
runtime_glnxa64 = fullfile(trimmed, 'runtime', 'glnxa64');
if exist(runtime_glnxa64, 'dir') ~= 7
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The current MCR_ROOT structure is malformed.');
end
end

function value = local_load_scalar(manifest_path, variable_name, expected_schema)
loaded = load(manifest_path);
if ~isfield(loaded, variable_name)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Manifest %s is missing variable %s.', manifest_path, variable_name);
end
value = loaded.(variable_name);
if ~isstruct(value) || numel(value) ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Manifest %s variable %s must be one scalar struct.', ...
        manifest_path, variable_name);
end
if ~isfield(value, 'schema') || ~ischar(value.schema) || ...
        size(value.schema, 1) ~= 1 || ~strcmp(value.schema, expected_schema)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Manifest %s has an unexpected schema.', manifest_path);
end
if ~isfield(value, 'manifest_version') || ~isnumeric(value.manifest_version) || ...
        ~isscalar(value.manifest_version) || value.manifest_version ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Manifest %s has an unsupported version.', manifest_path);
end
end

function local_validate_build(build, current)
required = {'runner'; 'mcr_root'; 'release'; 'update_minimum'; ...
    'mcr_version'; 'arch'; 'generation'; 'runner_checksum'; ...
    'source_commit'; 'source_provenance_fingerprint'; ...
    'required_outputs'};
for ii = 1:length(required)
    if ~isfield(build, required{ii})
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Build manifest is missing field %s.', required{ii});
    end
end
if ~ischar(build.runner) || size(build.runner, 1) ~= 1 || ...
        isempty(strtrim(build.runner))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest runner is invalid.');
end
if ~strcmp(local_strip_sep(strtrim(build.runner)), ...
        local_strip_sep(strtrim(current.runner)))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest runner does not match the current artifact.');
end
pinned = local_pinned_mcr_root();
if ~ischar(build.mcr_root) || size(build.mcr_root, 1) ~= 1 || ...
        ~strcmp(local_strip_sep(strtrim(build.mcr_root)), pinned)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest MCR_ROOT does not match the pinned %s.', pinned);
end
% Actual Runtime identity comes from disk metadata, never from assumed
% constants alone: prove the pinned tree is R2026a/26.1/glnxa64 before
% comparing the build manifest to it.
actual = local_actual_runtime_identity(strtrim(current.mcr_root));
if ~ischar(build.release) || size(build.release, 1) ~= 1 || ...
        isempty(strtrim(build.release))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest release is invalid.');
end
if ~strcmp(strtrim(build.release), actual.release)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest release is incompatible (expected %s).', ...
        actual.release);
end
if ~isnumeric(build.update_minimum) || ~isscalar(build.update_minimum) || ...
        ~isfinite(build.update_minimum) || ...
        build.update_minimum ~= floor(build.update_minimum) || ...
        build.update_minimum < 0
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest update_minimum is invalid.');
end
% Same release: actual pinned update must be >= build minimum. Same update
% preferred, newer same-release update compatible, older actual fails.
if actual.update < build.update_minimum
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest update minimum is not satisfied by the pinned runtime.');
end
if ~isnumeric(build.mcr_version) || numel(build.mcr_version) ~= 2 || ...
        any(build.mcr_version ~= floor(build.mcr_version))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest mcr_version is invalid.');
end
if build.mcr_version(1) ~= actual.mcr_version(1) || ...
        build.mcr_version(2) ~= actual.mcr_version(2)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest numeric runtime version is incompatible.');
end
if ~ischar(build.arch) || size(build.arch, 1) ~= 1 || ...
        ~strcmp(strtrim(build.arch), actual.arch)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest architecture is incompatible.');
end
if ~ischar(build.generation) || size(build.generation, 1) ~= 1 || ...
        ~strcmp(strtrim(build.generation), actual.generation)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest generation is incompatible.');
end
if ~ischar(build.runner_checksum) || size(build.runner_checksum, 1) ~= 1 || ...
        isempty(strtrim(build.runner_checksum))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest runner checksum is invalid.');
end
% B4B immutable identity: SHA-256 MANDATORY for the runner. No
% filesize/mtime/existence fallback. If hashing is unavailable the
% recomputed identity is empty and fails closed here, before PREPARE.
if ~local_is_valid_sha256(strtrim(build.runner_checksum))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest runner checksum must be SHA-256.');
end
expected_fp = local_fingerprint(strtrim(current.runner));
if isempty(expected_fp)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Current runner identity hashing is unavailable.');
end
if ~strcmp(lower(strtrim(build.runner_checksum)), lower(strtrim(expected_fp)))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest runner identity does not match the runner file.');
end
if ~ischar(build.source_commit) || size(build.source_commit, 1) ~= 1 || ...
        isempty(strtrim(build.source_commit))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest source commit is invalid.');
end
if ~ischar(build.source_provenance_fingerprint) || ...
        size(build.source_provenance_fingerprint, 1) ~= 1 || ...
        ~local_is_valid_sha256(strtrim(build.source_provenance_fingerprint))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest source provenance fingerprint must be SHA-256.');
end
if ~iscell(build.required_outputs) || isempty(build.required_outputs)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest required outputs are invalid.');
end
[m_req, n_req] = size(build.required_outputs);
if ~((m_req >= 1 && n_req == 1) || (m_req == 1 && n_req >= 1))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest required outputs must be a cell vector.');
end
expected_outputs = {'att_map.nii'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
for ii = 1:length(expected_outputs)
    found = false;
    for jj = 1:numel(build.required_outputs)
        entry = build.required_outputs{jj};
        if ischar(entry) && size(entry, 1) == 1 && ...
                strcmp(strtrim(entry), expected_outputs{ii})
            found = true;
            break;
        end
    end
    if ~found
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Build manifest is missing required output %s.', ...
            expected_outputs{ii});
    end
end
end

function local_validate_resources_contract(resources, for_execution, current, build)
if ~isfield(resources, 'native_platform')
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Resource manifest is missing native_platform.');
end
if ~isfield(resources, 'native_arch')
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Resource manifest is missing native_arch.');
end
if ~isfield(resources, 'native_validation')
    error('pseudo_CT:MLSCCurrentNativeEvidence', ...
        'Resource manifest is missing native_validation.');
end
if ~ischar(resources.native_platform) || ...
        ~strcmp(strtrim(resources.native_platform), 'glnxa64')
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Resource manifest platform is incompatible.');
end
if ~ischar(resources.native_arch) || ...
        ~strcmp(strtrim(resources.native_arch), 'glnxa64')
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Resource manifest architecture is incompatible.');
end
if ~ischar(resources.native_validation) || ...
        size(resources.native_validation, 1) ~= 1 || ...
        isempty(strtrim(resources.native_validation))
    error('pseudo_CT:MLSCCurrentNativeEvidence', ...
        'Resource manifest native validation is invalid.');
end
pending = local_pending_native_marker();
if for_execution
    % Production gate: manifests stay immutable, so the pending marker is
    % t007-gate-a-pending marker is
    % still required AND the separate Gate-A record must bind this exact
    % candidate. Pending alone, no record, or any failing binding stays
    % blocked without a Gate-A run. Arbitrary strings (including any
    % legacy validated-marker string) are rejected here.
    if ~strcmp(strtrim(resources.native_validation), pending)
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Resource manifest native validation is unknown.');
    end
    local_validate_gate_a_record(current, build, resources);
else
    % Contract gate: pending is the expected offline state. Any
    % non-pending value (including arbitrary legacy validated-marker
    % strings) is unknown and rejected now; unknown evidence never
    % reaches execution.
    if ~strcmp(strtrim(resources.native_validation), pending)
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Resource manifest native validation is unknown.');
    end
end
end

function text = local_fingerprint(path_text)
%LOCAL_FINGERPRINT SHA-256 content identity for the runner (B4B).
%   SHA-256 MANDATORY. Returns the lowercase 64-hex content hash, or ''
%   when hashing is unavailable (fail closed by the caller, never a
%   filesize/mtime/existence fallback). R2010b only.
text = local_sha_hex(path_text);
end

function flag = local_is_valid_sha256(value)
%LOCAL_IS_VALID_SHA256 Strict 64-hex SHA-256 shape (B5A).
%   Missing/empty/malformed (wrong length, non-hex) fails. R2010b only.
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

function flag = local_is_valid_normalized_input_sha(content)
%LOCAL_IS_VALID_NORMALIZED_INPUT_SHA Strict normalized-input SHA-256.
%   Parses the 'normalized_input:' fingerprint line (exact prefix, never
%   the 'normalized_input_verified:' marker) and requires the ENTIRE
%   normalized value after sha256= to match ^[0-9a-fA-F]{64}$ exactly
%   (same strict policy as required-output SHA). Prefix extraction is
%   forbidden: missing line, missing sha256=, empty, 63/65-hex,
%   64hex+suffix, prefix+64hex, trailing tokens, and non-hex all fail.
%   R2010b only.
flag = false;
try
    if ~ischar(content) || isempty(content)
        return;
    end
    normalized = strrep(content, char(13), char(10));
    parts = regexp(normalized, char(10), 'split');
    found = false;
    for ii = 1:length(parts)
        line = strtrim(parts{ii});
        % Exact 'normalized_input:' prefix; the verified marker has a
        % longer prefix and must not match here.
        if strncmp(line, 'normalized_input:', length('normalized_input:'))
            % Guard against 'normalized_input_verified:' sharing the
            % prefix: require the character after the prefix to not be
            % part of a longer field name (verified line starts with
            % 'normalized_input_verified', not 'normalized_input:').
            % strncmp above already distinguishes because verified line
            % has '_' at that position, not ':'.
            tail = line(length('normalized_input:') + 1:end);
            sha_pos = strfind(lower(tail), 'sha256=');
            if isempty(sha_pos)
                return;
            end
            sha_tail = tail(sha_pos(1) + 7:end);
            sha_candidate = strtrim(sha_tail);
            if isempty(regexp(sha_candidate, '^[0-9a-fA-F]{64}$', 'once'))
                return;
            end
            if ~local_is_valid_sha256(sha_candidate)
                return;
            end
            found = true;
        end
    end
    if ~found
        return;
    end
    flag = true;
catch %#ok<CTCH>
    flag = false;
end
end

function map = local_output_filename_map()
% Explicit authoritative key->basename map (testable contract).
map = struct();
map.att_map = 'att_map.nii';
map.validation_fusion = 'Fusion_MR_Pseudo_CT_validation.tiff';
map.validation_composite = 'Composite_Fusion_MR_Pseudo_CT_validation.tiff';
map.version = 'Pseudo_CT_AC_Version.txt';
end

function ok = local_verify_output_verification(verification_path)
ok = false;
try
    content = local_read_text_file(verification_path);
    if isempty(content)
        return;
    end
    if isempty(strfind(content, 'pseudo-CT.mlsc-current-output-verification/v1'))
        return;
    end
    if isempty(strfind(content, 'normalized_input_verified'))
        return;
    end
    % NORMALIZED_INPUT SHA STRICT: the 'normalized_input:' fingerprint
    % line must carry exactly ^[0-9A-Fa-f]{64}$ after whitespace
    % normalization (same strict policy as required-output SHA). Missing,
    % empty, 63/65-hex, 64hex+suffix, prefix+64hex, trailing tokens, and
    % non-hex all fail. The verified marker never overrides a malformed
    % SHA; evidence must be internally consistent.
    if ~local_is_valid_normalized_input_sha(content)
        return;
    end
    entries = local_verify_entries(verification_path);
    if isempty(entries)
        return;
    end
    basenames = {};
    for ii = 1:length(entries)
        basenames{end + 1, 1} = entries{ii}.basename; %#ok<AGROW>
    end
    map = local_output_filename_map();
    has_att = local_list_contains(basenames, map.att_map);
    has_ver = local_list_contains(basenames, map.version);
    has_fusion = local_list_contains(basenames, map.validation_fusion);
    has_composite = local_list_contains(basenames, map.validation_composite);
    if ~has_att || ~has_ver || ~(has_fusion || has_composite)
        return;
    end
    for ii = 1:length(entries)
        if ~(entries{ii}.bytes > 0 && isfinite(entries{ii}.bytes))
            return;
        end
        % B5A: SHA-256 MANDATORY for every required output. Missing,
        % empty, malformed, or unverifiable SHA fails. No size-only
        % fallback (fingerprint tail alone is insufficient).
        if ~local_is_valid_sha256(entries{ii}.sha256)
            return;
        end
    end
    if isempty(local_parse_semantic_block(content))
        return;
    end
    ok = true;
catch %#ok<CTCH>
    ok = false;
end
end

function ok = local_verify_copyback_identity(shared_temp, verification_path)
ok = false;
try
    entries = local_verify_entries(verification_path);
    if isempty(entries)
        return;
    end
    for ii = 1:length(entries)
        basename = entries{ii}.basename;
        if ~local_is_basename(basename)
            return;
        end
        shared_path = fullfile(shared_temp, basename);
        if exist(shared_path, 'file') ~= 2
            return;
        end
        info = dir(shared_path);
        if isempty(info) || info(1).bytes ~= entries{ii}.bytes
            return;
        end
        % B5A: SHA-256 MANDATORY for every entry. Missing/malformed SHA
        % fails; independently recomputed SHA must exactly match. No
        % size-only fallback, so same-size different-content fails.
        if ~local_is_valid_sha256(entries{ii}.sha256)
            return;
        end
        actual = local_sha_hex(shared_path);
        if isempty(actual) || ~strcmp(lower(strtrim(actual)), ...
                lower(strtrim(entries{ii}.sha256)))
            return;
        end
    end
    ok = true;
catch %#ok<CTCH>
    ok = false;
end
end

function ok = local_verify_att_map_semantic(att_map_path, verification_path)
ok = false;
try
    [~, base_name, ext_name] = fileparts(att_map_path);
    if ~strcmp([base_name ext_name], 'att_map.nii')
        return;
    end
    if exist(att_map_path, 'file') ~= 2
        return;
    end
    content = local_read_text_file(verification_path);
    if isempty(content)
        return;
    end
    semantic = local_parse_semantic_block(content);
    if isempty(semantic)
        return;
    end
    if ~strcmp(strtrim(semantic.basename), 'att_map.nii')
        return;
    end
    info = dir(att_map_path);
    if isempty(info) || info(1).bytes <= 0
        return;
    end
    if info(1).bytes ~= semantic.bytes
        return;
    end
    % B5A/B5B: att_map SHA-256 MANDATORY. Missing/malformed/unverifiable
    % fails closed. No size-only fallback.
    if ~local_is_valid_sha256(semantic.sha256)
        return;
    end
    actual = local_sha_hex(att_map_path);
    if isempty(actual) || ~strcmp(lower(strtrim(actual)), ...
            lower(strtrim(semantic.sha256)))
        return;
    end
    if exist('spm_vol', 'file') ~= 2
        return;
    end
    try
        V = spm_vol(att_map_path);
    catch %#ok<CTCH>
        return;
    end
    if ~isstruct(V) || isempty(V)
        return;
    end
    V = V(1);
    if ~isfield(V, 'dim') || ~isfield(V, 'mat') || ~isfield(V, 'dt')
        return;
    end
    if ~isnumeric(V.dim) || numel(V.dim) < 3 || any(~isfinite(V.dim(:))) || ...
            any(V.dim(:) <= 0)
        return;
    end
    if ~isnumeric(V.mat) || numel(V.mat) ~= 16 || any(~isfinite(V.mat(:))) || ...
            isequal(V.mat, zeros(size(V.mat)))
        return;
    end
    if ~isnumeric(V.dt) || isempty(V.dt) || V.dt(1) ~= 16
        return;
    end
    if V.dt(1) ~= semantic.datatype
        return;
    end
    if ~isequal(V.dim(:)', semantic.dim(:)')
        % Allow 3-vs-4 length only when extra is singleton on both.
        a = V.dim(:)';
        e = semantic.dim(:)';
        maxlen = max(length(a), length(e));
        a(end + 1:maxlen) = 1;
        e(end + 1:maxlen) = 1;
        if ~isequal(a, e)
            return;
        end
    end
    if ~isequal(V.mat, semantic.affine)
        return;
    end
    try
        data = spm_read_vols(V);
    catch %#ok<CTCH>
        return;
    end
    if ~isnumeric(data) && ~islogical(data)
        return;
    end
    if isempty(data) || ~all(isfinite(data(:)))
        return;
    end
    if ~isequal(semantic.finite, 1)
        return;
    end
    ok = true;
catch %#ok<CTCH>
    ok = false;
end
end

function entries = local_verify_entries(verification_path)
entries = {};
try
    content = local_read_text_file(verification_path);
    if isempty(content)
        return;
    end
    normalized = strrep(content, char(13), char(10));
    parts = regexp(normalized, char(10), 'split');
    for ii = 1:length(parts)
        line = strtrim(parts{ii});
        prefix = 'output ';
        if ~strncmp(line, prefix, length(prefix))
            continue;
        end
        rest = strtrim(line(length(prefix) + 1:end));
        colon = strfind(rest, ':');
        if isempty(colon)
            continue;
        end
        basename = strtrim(rest(1:colon(1) - 1));
        if ~local_is_basename(basename)
            continue;
        end
        tail = rest(colon(1) + 1:end);
        bytes_pos = strfind(tail, 'bytes=');
        if isempty(bytes_pos)
            continue;
        end
        bytes_value = sscanf(tail(bytes_pos(1) + 6:end), '%d', 1);
        if isempty(bytes_value) || ~isfinite(bytes_value) || bytes_value <= 0
            continue;
        end
        sha_text = '';
        sha_pos = strfind(lower(tail), 'sha256=');
        if ~isempty(sha_pos)
            sha_tail = tail(sha_pos(1) + 7:end);
            % B5A: strict 64-hex SHA-256 shape. The ENTIRE normalized
            % value after sha256= must match ^[0-9a-fA-F]{64}$ exactly.
            % Prefix extraction is forbidden: 63/65-hex, 64hex+suffix,
            % prefix+64hex, trailing tokens, non-hex, and missing/empty
            % are not retained; the entry then fails the mandatory check.
            sha_candidate = strtrim(sha_tail);
            if ~isempty(regexp(sha_candidate, '^[0-9a-fA-F]{64}$', 'once'))
                sha_text = lower(sha_candidate);
            end
        end
        entry = struct('basename', basename, 'bytes', double(bytes_value(1)), ...
            'sha256', sha_text, 'fingerprint', strtrim(tail));
        entries{end + 1, 1} = entry; %#ok<AGROW>
    end
catch %#ok<CTCH>
    entries = {};
end
end

function semantic = local_parse_semantic_block(content)
semantic = [];
try
    basename = local_block_field(content, 'att_map_basename:');
    bytes_text = local_block_field(content, 'att_map_bytes:');
    sha_text = local_block_field(content, 'att_map_sha256:');
    dtype_text = local_block_field(content, 'att_map_datatype:');
    dim_text = local_block_field(content, 'att_map_dim:');
    affine_text = local_block_field(content, 'att_map_affine:');
    finite_text = local_block_field(content, 'att_map_finite:');
    if isempty(basename) || isempty(bytes_text) || isempty(dtype_text) || ...
            isempty(dim_text) || isempty(affine_text) || isempty(finite_text)
        return;
    end
    % B5A/B5B: att_map SHA-256 is mandatory structural evidence.
    % Missing/empty/malformed (non-64-hex) fails closed here.
    if ~local_is_valid_sha256(sha_text)
        return;
    end
    if ~strcmp(strtrim(basename), 'att_map.nii')
        return;
    end
    bytes_value = sscanf(strtrim(bytes_text), '%d', 1);
    dtype_value = sscanf(strtrim(dtype_text), '%d', 1);
    finite_value = sscanf(strtrim(finite_text), '%d', 1);
    if isempty(bytes_value) || ~isfinite(bytes_value) || bytes_value <= 0
        return;
    end
    if isempty(dtype_value) || dtype_value ~= 16
        return;
    end
    if isempty(finite_value) || finite_value ~= 1
        return;
    end
    dim_value = sscanf(strtrim(dim_text), '%f', inf);
    if isempty(dim_value) || any(~isfinite(dim_value)) || any(dim_value <= 0)
        return;
    end
    affine_value = sscanf(strtrim(affine_text), '%f', inf);
    if isempty(affine_value) || numel(affine_value) ~= 16 || ...
            any(~isfinite(affine_value))
        return;
    end
    affine_value = reshape(affine_value, 4, 4);
    semantic = struct('basename', 'att_map.nii', ...
        'bytes', double(bytes_value(1)), ...
        'sha256', lower(strtrim(sha_text)), ...
        'datatype', double(dtype_value(1)), ...
        'dim', dim_value(:)', ...
        'affine', affine_value, ...
        'finite', 1);
catch %#ok<CTCH>
    semantic = [];
end
end

function value = local_block_field(content, marker)
value = '';
try
    pos = strfind(content, marker);
    if isempty(pos)
        return;
    end
    tail = content(pos(1) + length(marker):end);
    newline = strfind(tail, char(10));
    if ~isempty(newline)
        tail = tail(1:newline(1) - 1);
    end
    carriage = strfind(tail, char(13));
    if ~isempty(carriage)
        tail = tail(1:carriage(1) - 1);
    end
    value = strtrim(tail);
catch %#ok<CTCH>
    value = '';
end
end

function flag = local_list_contains(list, target)
flag = false;
try
    for ii = 1:length(list)
        if ischar(list{ii}) && strcmp(strtrim(list{ii}), target)
            flag = true;
            return;
        end
    end
catch %#ok<CTCH>
    flag = false;
end
end

function flag = local_is_basename(name_text)
flag = false;
try
    if ~ischar(name_text) || size(name_text, 1) ~= 1 || ...
            isempty(strtrim(name_text)) || any(name_text == char(0))
        return;
    end
    trimmed = strtrim(name_text);
    if ~isempty(strfind(trimmed, '..')) || ~isempty(strfind(trimmed, '/')) || ...
            ~isempty(strfind(trimmed, char(92)))
        return;
    end
    flag = true;
catch %#ok<CTCH>
    flag = false;
end
end

function text = local_read_text_file(path_name)
text = '';
try
    fid = fopen(path_name, 'r');
    if fid == -1
        return;
    end
    raw = fread(fid, inf, '*char')';
    fclose(fid);
    if ischar(raw)
        text = raw;
    end
catch %#ok<CTCH>
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    text = '';
end
end

function hex = local_sha_hex(path_name)
%LOCAL_SHA_HEX SHA-256 content hash, fail-closed (B4B).
%   Java SHA-256 when available, else the approved deterministic
%   sha256sum mechanism. No FNV/filesize/mtime fallback: when hashing is
%   unavailable the result is '' and callers fail closed. R2010b only.
hex = '';
try
    fid = fopen(path_name, 'r');
    if fid == -1
        return;
    end
    raw = fread(fid, inf, '*uint8')';
    fclose(fid);
    if isempty(raw)
        return;
    end
    try
        digest = java.security.MessageDigest.getInstance('SHA-256');
        digest.update(raw);
        bytes = typecast(digest.digest(), 'uint8');
        candidate = lower(reshape(dec2hex(bytes, 2)', 1, []));
        if local_is_valid_sha256(candidate)
            hex = candidate;
            return;
        end
    catch %#ok<CTCH>
    end
    try
        quoted = local_shell_quote(path_name);
        [status, out] = system(['sha256sum ' quoted ' 2>/dev/null']);
        if status == 0 && ischar(out) && ~isempty(strtrim(out))
            tok = regexp(strtrim(out), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', ...
                'tokens', 'once');
            if ~isempty(tok)
                candidate = lower(strtrim(tok{1}));
                if local_is_valid_sha256(candidate)
                    hex = candidate;
                    return;
                end
            end
        end
    catch %#ok<CTCH>
    end
    hex = '';
catch %#ok<CTCH>
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    hex = '';
end
end

function quoted = local_shell_quote(value)
%LOCAL_SHELL_QUOTE POSIX single-quote for the sha256sum fallback.
quoted = '''''';
try
    if ~ischar(value) || size(value, 1) ~= 1 || isempty(value)
        quoted = '''''';
        return;
    end
    single_quote = char(39);
    double_quote = char(34);
    quoted = single_quote;
    for ii = 1:length(value)
        if value(ii) == char(0)
            error('pseudo_CT:MLSCCurrentManifest', 'NUL in path.');
        elseif value(ii) == single_quote
            quoted = [quoted single_quote double_quote single_quote ...
                double_quote single_quote]; %#ok<AGROW>
        else
            quoted = [quoted value(ii)]; %#ok<AGROW>
        end
    end
    quoted = [quoted single_quote];
catch %#ok<CTCH>
    quoted = '''''';
end
end
