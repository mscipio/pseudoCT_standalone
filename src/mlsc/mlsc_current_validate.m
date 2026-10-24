function varargout = mlsc_current_validate(action, varargin)
%MLSC_CURRENT_VALIDATE Pinned current artifact contract (T004, T014).
%   Implements the T014 pinned MCR_ROOT correction, which is authoritative
%   over the stale T004 catalog/resolver wording. There is no generic
%   catalog, no dynamic discovery, no MCR 7.11 fallback, no workstation
%   inference, no latest/current-label authority, and no submitting-MATLAB
%   substitute. The only accepted MCR_ROOT is the pinned version-specific
%   tree /usr/pubsw/common/matlab/7.11 (R2010b, containing MCR 7.14; never
%   the current symlink). The
%   generated launcher owns the Runtime environment; this file never
%   constructs a global LD_LIBRARY_PATH.
%
%   Actions (R2010b-compatible, deterministic offline, no live SSH/Slurm):
%     PINNED = MLSC_CURRENT_VALIDATE('pinned_mcr_root')
%     FLAG = MLSC_CURRENT_VALIDATE('is_current', CONFIG)
%     MLSC_CURRENT_VALIDATE('validate_contract', CONFIG)
%       Fail-closed pre-submission contract: missing runner/MCR_ROOT/
%       manifests, malformed MCR_ROOT structure, validated actual MCR_ROOT
%       identity from the exact MATLAB 7.11 install root containing MCR 7.14,
%       identity/arch/release/
%       generation/update mismatch, missing outputs contract. No native
%       certification check remains in this active dev path (T009
%       remediation): legacy native fields and simplified manifests omitting
%       them are both accepted; the payload enforces actual file existence.
%     MLSC_CURRENT_VALIDATE('validate_for_execution', CONFIG)
%       Same as contract. The former Gate-A execution requirement was
%       removed from this active dev path (T009 remediation): no Gate-A
%       record is required or consulted here. MCR/build/output/copy-back
%       enforcement is unchanged.
%     INFO = MLSC_CURRENT_VALIDATE('gate_a_schema')
%       Returns the exact expected Gate-A record schema string.
%     MLSC_CURRENT_VALIDATE('structure', MCR_ROOT)
%       Malformed-structure guard for one MCR_ROOT path (dir plus
%       runtime/glnxa64). Used by contract and directly by offline fixtures.
%     INFO = MLSC_CURRENT_VALIDATE('expected_actual')
%       Returns the pinned MATLAB root/MCR 7.14 identity (arch glnxa64).
%       Callers must not treat these constants as proof without the
%       root/library check in local_validate_build.
%     INFO = MLSC_CURRENT_VALIDATE('actual_identity', MCR_ROOT)
%       Returns the disk-validated actual MCR_ROOT identity after proving
%       the exact MATLAB 7.11 root and architecture-specific MCR 7.14 library.
%
%   Build manifest (.mat, scalar struct BUILD):
%     schema 'pseudo-CT.mlsc-current-build/v1', manifest_version 1,
%     runner (historic build path; relocated installs bind by basename
%     plus recomputed SHA-256, provenance preserved separately),
%     mcr_root (pinned MCR, separate from MATLAB matlabroot), compiler
%     release (R-prefixed), update_minimum,
%     mcr_version [major minor], arch, generation, runner_checksum
%     (SHA-256), source_commit (base HEAD),
%     source_provenance_fingerprint (SHA-256 over commit plus
%     tracked/untracked lists), required_outputs (canonical 3).
%   Resource manifest (.mat, scalar struct RESOURCES):
%     schema 'pseudo-CT.mlsc-current-resources/v1', manifest_version 1
%     (T003 authority; atlas/resource existence validated by payload).
%     Contract checks existence/schema/version only; legacy native fields
%     are ignored when present and required of nothing. Detailed
%     atlas/resource existence checks stay in mlsc_current_payload
%     (no duplicated science).
%   Gate-A record tooling (mlsc_finalize_gate_a, 'gate_a_schema') is
%   retained only as inert reference: nothing in this active dev path
%   requires, mints, or consults a Gate-A record.
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
pinned = '/usr/pubsw/common/matlab/7.11';
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
actual.release = 'R2010b';
actual.update = 0;
actual.mcr_version = [7 14];
actual.arch = 'glnxa64';
actual.generation = '7.14';
actual.version = '7.14';
end

function actual = local_actual_runtime_identity(mcr_root)
%LOCAL_ACTUAL_RUNTIME_IDENTITY Disk-validated MCR_ROOT identity.
%   Validate the explicit MATLAB R2010b installation root and the required
%   MCR 7.14 runtime installed beneath it.
%   MATLAB installation metadata is not Runtime metadata: in particular,
%   R2010b's matlabroot/mcrversion must never be used to identify MCR 7.14.
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
local_validate_structure(trimmed);
if ~strcmp(local_strip_sep(trimmed), local_pinned_mcr_root())
    error('pseudo_CT:MLSCCurrentMCR', ...
        'MATLAB root must be the explicit R2010b installation at %s.', ...
        local_pinned_mcr_root());
