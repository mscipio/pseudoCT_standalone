function status = pseudoct_standalone(varargin)
%PSEUDOCT_STANDALONE Compiled dispatcher for standalone CLI and headless runs.
%   STATUS = PSEUDOCT_STANDALONE(MODE) is the single standalone compile target
%   (built by scripts/build_application.m into standalone/pseudoct_standalone).
%   It only delegates; no serialization or validation is duplicated here:
%     prepare_validate, prepare_submit, verify_result, store_credentials
%         -> PSEUDOCT_CLI_BRIDGE(MODE), operations read from the environment.
%     headless
%         -> PSEUDOCT_HEADLESS_CLI(), which reads PSEUDOCT_REQUEST_MAT and
%            PSEUDOCT_RESULT_MAT and calls PSEUDO_CT_HEADLESS(request, result).
%   STATUS = PSEUDOCT_STANDALONE('orchestrate', REQUEST_MAT, REPORT_MAT)
%         -> loads the cell array ARGUMENTS from REQUEST_MAT, calls
%            PSEUDO_CT_ORCHESTRATE('run', struct('arguments', {ARGUMENTS})),
%            saves the result as variable REPORT into REPORT_MAT (-v6) and
%            returns 0. Any error is printed to stderr and returns 70; no
%            report is written then.
%   STATUS = PSEUDOCT_STANDALONE('package-manifests', PAYLOAD_DIR, RESOURCES_DIR, OUTPUT_DIR)
%         -> writes OUTPUT_DIR/build_manifest.mat and resource_manifest.mat
%            (OUTPUT_DIR must be <package>/runtimes/<LABEL>/payload; RESOURCES_DIR
%            must be <package>/resources; the MCR version comes from
%            PSEUDOCT_RUNTIME_MCR_VERSION; see local_package_manifests).
%   Any other mode, or a missing or extra argument, returns 70 before any
%   dispatch. No path setup is performed: the runtime is compiled in by mcc
%   (-I over src/ plus automatic dependency analysis), so repository src/ is
%   never put on the path.
%   When called as a compiled main (nargout == 0) STATUS becomes the process
%   exit code, as bin/pseudoct expects. Outside the compiled build, call with an
%   output: a bare call would exit the MATLAB session.
%   Minimum supported MATLAB: R2010b.

status = 70;
try
    if nargin == 4 && ischar(varargin{1}) && ...
            strcmp(varargin{1}, 'package-manifests')
        status = local_package_manifests(varargin{2}, varargin{3}, varargin{4});
    elseif nargin == 3 && ischar(varargin{1}) && ...
            strcmp(varargin{1}, 'orchestrate')
        status = local_orchestrate(varargin{2}, varargin{3});
    elseif nargin ~= 1 || ~ischar(varargin{1})
        fprintf(2, 'pseudoct: standalone dispatch requires exactly one mode.\n');
    elseif strcmp(varargin{1}, 'headless')
        status = pseudoct_headless_cli();
    elseif any(strcmp(varargin{1}, {'prepare_validate'; 'prepare_submit'; ...
            'verify_result'; 'store_credentials'}))
        status = pseudoct_cli_bridge(varargin{1});
    else
        fprintf(2, 'pseudoct: unknown standalone operation.\n');
    end
catch
    % Do not expose exception text or paths; the launcher maps 70 to runtime.
    fprintf(2, 'pseudoct: standalone dispatch failed.\n');
    status = 70;
end
if ~isnumeric(status) || ~isscalar(status)
    status = 70;
end
if nargout == 0
    exit(status);
end
end

function status = local_orchestrate(request_path, report_path)
%LOCAL_ORCHESTRATE Run one orchestrate request and save its report MAT.
%   Errors are reported on stderr and mapped to 70; the report file is only
%   written after a successful run.
status = 70;
try
    if ~ischar(request_path) || ~ischar(report_path)
        error('pseudoct:orchestrate', 'Request and report paths are required.');
    end
    loaded = load(request_path, 'arguments');
    if ~isfield(loaded, 'arguments') || ~iscell(loaded.arguments)
        error('pseudoct:orchestrate', ...
            'The orchestrate request must contain a cell array ARGUMENTS.');
    end
    % An empty request would make the lifecycle open the interactive selector.
    % Reject it here, before pseudo_CT_orchestrate is called.
    if isempty(loaded.arguments)
        error('pseudoct:orchestrate', ...
            'The orchestrate request has no run arguments; refusing an interactive run.');
    end
    report = pseudo_CT_orchestrate('run', ...
        struct('arguments', {loaded.arguments}));
    save(report_path, 'report', '-v6');
    status = 0;
catch ME
    fprintf(2, 'pseudoct: orchestrate failed: %s\n', ME.message);
    status = 70;
end
end

