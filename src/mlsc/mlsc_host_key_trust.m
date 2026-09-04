function [verifier, host_key_source] = mlsc_host_key_trust(host, port, trusted_material)
%MLSC_HOST_KEY_TRUST Build a strict, in-memory MLSC host-key verifier.
%   [VERIFIER, HOST_KEY_SOURCE] = MLSC_HOST_KEY_TRUST(HOST, PORT, TRUSTED_MATERIAL)
%   resolves an explicitly supplied, independently trusted known_hosts record and
%   returns a bundled Ganymed ch.ethz.ssh2.MLSCStrictHostKeyVerifier bound to an
%   in-memory KnownHosts database for exactly HOST:PORT.  VERIFIER is intended to
%   be handed to Connection.connect(verifier) before any authentication.
%
%   TRUSTED_MATERIAL is a runtime-only trust source.  It may be a function handle
%   that returns the known_hosts text when called, or the known_hosts text itself
%   as a character vector or cell array of lines.  This function never reads it
%   from a profile, a file it writes, the network, or a connection, and it never
%   prints, caches, or persists the material.
%
%   The function fails closed -- without opening any connection -- when the trust
%   source is missing, empty, malformed, or contains no supported (ssh-rsa or
%   ssh-dss) entry naming exactly HOST.  Missing/malformed/unsupported material
%   therefore never reaches authentication, account discovery, or submission; a
%   new, changed, or mismatched key is rejected later by the strict verifier,
%   which accepts only a key reported as KnownHosts.HOSTKEY_IS_OK.
%
%   HOST_KEY_SOURCE is a short, credential-free and key-free label describing the
%   trust provenance (for example 'runtime provider' or 'not supplied'); it never
%   contains key material.
%
%   Minimum supported MATLAB: R2010b.

verifier = [];
host_key_source = 'not supplied';

% --- Validate the pinned target before touching any trust material. ---
if ~ischar(host) || size(host, 1) ~= 1 || isempty(strtrim(host)) || ...
        any(host == char(0)) || ~isempty(regexp(host, '\s', 'once'))
    error('pseudo_CT:MLSCSSH2HostKeyTarget', ...
        'A single non-empty MLSC host-key target hostname is required.');
end
if ~isnumeric(port) || ~isscalar(port) || ~isfinite(port) || ...
        port ~= floor(port) || port < 1 || port > 65535
    error('pseudo_CT:MLSCSSH2HostKeyTarget', ...
        'A valid integer MLSC host-key target port is required.');
end

% --- Resolve the runtime-only trusted material. ---
material = [];
if isa(trusted_material, 'function_handle')
    host_key_source = 'runtime provider';
    material = feval(trusted_material);
elseif ischar(trusted_material) || iscell(trusted_material)
    host_key_source = 'runtime text';
    material = trusted_material;
end

text = local_known_hosts_text(material);
if isempty(text)
    error('pseudo_CT:MLSCSSH2HostKeyMissing', ...
        ['No independently trusted MLSC host-key material was supplied at ', ...
         'runtime; refusing to connect, authenticate, discover accounts, or ', ...
         'submit.']);
end

% --- Require at least one supported entry naming exactly this host. ---
if ~local_has_supported_entry(text, host)
    error('pseudo_CT:MLSCSSH2HostKeyUnsupported', ...
        ['The supplied MLSC host-key material has no supported (ssh-rsa or ', ...
         'ssh-dss) entry for the pinned host; refusing to connect.']);
end

% --- Load the bundled Ganymed classes without any network access. ---
local_ensure_ganymed();

% --- Build the in-memory database (char[] constructor only: never a File). ---
try
    char_data = local_to_java_chars(text);
    known_hosts = ch.ethz.ssh2.KnownHosts(char_data);
catch ME
    error('pseudo_CT:MLSCSSH2HostKeyMalformed', ...
        'The supplied MLSC host-key material could not be parsed; refusing to connect. (%s)', ...
        ME.message);
end

% --- Bind a strict verifier to the exact pinned host and port. ---
try
    verifier = ch.ethz.ssh2.MLSCStrictHostKeyVerifier( ...
        known_hosts, java.lang.String(host), port);
catch ME
    error('pseudo_CT:MLSCSSH2HostKeyMalformed', ...
        'The MLSC strict host-key verifier could not be created; refusing to connect. (%s)', ...
        ME.message);
end
end

function text = local_known_hosts_text(material)
text = '';
if isempty(material)
    return;
end
if iscell(material)
    parts = {};
    for ii = 1:numel(material)
        if ~ischar(material{ii})
            return;
        end
        parts{end + 1} = material{ii}; %#ok<AGROW>
    end
    material = char(parts);
end
if ~ischar(material)
    return;
end
% Collapse a multi-row char matrix into newline-separated single-line text.
lines = cellstr(material);
lines = lines(:);
joined = '';
for ii = 1:length(lines)
    joined = [joined char(lines{ii}) char(10)]; %#ok<AGROW>
end
if isempty(strtrim(joined))
    return;
end
text = joined;
end

function present = local_has_supported_entry(text, host)
present = false;
lines = regexp(text, '\r\n|\n|\r', 'split');
for ii = 1:length(lines)
    line = strtrim(lines{ii});
    if isempty(line) || line(1) == '#'
        continue;
    end
    fields = regexp(line, '\s+', 'split');
    if length(fields) < 3
        continue;
    end
    algorithm = fields{2};
    if ~strcmp(algorithm, 'ssh-rsa') && ~strcmp(algorithm, 'ssh-dss')
        continue;
    end
    if isempty(fields{3})
        continue;
    end
    % A hashed host pattern (|1|...) or an explicit hostname list may name the
    % pinned host; accept either so the strict verifier can do the real match.
    patterns = strsplit_simple(fields{1}, ',');
    for kk = 1:length(patterns)
        pattern = patterns{kk};
        if numel(pattern) >= 3 && strcmp(pattern(1:3), '|1|')
            present = true;
            return;
        end
        if ~isempty(pattern) && pattern(1) == '@'
            continue;
        end
        if strcmpi(pattern, host)
            present = true;
            return;
        end
    end
end
end

function tokens = strsplit_simple(value, delimiter)
tokens = {};
start_index = 1;
for ii = 1:length(value)
    if value(ii) == delimiter
        tokens{end + 1} = value(start_index:ii - 1); %#ok<AGROW>
        start_index = ii + 1;
    end
end
tokens{end + 1} = value(start_index:end);
end

function local_ensure_ganymed()
if exist('ch.ethz.ssh2.KnownHosts', 'class') == 8
    return;
end
setup_file = which('ssh2_setup');
if isempty(setup_file)
    error('pseudo_CT:MLSCSSH2Library', ...
        'The bundled MATLAB SSH2 support could not be located.');
end
ssh2_base_dir = fileparts(setup_file);
jar_path = fullfile(ssh2_base_dir, 'ganymed-ssh2-m1', 'ganymed-ssh2-m1.jar');
if exist(jar_path, 'file') ~= 2
    error('pseudo_CT:MLSCSSH2Library', ...
        'The bundled Ganymed SSH2 library is unavailable.');
end
javaaddpath(jar_path);
if exist('ch.ethz.ssh2.KnownHosts', 'class') ~= 8
    error('pseudo_CT:MLSCSSH2Library', ...
        'The bundled Ganymed SSH2 library could not be loaded.');
end
end

function char_data = local_to_java_chars(text)
% Convert MATLAB text to a Java char[] for the in-memory KnownHosts database.
text_array = java.lang.String(text);
char_data = text_array.toCharArray();
end
