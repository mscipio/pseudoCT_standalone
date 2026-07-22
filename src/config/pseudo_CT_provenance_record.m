function record = pseudo_CT_provenance_record(tree_dir, record_path)
%PSEUDO_CT_PROVENANCE_RECORD Load or validate a vendor provenance record.
%   RECORD = PSEUDO_CT_PROVENANCE_RECORD(TREE_DIR, RECORD_PATH) returns the
%   provenance record for a vendor SPM tree. In PR1 this is a foundation
%   helper: it validates that the record file and inventory exist and that
%   the expected SPM version is recorded. Full checksum verification is
%   wired here but only enforced when the underlying CHECKSUMS.sha256 file
%   is present.
%
%   When TREE_DIR is omitted or empty, an empty record template is returned.
%   When the record file is missing, PROVENANCE:RecordMissing is raised.
%   When the inventory is missing, PROVENANCE:InventoryMissing is raised.
%   When a checksum does not match, PROVENANCE:ChecksumMismatch is raised.
%
%   r4667 records are apply-blocked; calling this helper for spm8-r4667
%   before the vendor phase materializes it will raise PROVENANCE:RecordMissing.
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
record.file_count = count_tree_files(tree_dir);
record.bytes = dir_bytes(tree_dir);

[~, tree_name] = fileparts(tree_dir);
if strcmp(tree_name, 'spm8-r6313')
    record.expected_spm_version = 'r6313';
elseif strcmp(tree_name, 'spm8-r4667')
    record.expected_spm_version = 'r4667';
else
    record.expected_spm_version = tree_name;
end

checksums_path = fullfile(tree_dir, 'CHECKSUMS.sha256');
if exist(checksums_path, 'file') == 2
    record.sha256_map = read_checksums(checksums_path, ids);
    verify_checksums(tree_dir, record.sha256_map, ids);
end

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
record.record_path = '';

end

%% ------------------------------------------------------------------------
function n = count_tree_files(tree_dir)

n = 0;
entries = dir(tree_dir);
for ii = 1:length(entries)
    if strcmp(entries(ii).name, '.') || strcmp(entries(ii).name, '..')
        continue;
    end
    if entries(ii).isdir
        n = n + count_tree_files(fullfile(tree_dir, entries(ii).name));
    else
        n = n + 1;
    end
end

end

%% ------------------------------------------------------------------------
function bytes = dir_bytes(tree_dir)

bytes = 0;
entries = dir(tree_dir);
for ii = 1:length(entries)
    if strcmp(entries(ii).name, '.') || strcmp(entries(ii).name, '..')
        continue;
    end
    if entries(ii).isdir
        bytes = bytes + dir_bytes(fullfile(tree_dir, entries(ii).name));
    else
        bytes = bytes + entries(ii).bytes;
    end
end

end

%% ------------------------------------------------------------------------
function map = read_checksums(path, ids)

map = struct();
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
    if length(parts) >= 2
        hash = parts{1};
        relpath = parts{2};
        map.(sanitize_fieldname(relpath)) = hash;
    end
end

end

%% ------------------------------------------------------------------------
function verify_checksums(tree_dir, map, ids)

fields = fieldnames(map);
for ii = 1:length(fields)
    relpath = fields{ii};
    expected = map.(relpath);
    full_path = fullfile(tree_dir, relpath);
    if exist(full_path, 'file') ~= 2
        error(ids.PROVENANCE.ChecksumMismatch, ...
              'Provenance inventory lists missing file: %s', full_path);
    end
    actual = file_sha256(full_path);
    if ~strcmpi(actual, expected)
        error(ids.PROVENANCE.ChecksumMismatch, ...
              'Checksum mismatch for %s', full_path);
    end
end

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
if ~isempty(name) && name(1) >= '0' && name(1) <= '9'
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
