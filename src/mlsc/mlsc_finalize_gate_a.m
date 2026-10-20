function gate_a = mlsc_finalize_gate_a(candidate, evidence, record_path)
%MLSC_FINALIZE_GATE_A Mint one immutable Gate-A record (T015).
%   GATE_A = MLSC_FINALIZE_GATE_A(CANDIDATE, EVIDENCE, RECORD_PATH)
%   deterministically assembles the structured machine-readable Gate-A
%   record for the exact Gate-A candidate and writes it to RECORD_PATH
%   (.mat, variable gate_a). No network, no deploy, no production-path
%   mutation: only RECORD_PATH is written. No self-certification: every
%   file identity is recomputed from disk here, the build manifest must
%   already carry the canonical validator schema, the pinned MCR_ROOT
%   identity is disk-validated, and overall pass is refused unless every
%   observed gate reports pass.
%
%   CANDIDATE fields (all non-empty character rows, all must exist):
%     runner, build_exe, build_manifest, resource_manifest, mcr_root.
%   EVIDENCE fields (observed Gate-A run results, never invented):
%     native_names (cell vector), native_paths (cell, same order),
%     native_results (cell of 'pass', same order), launcher_result,
%     runtime_lib_result, prepare_result, compute_result (each 'pass').
%   RECORD_PATH is the destination record file (parent must exist).
%
%   The record binds (never rewrites) the manifests: source commit plus
%   provenance fingerprint, pinned root with validated release/version/
%   actual update/minimum/numeric/arch/generation, runner/exe/build/
%   resource SHA-256, every native identity plus per-native pass, the
%   four run gates, and overall pass. Fixture records minted by tests are
%   test-only and unusable as production evidence (they bind fixture
%   paths, never the production artifact).
%
%   Minimum supported MATLAB: R2010b.

if ~isstruct(candidate) || numel(candidate) ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'A Gate-A candidate struct is required.');
end
if ~isstruct(evidence) || numel(evidence) ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A run evidence is required.');
end
if ~ischar(record_path) || size(record_path, 1) ~= 1 || ...
        isempty(strtrim(record_path)) || any(record_path == char(0))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'A Gate-A record path is required.');
end
record_path = strtrim(record_path);
[record_parent, ~, ~] = fileparts(record_path);
if ~isempty(record_parent) && exist(record_parent, 'dir') ~= 7
    error('pseudo_CT:MLSCCurrentManifest', ...
        'The Gate-A record directory is unavailable.');
end
candidate_fields = {'runner'; 'build_exe'; 'build_manifest'; ...
    'resource_manifest'; 'mcr_root'};
for ii = 1:length(candidate_fields)
    if ~isfield(candidate, candidate_fields{ii})
        error('pseudo_CT:MLSCCurrentManifest', ...
            'The Gate-A candidate is missing %s.', candidate_fields{ii});
    end
    value = candidate.(candidate_fields{ii});
    if ~ischar(value) || size(value, 1) ~= 1 || ...
            isempty(strtrim(value)) || any(value == char(0))
        error('pseudo_CT:MLSCCurrentManifest', ...
            'The Gate-A candidate %s is invalid.', candidate_fields{ii});
    end
    if exist(strtrim(value), 'file') == 2
        continue;
    end
    if exist(strtrim(value), 'dir') == 7
        continue;
    end
    error('pseudo_CT:MLSCCurrentManifest', ...
        'The Gate-A candidate %s is unavailable.', candidate_fields{ii});
end
evidence_lists = {'native_names'; 'native_paths'; 'native_results'};
for ii = 1:length(evidence_lists)
    if ~isfield(evidence, evidence_lists{ii})
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Gate-A evidence is missing %s.', evidence_lists{ii});
    end
end
if ~iscell(evidence.native_names) || isempty(evidence.native_names) || ...
        ~iscell(evidence.native_paths) || ~iscell(evidence.native_results)
    error('pseudo_CT:MLSCCurrentNativeEvidence', ...
        'Gate-A native evidence is invalid.');
end
if numel(evidence.native_names) ~= numel(evidence.native_paths) || ...
        numel(evidence.native_names) ~= numel(evidence.native_results)
    error('pseudo_CT:MLSCCurrentNativeEvidence', ...
        'Gate-A native evidence is inconsistent.');
end
run_gates = {'launcher_result'; 'runtime_lib_result'; ...
    'prepare_result'; 'compute_result'};