function status = local_package_manifests(payload_dir, resources_dir, output_dir)
%LOCAL_PACKAGE_MANIFESTS Publish one release's MLSC build and resource manifests.
%   PAYLOAD_DIR holds run_mlsc_current_payload.sh and mlsc_current_payload.
%   RESOURCES_DIR must be exactly <package>/resources.
%   OUTPUT_DIR must be <package>/runtimes/<LABEL>/payload: LABEL becomes the
%   build release. The MCR version is read from PSEUDOCT_RUNTIME_MCR_VERSION
%   (catalog value such as 7.14 or 9.7), never from MATLAB's version().
%   Stored paths are relocatable: the runner is recorded by basename, and
%   resources.atlas_dir is relative to the manifest folder
%   ('../../../resources'; worked example: manifest
%   /pkg/runtimes/R2019b/payload/resource_manifest.mat resolves to
%   /pkg/resources).
%   Both files are built in a stage directory inside OUTPUT_DIR, then published
%   with rollback: on failure either both previous files or both new files
%   remain. Returns 0 on success, 70 on failure (message on stderr).
status = 70;
stage_dir = '';
stage_retained = false;
try
    if ~isdeployed
        error('pseudoct:packageManifests', ...
            'Manifests are written only by the compiled release dispatcher.');
    end
    local_require_absolute_path(payload_dir, 'dir');
    local_require_absolute_path(resources_dir, 'dir');
    local_require_absolute_path(output_dir, 'dir');
    [release_dir, leaf] = fileparts(output_dir);
    [runtimes_dir, release] = fileparts(release_dir);
    [~, runtimes_name] = fileparts(runtimes_dir);
    if ~strcmp(leaf, 'payload') || ~strcmp(runtimes_name, 'runtimes') || ...
            isempty(regexp(release, '^[A-Za-z0-9]+$', 'once'))
        error('pseudoct:packageManifests', ...
            'Output directory must be <package>/runtimes/<LABEL>/payload.');
    end
    % The payload compares the manifest atlas_dir with the installed atlas root
    % (pseudo_CT_dependency_paths: <PSEUDOCT_INSTALL_ROOT>/resources). The
    % manifest folder is <package>/runtimes/<LABEL>/payload, three levels below
    % the package root, so the recorded relative value is '../../../resources':
    % payload -> <LABEL> -> runtimes -> <package>, then resources.
    package_root = local_strip_trailing(fileparts(runtimes_dir));
    if ~strcmp(local_strip_trailing(resources_dir), ...
            fullfile(package_root, 'resources'))
        error('pseudoct:packageManifests', ...
            'Resources directory must be <package>/resources.');
    end
    atlas_dir_relative = '../../../resources';

    % MCR identity: the launcher's catalog value, validated before any write.
    mcr_text = strtrim(getenv('PSEUDOCT_RUNTIME_MCR_VERSION'));
    if isempty(regexp(mcr_text, '^[0-9]+\.[0-9]+$', 'once'))
        error('pseudoct:packageManifests', ...
            'PSEUDOCT_RUNTIME_MCR_VERSION must be a release MCR version (M.m).');
    end
    numbers = sscanf(mcr_text, '%d.%d')';

    runner = fullfile(payload_dir, 'run_mlsc_current_payload.sh');
    binary = fullfile(payload_dir, 'mlsc_current_payload');
    local_require_absolute_path(runner, 'file');
    local_require_absolute_path(binary, 'file');
    runner_sha = mlsc_current_validate('sha256_file', runner);
    binary_sha = mlsc_current_validate('sha256_file', binary);
    if isempty(runner_sha) || isempty(binary_sha)
        error('pseudoct:packageManifests', 'Content hashing is unavailable.');
    end
    binary_info = dir(binary);

    build = struct();
    build.schema = 'pseudo-CT.mlsc-current-build/v1';
    build.manifest_version = 1;
    % Basename only: the validator binds the runner by name plus SHA-256.
    build.runner = 'run_mlsc_current_payload.sh';
    build.runner_checksum = runner_sha;
    build.payload_binary = 'mlsc_current_payload';
    build.payload_bytes = binary_info(1).bytes;
    build.payload_sha256 = binary_sha;
    % Installed mode does not bind a build-machine MCR path (see validator).
    build.mcr_root = '';
    build.release = release;
    build.update_minimum = 0;
    build.mcr_version = numbers;
    build.arch = 'glnxa64';
    build.generation = mcr_text;
    build.source_commit = 'packaged-payload';
    build.source_provenance_fingerprint = binary_sha;
    build.required_outputs = {'att_map.nii'; ...
        'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};

    listing = dir(resources_dir);
    names = {};
    for ii = 1:length(listing)
        if ~listing(ii).isdir && listing(ii).name(1) ~= '.'
            names{end + 1, 1} = listing(ii).name; %#ok<AGROW>
        end
    end
    if isempty(names)
        error('pseudoct:packageManifests', 'No resource files were found.');
    end
    names = sort(names);
    resource_bytes = zeros(length(names), 1);
    resource_sha = cell(length(names), 1);
    for ii = 1:length(names)
        path_here = fullfile(resources_dir, names{ii});
        info = dir(path_here);
        resource_bytes(ii) = info(1).bytes;
        resource_sha{ii} = mlsc_current_validate('sha256_file', path_here);
        if isempty(resource_sha{ii})
            error('pseudoct:packageManifests', 'Content hashing is unavailable.');
        end
    end
    atlas_hits = regexp(names, 'Atlas.*\.nii$', 'once');
    atlas_list = names(~cellfun('isempty', atlas_hits));
    if isempty(atlas_list)
        error('pseudoct:packageManifests', 'No *Atlas*.nii resources were found.');
    end

    resources = struct();
    resources.schema = 'pseudo-CT.mlsc-current-resources/v1';
    resources.manifest_version = 1;
    resources.atlas_dir = atlas_dir_relative;
    resources.atlas_list = atlas_list;
    resources.resource_names = names;
    resources.resource_bytes = resource_bytes;
    resources.resource_sha256 = resource_sha;

    % Stage both files inside OUTPUT_DIR, then publish them with rollback.
    stage_dir = local_make_stage_dir(output_dir);
    stage_files = {fullfile(stage_dir, 'build_manifest.mat'); ...
        fullfile(stage_dir, 'resource_manifest.mat')};
    save(stage_files{1}, 'build', '-v6');
    save(stage_files{2}, 'resources', '-v6');
    dest_files = {fullfile(output_dir, 'build_manifest.mat'); ...
        fullfile(output_dir, 'resource_manifest.mat')};
    [message, stage_retained] = local_publish_manifests(stage_dir, ...
        stage_files, dest_files);
    if ~isempty(message)
        error('pseudoct:packageManifests', '%s', message);
    end
    status = 0;
catch ME
    fprintf(2, 'pseudoct: package-manifests failed: %s\n', ME.message);
    status = 70;
end
if ~isempty(stage_dir) && exist(stage_dir, 'dir') == 7 && ~stage_retained
    local_remove_stage(stage_dir);
end
end

function [message, retained] = local_publish_manifests(stage_dir, stage_files, dest_files)
%LOCAL_PUBLISH_MANIFESTS Move staged files into place; roll back on failure.
%   Pre-existing destinations are displaced into STAGE_DIR first. On any
%   failure, files published by this call are deleted and displaced files are
%   moved back. MESSAGE is empty on success. RETAINED is true only when a
%   displaced file could not be restored; the stage directory is then kept.
message = '';
retained = false;
displaced = {};
published = {};
try
    for ii = 1:length(dest_files)
        if exist(dest_files{ii}, 'file') == 2
            backup = fullfile(stage_dir, sprintf('previous-%d.mat', ii));
            movefile(dest_files{ii}, backup, 'f');
            displaced{end + 1} = {dest_files{ii}, backup}; %#ok<AGROW>
        end
        movefile(stage_files{ii}, dest_files{ii}, 'f');
        published{end + 1} = dest_files{ii}; %#ok<AGROW>
    end
catch ME
    message = ME.message;
    for ii = length(published):-1:1
        if exist(published{ii}, 'file') == 2
            delete(published{ii});
        end
    end
    for ii = length(displaced):-1:1
        try
            movefile(displaced{ii}{2}, displaced{ii}{1}, 'f');
        catch %#ok<CTCH>
            retained = true;
        end
    end
    if retained
        message = [message ' Previous manifests could not be restored; ' ...
            'they remain in ' stage_dir '.'];
    end
end
end

function stage_dir = local_make_stage_dir(output_dir)
%LOCAL_MAKE_STAGE_DIR Create a new hidden stage directory inside OUTPUT_DIR.
stage_dir = '';
for kk = 1:10000
    name = sprintf('.manifest-stage-%04d', kk);
    candidate = fullfile(output_dir, name);
    if exist(candidate, 'dir') == 7 || exist(candidate, 'file') == 2
        continue;
    end
    [ok, ~] = mkdir(output_dir, name);
    if ok
        stage_dir = candidate;
        return;
    end
end
error('pseudoct:packageManifests', 'No stage directory could be created.');
end

function local_remove_stage(stage_dir)
%LOCAL_REMOVE_STAGE Delete the files of a stage directory and the directory.
listing = dir(stage_dir);
for ii = 1:length(listing)
    if ~listing(ii).isdir
        delete(fullfile(stage_dir, listing(ii).name));
    end
end
rmdir(stage_dir);
end

function text = local_strip_trailing(text)
%LOCAL_STRIP_TRAILING Remove trailing '/' characters (keeps a lone root '/').
while length(text) > 1 && text(end) == '/'
    text(end) = '';
end
end

function local_require_absolute_path(path_text, kind)
%LOCAL_REQUIRE_ABSOLUTE_PATH Absolute existing file or directory, else error.
if ~ischar(path_text) || size(path_text, 1) ~= 1 || isempty(path_text) || ...
        path_text(1) ~= '/' || any(path_text == char(0))
    error('pseudoct:packageManifests', 'Manifest paths must be absolute.');
end
if strcmp(kind, 'dir')
    found = exist(path_text, 'dir') == 7;
else
    found = exist(path_text, 'file') == 2;
end
if ~found
    error('pseudoct:packageManifests', ...
        'A required manifest input is missing.');
end
end