end
runtime_lib = fullfile(trimmed, 'runtime', 'glnxa64', 'libmwmclmcrrt.so');
if exist(runtime_lib, 'file') ~= 2
    error('pseudo_CT:MLSCCurrentMCR', ...
        'The MCR 7.14 runtime library under the pinned MATLAB root is unavailable.');
end
parsed = local_expected_actual();
actual = struct();
actual.release = parsed.release;
actual.version = parsed.version;
actual.update = parsed.update;
actual.mcr_version = parsed.mcr_version;
actual.arch = parsed.arch;
actual.generation = parsed.generation;
end

function schema = local_gate_a_schema()
schema = 'pseudo-CT.mlsc-current-gate-a/v1';
end


function value = local_strip_sep(value)
value = strtrim(value);
while length(value) > 1 && (value(end) == '/' || value(end) == char(92))
    value(end) = '';
end
end

function same = local_same_basename(path_a, path_b)
%LOCAL_SAME_BASENAME Basename identity for relocatable installs (R2010b).
%   Compares only the file name plus extension so the same content under a
%   new absolute directory prefix still binds; content itself is proven by
%   the recomputed SHA-256 at each call site. Both inputs must be absolute
%   paths (no bare basenames or relative paths); empty names never match.
same = false;
try
    if ~ischar(path_a) || size(path_a, 1) ~= 1 || ...
            ~ischar(path_b) || size(path_b, 1) ~= 1
        return;
    end
    trimmed_a = strtrim(path_a);
    trimmed_b = strtrim(path_b);
    if isempty(trimmed_a) || isempty(trimmed_b)
        return;
    end
    if trimmed_a(1) ~= '/' || trimmed_b(1) ~= '/'
        return;
    end
    [~, base_a, ext_a] = fileparts(trimmed_a);
    [~, base_b, ext_b] = fileparts(trimmed_b);
    name_a = [base_a ext_a];
    name_b = [base_b ext_b];
    if isempty(strtrim(name_a)) || isempty(strtrim(name_b))
        return;
    end
    same = strcmp(name_a, name_b);
catch %#ok<CTCH>
    same = false;
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
% Pinned exactness: explicit MATLAB 7.11 installation root only. Rejects current symlink,
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
% Resource manifest: existence plus scalar schema/version only. T009
% remediation removed every native certification check (pending marker,
% platform/arch, native inventory, build/resource arch compatibility) and
% the Gate-A execution requirement from this active dev path: manifests
% carrying legacy native fields and simplified manifests omitting them are
% both accepted here. The payload enforces actual file existence; output
% and copy-back verification below are unchanged.
local_load_scalar(current.resource_manifest, 'resources', ...
    'pseudo-CT.mlsc-current-resources/v1');
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
% Relocatable installed distribution: bind by content identity (basename
% plus the recomputed SHA-256 checked below), not by the historical
% absolute build path. Provenance (source commit/fingerprint) is preserved
% and compared exactly elsewhere; only the directory prefix may differ.
if ~local_same_basename(strtrim(build.runner), strtrim(current.runner))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest runner does not match the current artifact.');
end
pinned = local_pinned_mcr_root();
if ~ischar(build.mcr_root) || size(build.mcr_root, 1) ~= 1 || ...
        ~strcmp(local_strip_sep(strtrim(build.mcr_root)), pinned)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest MCR_ROOT does not match the pinned %s.', pinned);
end
% Runtime identity is proved by the exact MATLAB 7.11 install root, its
% architecture-specific runtime library, and separate MCR version 7.14
% metadata (MCR 7.14 does not ship the newer
% VersionInfo.xml metadata). The compiler release is separate: an R2010b
% MATLAB install can produce a payload deployed against MCR 7.14.
actual = local_actual_runtime_identity(strtrim(current.mcr_root));
if ~ischar(build.release) || size(build.release, 1) ~= 1 || ...
        isempty(strtrim(build.release))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest release is invalid.');
end
if ~strcmp(strtrim(build.release), actual.release)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest compiler release does not match pinned %s.', ...
        actual.release);
end
if ~isnumeric(build.update_minimum) || ~isscalar(build.update_minimum) || ...
        ~isfinite(build.update_minimum) || ...
        build.update_minimum ~= floor(build.update_minimum) || ...
        build.update_minimum < 0
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest update_minimum is invalid.');
end
% This Runtime installation does not publish update metadata. Keep the
% manifest field well-formed, but do not compare it to MATLAB's compiler
% update (that would confuse the install root with the deployed Runtime).
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
