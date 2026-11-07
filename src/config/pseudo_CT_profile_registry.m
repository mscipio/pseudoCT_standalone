function out = pseudo_CT_profile_registry(action, arg)
%PSEUDO_CT_PROFILE_REGISTRY Canonical profile keys, configurations and identity.
%   KEYS = PSEUDO_CT_PROFILE_REGISTRY('keys') returns the four canonical
%   hyphenated profile keys in registry order as a cell column.
%
%   CONFIG = PSEUDO_CT_PROFILE_REGISTRY('invoke', KEY) calls the profile function
%   for KEY through direct callable references. One mechanism serves source
%   checkouts (the profile files are on the path) and compiled distributions
%   (build_application compiles them in). Underscore spellings and display
%   labels are rejected.
%
%   IDENTITY = PSEUDO_CT_PROFILE_REGISTRY('identity', KEY) returns profile_key,
%   profile_identity_source ('effective-config') and profile_sha256: the SHA-256
%   of the canonical text of the effective configuration. Any changed setting
%   changes the identity in both modes; comment-only edits do not.
%
%   HASH = PSEUDO_CT_PROFILE_REGISTRY('config_hash', CONFIG) hashes one
%   configuration struct the same way.
%   Minimum supported MATLAB: R2010b.

if nargin < 1 || ~ischar(action)
    error('pseudo_CT:ProfileRegistry', 'A profile registry action is required.');
end
switch action
    case 'keys'
        out = {'local'; 'local-mprage-only'; 'mlsc'; 'mlsc-mprage-only'};
    case 'invoke'
        key = local_require_key(arg);
        switch key
            case 'local'
                out = local();
            case 'mlsc'
                out = mlsc();
            case 'local-mprage-only'
                out = local_mprage_only();
            otherwise
                out = mlsc_mprage_only();
        end
    case 'identity'
        key = local_require_key(arg);
        config = pseudo_CT_profile_registry('invoke', key);
        out = struct('profile_key', key, ...
            'profile_identity_source', 'effective-config', ...
            'profile_sha256', local_config_hash(config));
    case 'config_hash'
        out = local_config_hash(arg);
    otherwise
        error('pseudo_CT:ProfileRegistry', 'Unknown profile registry action.');
end
end

function key = local_require_key(key)
%LOCAL_REQUIRE_KEY Exact canonical key among the four profiles.
if ~ischar(key) || size(key, 1) ~= 1 || ~any(strcmp(key, ...
        {'local'; 'mlsc'; 'local-mprage-only'; 'mlsc-mprage-only'}))
    error('pseudo_CT:InvalidProfile', 'Unknown profile: %s', local_text(key));
end
end

function hash = local_config_hash(config)
%LOCAL_CONFIG_HASH SHA-256 of the canonical text of one configuration struct.
text = local_canonical(config);
path_name = [tempname '.txt'];
fid = fopen(path_name, 'w');
if fid == -1
    error('pseudo_CT:OrchestrationArtifact', ...
        'A profile identity could not be computed.');
end
cleanup_file = onCleanup(@() local_delete(path_name)); %#ok<NASGU>
fprintf(fid, '%s', text);
fclose(fid);
try
    hash = mlsc_release_gate('sha256_file', path_name);
catch ME
    error('pseudo_CT:OrchestrationArtifact', ...
        'A profile identity could not be computed: %s', ME.message);
end
if ~ischar(hash) || isempty(hash)
    error('pseudo_CT:OrchestrationArtifact', 'A profile identity could not be computed.');
end
end

function text = local_canonical(value)
%LOCAL_CANONICAL ASCII, order-independent text of a value (fields sorted,
%   numbers and characters as code points, so encoding cannot change it).
size_text = sprintf('%dx', size(value));
if isstruct(value)
    text = ['struct' size_text '{'];
    for ii = 1:numel(value)
        names = sort(fieldnames(value(ii)));
        for jj = 1:numel(names)
            text = [text names{jj} '=' local_canonical(value(ii).(names{jj})) ';']; %#ok<AGROW>
        end
        text = [text '|']; %#ok<AGROW>
    end
    text = [text '}'];
elseif iscell(value)
    text = ['cell' size_text '{'];
    for ii = 1:numel(value)
        text = [text local_canonical(value{ii}) ',']; %#ok<AGROW>
    end
    text = [text '}'];
elseif ischar(value)
    text = ['char' size_text ':' sprintf('%d.', double(value))];
elseif islogical(value)
    text = ['logical' size_text ':' sprintf('%d.', double(value(:)))];
elseif isnumeric(value)
    text = ['num' class(value) size_text ':' sprintf('%.17g.', double(value(:)))];
elseif isa(value, 'function_handle')
    text = ['fh:' func2str(value)];
else
    text = ['class:' class(value)];
end
end

function text = local_text(value)
if ischar(value)
    text = value;
else
    text = '<non-text>';
end
end

function local_delete(path_name)
if exist(path_name, 'file') == 2
    delete(path_name);
end
end
