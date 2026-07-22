function record = pseudo_CT_provenance_record(tree_dir, record_path)
%PSEUDO_CT_PROVENANCE_RECORD Load or validate an SPM provenance record.
%   RECORD = PSEUDO_CT_PROVENANCE_RECORD(TREE_DIR, RECORD_PATH) requires
%   the inventory and checksum records to exist together.  Every current
%   regular file in the scoped tree must appear in the canonical checksum
%   list, and every listed digest must match before a record is returned.
%
%   When TREE_DIR is omitted or empty, an empty record template is returned.
%   r4667 records remain apply-blocked until their vendor tree is materialized.
%
%   Minimum supported MATLAB: R2010b.

ids = pseudo_CT_error_ids();

record = empty_record();

if nargin < 1 || isempty(tree_dir)
    return;
end

if nargin < 2 || isempty(record_path)
    record_path = fullfile(tree_dir, 'INVENTORY.json');
end

if exist(record_path, 'file') ~= 2
    error(ids.PROVENANCE.RecordMissing, ...
          'Provenance record missing for %s: %s', tree_dir, record_path);
end

inventory_path = fullfile(tree_dir, 'INVENTORY.json');
if exist(inventory_path, 'file') ~= 2
    error(ids.PROVENANCE.InventoryMissing, ...
          'Provenance inventory missing for %s: %s', tree_dir, inventory_path);
end

record.record_path = record_path;
record.tree_inventory = inventory_path;

[~, tree_name] = fileparts(tree_dir);
if strcmp(tree_name, 'spm8-r6313')
    record.expected_spm_version = 'r6313';
elseif strcmp(tree_name, 'spm8-r4667')
    record.expected_spm_version = 'r4667';
else
    record.expected_spm_version = tree_name;
end

checksums_path = fullfile(tree_dir, 'CHECKSUMS.sha256');
if exist(checksums_path, 'file') ~= 2
    error(ids.PROVENANCE.RecordMissing, ...
          'Provenance checksums missing for %s: %s', tree_dir, checksums_path);
end

[record.sha256_map, record.sha256_paths] = read_checksums(checksums_path, ids);
verify_scope(tree_dir, record.sha256_paths, ids);
verify_checksums(tree_dir, record.sha256_map, record.sha256_paths, ids);
record.file_count = length(record.sha256_paths);
record.bytes = scoped_bytes(tree_dir, record.sha256_paths, ids);
validate_inventory(inventory_path, tree_name, record.file_count, record.bytes, ...
                   file_sha256(checksums_path), ids);

end

%% ------------------------------------------------------------------------
function record = empty_record()

record = struct();
record.source   = '';
record.license  = '';
record.tree_inventory = '';
record.file_count = 0;
record.bytes    = 0;
record.expected_spm_version = '';
record.sha256_map = struct();
record.sha256_paths = {};
record.record_path = '';

end

%% ------------------------------------------------------------------------
function [map, paths] = read_checksums(path, ids)

map = struct();
paths = {};
fid = fopen(path, 'r');
if fid == -1
    error(ids.PROVENANCE.RecordMissing, 'Cannot open checksums: %s', path);
end
cleanup = onCleanup(@() fclose(fid));

while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    line = strtrim(line);
    if isempty(line)
        continue;
    end
    parts = strsplit(line);
    if length(parts) ~= 2 || isempty(regexp(parts{1}, '^[0-9a-fA-F]{64}$', 'once'))
        error(ids.PROVENANCE.ChecksumMismatch, 'Malformed checksum line: %s', line);
    end
    hash = parts{1};
    relpath = parts{2};
    validate_relative_path(relpath, ids);
    field = sanitize_fieldname(relpath);
    if isfield(map, field)
        error(ids.PROVENANCE.ChecksumMismatch, 'Duplicate checksum path: %s', relpath);
    end
    map.(field) = hash;
    paths{end+1} = relpath; %#ok<AGROW>
end

if isempty(paths) || ~isequal(paths, sort(paths))
    error(ids.PROVENANCE.ChecksumMismatch, 'Checksum paths are not canonically ordered.');
end

end

%% ------------------------------------------------------------------------
function verify_scope(tree_dir, listed_paths, ids)

actual_paths = collect_scope_files(tree_dir, tree_dir, ids);
if ~isequal(actual_paths, sort(listed_paths))
    error(ids.PROVENANCE.ChecksumMismatch, ...
          'Checksum scope does not match files below %s.', tree_dir);
end

end

%% ------------------------------------------------------------------------
function paths = collect_scope_files(root_dir, current_dir, ids)

paths = {};
entries = dir(current_dir);
for ii = 1:length(entries)
    name = entries(ii).name;
    if strcmp(name, '.') || strcmp(name, '..')
        continue;
    end
    full_path = fullfile(current_dir, name);
    relpath = relative_path(root_dir, full_path, ids);
    if is_excluded_path(relpath)
        continue;
    end
    if entries(ii).isdir
        nested = collect_scope_files(root_dir, full_path, ids);
        paths = [paths nested]; %#ok<AGROW>
    else
        paths{end+1} = relpath; %#ok<AGROW>
    end
end
paths = sort(paths);

end

%% ------------------------------------------------------------------------
function bytes = scoped_bytes(tree_dir, paths, ids)

bytes = 0;
for ii = 1:length(paths)
    full_path = fullfile(tree_dir, paths{ii});
    info = dir(full_path);
    if isempty(info) || info(1).isdir
        error(ids.PROVENANCE.ChecksumMismatch, 'Missing scoped file: %s', paths{ii});
    end
    bytes = bytes + info(1).bytes;
end

end

%% ------------------------------------------------------------------------
function verify_checksums(tree_dir, map, paths, ids)

