function hex = mlsc_release_gate(action, path_text)
%MLSC_RELEASE_GATE SHA-256 content hash of one file.
%   HEX = MLSC_RELEASE_GATE('sha256_file', PATH) returns the lowercase SHA-256 of
%   PATH. The Java digest is used where a JVM exists; otherwise (the compiled
%   standalone disables Java) sha256sum is used. A missing or unhashable file
%   raises an error; there is no size or time fallback. This is the only
%   release-gate action that remains: the source-release tooling it once served
%   was replaced by scripts/release_application.py.
%   Minimum supported MATLAB: R2010b.

if nargin ~= 2 || ~ischar(action) || ~strcmp(action, 'sha256_file')
    error('pseudo_CT:MLSCReleaseGate', 'Unknown release-gate action.');
end
hex = local_sha256_file(path_text);
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

function flag = local_is_valid_sha256(value)
flag = ischar(value) && size(value, 1) == 1 && ...
    ~isempty(regexp(value, '^[0-9a-fA-F]{64}$', 'once'));
end

function quoted = local_shell_quote(value)
quote = char(39);
quoted = [quote strrep(value, quote, [quote char(92) quote quote]) quote];
end