for ii = 1:length(run_gates)
    if ~isfield(evidence, run_gates{ii})
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Gate-A evidence is missing %s.', run_gates{ii});
    end
    value = evidence.(run_gates{ii});
    if ~ischar(value) || size(value, 1) ~= 1 || ...
            ~strcmp(strtrim(value), 'pass')
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Gate-A %s did not pass; no record is minted.', run_gates{ii});
    end
end
for ii = 1:numel(evidence.native_names)
    name_here = evidence.native_names{ii};
    result_here = evidence.native_results{ii};
    if ~ischar(name_here) || size(name_here, 1) ~= 1 || ...
            isempty(strtrim(name_here))
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Gate-A native evidence is invalid.');
    end
    if ~ischar(result_here) || size(result_here, 1) ~= 1 || ...
            ~strcmp(strtrim(result_here), 'pass')
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Gate-A native %s did not pass; no record is minted.', ...
            strtrim(name_here));
    end
end
% Build manifest authority: canonical schema, candidate consistency.
loaded_build = load(strtrim(candidate.build_manifest));
if ~isfield(loaded_build, 'build')
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest is missing variable build.');
end
build = loaded_build.build;
if ~isstruct(build) || numel(build) ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest variable build must be one scalar struct.');
end
if ~isfield(build, 'schema') || ~ischar(build.schema) || ...
        ~strcmp(build.schema, 'pseudo-CT.mlsc-current-build/v1')
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest has an unexpected schema.');
end
if ~isfield(build, 'manifest_version') || ...
        ~isnumeric(build.manifest_version) || ...
        ~isscalar(build.manifest_version) || build.manifest_version ~= 1
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest has an unsupported version.');
end
build_required = {'runner'; 'mcr_root'; 'release'; 'update_minimum'; ...
    'mcr_version'; 'arch'; 'generation'; 'runner_checksum'; ...
    'source_commit'; 'source_provenance_fingerprint'; ...
    'required_outputs'};
for ii = 1:length(build_required)
    if ~isfield(build, build_required{ii})
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Build manifest is missing field %s.', build_required{ii});
    end
end
if ~strcmp(strtrim(build.runner), strtrim(candidate.runner))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'The candidate runner does not match the build manifest.');
end
pinned = mlsc_current_validate('pinned_mcr_root');
if ~strcmp(strtrim(build.mcr_root), pinned) || ...
        ~strcmp(strtrim(candidate.mcr_root), pinned)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'The candidate MCR_ROOT is not the pinned %s.', pinned);
end
actual = mlsc_current_validate('actual_identity', strtrim(candidate.mcr_root));
if ~strcmp(strtrim(build.release), actual.release)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest release is incompatible (expected %s).', ...
        actual.release);
end
if actual.update < build.update_minimum
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest update minimum is not satisfied.');
end
if ~isequal(build.mcr_version, actual.mcr_version) || ...
        ~strcmp(strtrim(build.arch), actual.arch) || ...
        ~strcmp(strtrim(build.generation), actual.generation)
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Build manifest runtime identity is incompatible.');
end
% Recompute every file identity from disk (no caller-supplied hashes).
runner_sum = local_finalize_sha(strtrim(candidate.runner));
exe_sum = local_finalize_sha(strtrim(candidate.build_exe));
build_sum = local_finalize_sha(strtrim(candidate.build_manifest));
resource_sum = local_finalize_sha(strtrim(candidate.resource_manifest));
if ~strcmp(lower(strtrim(build.runner_checksum)), lower(runner_sum))
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Candidate runner identity does not match the build manifest.');
end
native_sums = cell(size(evidence.native_paths));
for ii = 1:numel(evidence.native_paths)
    path_here = evidence.native_paths{ii};
    if ~ischar(path_here) || size(path_here, 1) ~= 1 || ...
            isempty(strtrim(path_here))
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Gate-A native path is invalid.');
    end
    native_sums{ii} = local_finalize_sha(strtrim(path_here)); %#ok<AGROW>