for ii = 1:length(paths)
    relpath = paths{ii};
    expected = map.(sanitize_fieldname(relpath));
    full_path = fullfile(tree_dir, relpath);
    if exist(full_path, 'file') ~= 2
        error(ids.PROVENANCE.ChecksumMismatch, ...
              'Provenance inventory lists missing file: %s', full_path);
    end
    actual = file_sha256(full_path);
    if isempty(actual) || ~strcmpi(actual, expected)
        error(ids.PROVENANCE.ChecksumMismatch, ...
              'Checksum mismatch for %s', full_path);
    end
end

end

%% ------------------------------------------------------------------------
function validate_inventory(path, tree_name, file_count, bytes, aggregate, ids)

text = read_text(path, ids);
if isempty(strfind(text, '"schema": "pseudo-CT.spm-provenance/v1"')) || ...
   isempty(strfind(text, '"schema_version": 1')) || ...
   isempty(strfind(text, ['"root": "' tree_name '"'])) || ...
   isempty(strfind(text, ['"revision": "' expected_revision(tree_name) '"']))
    error(ids.PROVENANCE.ChecksumMismatch, 'Malformed provenance inventory: %s', path);
end

count_token = regexp(text, '"file_count":\s*([0-9]+)', 'tokens', 'once');
bytes_token = regexp(text, '"total_bytes":\s*([0-9]+)', 'tokens', 'once');
digest_token = regexp(text, '"aggregate_sha256":\s*"([0-9a-fA-F]{64})"', 'tokens', 'once');
if isempty(count_token) || isempty(bytes_token) || isempty(digest_token) || ...
   str2double(count_token{1}) ~= file_count || ...
   str2double(bytes_token{1}) ~= bytes || ~strcmpi(digest_token{1}, aggregate)
    error(ids.PROVENANCE.ChecksumMismatch, 'Inventory binding mismatch: %s', path);
end

end

%% ------------------------------------------------------------------------
function revision = expected_revision(tree_name)

if strcmp(tree_name, 'spm8-r6313')
    revision = 'r6313';
elseif strcmp(tree_name, 'spm8-r4667')
    revision = 'r4667';
else
    revision = tree_name;
end

end

%% ------------------------------------------------------------------------
function text = read_text(path, ids)

fid = fopen(path, 'r');
if fid == -1
    error(ids.PROVENANCE.InventoryMissing, 'Cannot open inventory: %s', path);
end
cleanup = onCleanup(@() fclose(fid));
text = fread(fid, inf, '*char')';

end

%% ------------------------------------------------------------------------
function validate_relative_path(relpath, ids)

if isempty(relpath) || relpath(1) == '/' || ~isempty(strfind(relpath, '\'))
    error(ids.PROVENANCE.ChecksumMismatch, 'Unsafe checksum path: %s', relpath);
end
parts = regexp(relpath, '/', 'split');
for ii = 1:length(parts)
    if isempty(parts{ii}) || strcmp(parts{ii}, '.') || strcmp(parts{ii}, '..')
        error(ids.PROVENANCE.ChecksumMismatch, 'Unsafe checksum path: %s', relpath);
    end
end

end

%% ------------------------------------------------------------------------
function relpath = relative_path(root_dir, full_path, ids)

prefix = [root_dir filesep];
if length(full_path) <= length(prefix) || ...
   ~strcmp(full_path(1:length(prefix)), prefix)
    error(ids.PROVENANCE.ChecksumMismatch, ...
          'Path escapes provenance root: %s', full_path);
end
relpath = full_path(length(prefix)+1:end);
relpath(relpath == filesep) = '/';
validate_relative_path(relpath, ids);

end

%% ------------------------------------------------------------------------
function result = is_excluded_path(relpath)

result = strcmp(relpath, 'CHECKSUMS.sha256') || strcmp(relpath, 'INVENTORY.json') || ...
    strcmp(relpath, '.gitignore') || strcmp(relpath, '.gitattributes') || ...
    strcmp(relpath, '.gitmodules') || strcmp(relpath, '.git') || ...
    (length(relpath) > 5 && strcmp(relpath(1:5), '.git/'));

end

%% ------------------------------------------------------------------------
function hash = file_sha256(path)

fid = fopen(path, 'rb');
if fid == -1
    hash = '';
    return;
end
cleanup = onCleanup(@() fclose(fid));
data = fread(fid, inf, '*uint8');

try
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(data);
    digest = md.digest();
    hash = sprintf('%02x', typecast(digest, 'uint8'));
catch  %#ok<CTCH>
    hash = '';
end

end

%% ------------------------------------------------------------------------
function name = sanitize_fieldname(relpath)

name = relpath;
name(name == '/') = '_';
name(name == '\') = '_';
name(name == '.') = '_';
name(name == '-') = '_';
for ii = 1:length(name)
    is_letter = (name(ii) >= 'a' && name(ii) <= 'z') || ...
        (name(ii) >= 'A' && name(ii) <= 'Z');
    is_digit = name(ii) >= '0' && name(ii) <= '9';
    if ~(is_letter || is_digit || name(ii) == '_')
        name(ii) = '_';
    end
end
if isempty(name) || ~((name(1) >= 'a' && name(1) <= 'z') || ...
                      (name(1) >= 'A' && name(1) <= 'Z'))
    name = ['f_' name];
end

end

%% ------------------------------------------------------------------------
function parts = strsplit(str)
% Minimal R2010b-safe space/tab split.

parts = {};
remain = strtrim(str);
while ~isempty(remain)
    [tok, remain] = strtok(remain, sprintf(' \t'));
    if ~isempty(tok)
        parts{end+1} = tok; %#ok<AGROW>
    end
end

end
