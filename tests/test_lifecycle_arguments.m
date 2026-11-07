function test_lifecycle_arguments()
%TEST_LIFECYCLE_ARGUMENTS Submit's forwarded arguments must parse on every path.
%   The compiled (deployed) submit forwards the argument list built in
%   pseudo_CT_orchestrate's local_submit. Both the source and deployed paths of
%   pseudo_CT_run_lifecycle use pseudo_CT_lifecycle_arguments, so this offline
%   check covers the deployed acceptance without running science.

root_dir = fileparts(fileparts(mfilename('fullpath')));
old_path = path();
addpath(genpath(fullfile(root_dir, 'src')), '-begin');
cleanup = onCleanup(@() path(old_path)); %#ok<NASGU>

for cleanup_value = [false true]
    % A resolved job with every option field validate records (Option A values
    % and the default cleanup), as local_submit receives it.
    options = struct('correct_aliasing', false, ...
        'recenter_before_normalization', false, ...
        'cleanup_on_success', cleanup_value);
    resolved = struct('profile', 'local', ...
        'subjects', struct('mprage_fn', {'/synthetic/MR/MPRAGE/a.dcm'}, ...
            'umap_fn', {'/synthetic/MR/UMAP/u.dcm'}), ...
        'options', options, 'current_artifact_root', '');

    % Exact argument list local_submit forwards (see pseudo_CT_orchestrate.m).
    umaps = {resolved.subjects.umap_fn};
    args = {'profile', resolved.profile, ...
        'subjects', {resolved.subjects.mprage_fn}, ...
        'umap_files', umaps, 'resolved_jobs', resolved.subjects, ...
        'headless_mode', false, 'headless_credentials', struct(), ...
        'group_account', '', 'mlsc_host_key_provider', []};
    if isfield(resolved.options, 'cleanup_on_success')
        args = [args {'cleanup_on_success', resolved.options.cleanup_on_success}];
    end

    parsed = pseudo_CT_lifecycle_arguments(args{:});
    assert(strcmp(parsed.profile, 'local'));
    assert(isequal(parsed.umap_files, umaps));
    assert(isequal(parsed.resolved_jobs, resolved.subjects));
    assert(islogical(parsed.cleanup_on_success) && ...
        parsed.cleanup_on_success == cleanup_value, ...
        'The submitted cleanup_on_success must reach the lifecycle unchanged.');
end

% The parser is strict: an unlisted name is still rejected.
raised = '';
try
    pseudo_CT_lifecycle_arguments('profile', 'local', 'bogus_option', 1);
catch ME
    raised = ME.identifier;
end
assert(strcmp(raised, 'MATLAB:InputParser:UnmatchedParameter'), ...
    sprintf('An unlisted name must be rejected, got [%s].', raised));

% Both lifecycle paths must use the one shared definition (no private parser),
% and the deployed branch must return the cleanup value to the caller.
text = local_read(fullfile(root_dir, 'src', 'orchestration', 'pseudo_CT_run_lifecycle.m'));
assert(isempty(strfind(text, 'p = inputParser;')), ...
    'The lifecycle must not keep a private argument parser.');
assert(numel(strfind(text, 'pseudo_CT_lifecycle_arguments(varargin{:})')) == 2, ...
    'Both lifecycle paths must parse through pseudo_CT_lifecycle_arguments.');
assert(numel(strfind(text, 'cleanup_on_success_arg] = ...')) == 2, ...
    'The deployed signature and its caller must carry cleanup_on_success_arg.');

% Compiled stderr: one preformatted %s per line (a literal before %s loses the value).
headless_text = local_read(fullfile(root_dir, 'src', 'api', 'pseudo_CT_headless.m'));
assert(~isempty(strfind(headless_text, 'fprintf(2, ''%s\n'', [''pseudoct-headless: '' diag{kk}])')), ...
    'The headless diagnostics must print one preformatted line per message.');

fprintf('Lifecycle submit argument contract checks passed.\n');
end

function text = local_read(path_text)
fid = fopen(path_text, 'r');
if fid == -1
    error('test_lifecycle_arguments:Read', 'Cannot read %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
text = fscanf(fid, '%c');
end