end
% Resource-declared natives must all be covered when declared.
loaded_resources = load(strtrim(candidate.resource_manifest));
if isfield(loaded_resources, 'resources')
    res_check = loaded_resources.resources;
    if isstruct(res_check) && numel(res_check) == 1 && ...
            isfield(res_check, 'native_names') && ...
            iscell(res_check.native_names) && ...
            ~isempty(res_check.native_names)
        for ii = 1:numel(res_check.native_names)
            required_name = res_check.native_names{ii};
            if ~ischar(required_name) || size(required_name, 1) ~= 1
                continue;
            end
            covered = false;
            for jj = 1:numel(evidence.native_names)
                entry = evidence.native_names{jj};
                if ischar(entry) && size(entry, 1) == 1 && ...
                        strcmp(strtrim(entry), strtrim(required_name))
                    covered = true;
                    break;
                end
            end
            if ~covered
                error('pseudo_CT:MLSCCurrentNativeEvidence', ...
                    'Gate-A evidence is missing native %s.', ...
                    strtrim(required_name));
            end
        end
    end
end
gate_a = struct();
gate_a.schema = mlsc_current_validate('gate_a_schema');
gate_a.manifest_version = 1;
gate_a.source_commit = strtrim(build.source_commit);
gate_a.source_provenance_fingerprint = lower( ...
    strtrim(build.source_provenance_fingerprint));
gate_a.mcr_root = pinned;
gate_a.release = strtrim(actual.release);
gate_a.version = strtrim(actual.version);
gate_a.update_minimum = double(build.update_minimum);
gate_a.update_actual = double(actual.update);
gate_a.mcr_version = [double(actual.mcr_version(1)) ...
    double(actual.mcr_version(2))];
gate_a.arch = strtrim(actual.arch);
gate_a.generation = strtrim(actual.generation);
gate_a.runner = strtrim(candidate.runner);
gate_a.runner_checksum = runner_sum;
gate_a.build_exe = strtrim(candidate.build_exe);
gate_a.build_exe_checksum = exe_sum;
gate_a.build_manifest = strtrim(candidate.build_manifest);
gate_a.build_manifest_checksum = build_sum;
gate_a.resource_manifest = strtrim(candidate.resource_manifest);
gate_a.resource_manifest_checksum = resource_sum;
gate_a.native_names = evidence.native_names(:);
gate_a.native_paths = evidence.native_paths(:);
gate_a.native_checksums = native_sums(:);
gate_a.native_results = evidence.native_results(:);
gate_a.launcher_result = 'pass';
gate_a.runtime_lib_result = 'pass';
gate_a.prepare_result = 'pass';
gate_a.compute_result = 'pass';
gate_a.overall_result = 'pass';
save(record_path, 'gate_a');
end

function hex = local_finalize_sha(path_name)
%LOCAL_FINALIZE_SHA SHA-256 content identity, fail-closed (no fallback).
hex = '';
try
    fid = fopen(path_name, 'r');
    if fid == -1
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Gate-A candidate file is unreadable.');
    end
    raw = fread(fid, inf, '*uint8')';
    fclose(fid);
    if isempty(raw)
        error('pseudo_CT:MLSCCurrentManifest', ...
            'Gate-A candidate file is empty.');
    end
    try
        digest = java.security.MessageDigest.getInstance('SHA-256');
        digest.update(raw);
        bytes = typecast(digest.digest(), 'uint8');
        candidate = lower(reshape(dec2hex(bytes, 2)', 1, []));
        if length(candidate) == 64 && ...
                ~isempty(regexp(candidate, '^[0-9a-fA-F]{64}$', 'once'))
            hex = candidate;
            return;
        end
    catch %#ok<CTCH>
    end
    try
        single_quote = char(39);
        double_quote = char(34);
        quoted = single_quote;
        for ii = 1:length(path_name)
            if path_name(ii) == single_quote
                quoted = [quoted single_quote double_quote single_quote ...
                    double_quote single_quote]; %#ok<AGROW>
            else
                quoted = [quoted path_name(ii)]; %#ok<AGROW>
            end
        end
        quoted = [quoted single_quote];
        [status, out] = system(['sha256sum ' quoted ' 2>/dev/null']);
        if status == 0 && ischar(out) && ~isempty(strtrim(out))
            tok = regexp(strtrim(out), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', ...
                'tokens', 'once');
            if ~isempty(tok)
                candidate = lower(strtrim(tok{1}));
                if length(candidate) == 64
                    hex = candidate;
                    return;
                end
            end
        end
    catch %#ok<CTCH>
    end
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A file hashing is unavailable.');
catch ME
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    if strncmp(ME.identifier, 'pseudo_CT:', length('pseudo_CT:'))
        rethrow(ME);
    end
    error('pseudo_CT:MLSCCurrentManifest', ...
        'Gate-A file hashing is unavailable.');
end
end
