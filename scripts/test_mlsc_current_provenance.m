function test_mlsc_current_provenance()
%TEST_MLSC_CURRENT_PROVENANCE Narrow content-binding regression (T007).
%   Offline only (no Gates/production, no rebuild, no /usr/pubsw mutation,
%   no SSH/Slurm). Covers exactly one invariant: same filenames with
%   changed contents yield different content-bound fingerprints, where the
%   fingerprint is SHA-256 over canonical "<relpath>\t<SHA256>\n" per
%   included file sorted by path. No broader redesign.
%
%   Minimum supported MATLAB: R2010b.

test_root = tempname;
mkdir(test_root);
cleanup_root = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>

% Same filenames in two fixture trees, one file content differs.
rels = {'a.m'; 'sub/b.m'};
dir_a = fullfile(test_root, 'case-a');
dir_b = fullfile(test_root, 'case-b');
mkdir(dir_a);
mkdir(fullfile(dir_a, 'sub'));
mkdir(dir_b);
mkdir(fullfile(dir_b, 'sub'));
local_write(fullfile(dir_a, 'a.m'), 'content-one');
local_write(fullfile(dir_a, 'sub', 'b.m'), 'shared-content');
local_write(fullfile(dir_b, 'a.m'), 'content-one');
local_write(fullfile(dir_b, 'sub', 'b.m'), 'shared-content-CHANGED');

fp_a = local_content_fingerprint(dir_a, rels);
fp_b = local_content_fingerprint(dir_b, rels);
assert(ischar(fp_a) && length(fp_a) == 64, 'Fingerprint A invalid.');
assert(ischar(fp_b) && length(fp_b) == 64, 'Fingerprint B invalid.');
assert(~strcmp(fp_a, fp_b), 'Same filenames with changed contents did not change the fingerprint.');

% Determinism sanity: identical contents yield identical fingerprints.
dir_c = fullfile(test_root, 'case-c');
mkdir(dir_c);
mkdir(fullfile(dir_c, 'sub'));
local_write(fullfile(dir_c, 'a.m'), 'content-one');
local_write(fullfile(dir_c, 'sub', 'b.m'), 'shared-content');
fp_c = local_content_fingerprint(dir_c, rels);
assert(strcmp(fp_a, fp_c), 'Identical contents did not yield identical fingerprints.');

fprintf('PROVENANCE-REGRESSION PASS: same filenames + changed contents => different fingerprint.\n');
end

function fp = local_content_fingerprint(root_dir, rels)
rels = sort(rels(:));
canonical = '';
for kk = 1:numel(rels)
    rel_here = strtrim(rels{kk});
    full_here = fullfile(root_dir, rel_here);
    h = local_sha_hex(full_here);
    canonical = [canonical rel_here char(9) lower(strtrim(h)) char(10)]; %#ok<AGROW>
end
try
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(uint8(canonical));
    bytes = typecast(digest.digest(), 'uint8');
    fp = lower(reshape(dec2hex(bytes, 2)', 1, []));
    assert(length(fp) == 64, 'Content fingerprint failed.');
    return;
catch %#ok<CTCH>
end
error('pseudo_CT:ProvenanceRegression', 'Content fingerprint unavailable.');
end

function hex = local_sha_hex(path_name)
fid = fopen(path_name, 'r');
assert(fid ~= -1, 'Hash fixture could not be read.');
raw = fread(fid, inf, '*uint8')';
fclose(fid);
try
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(raw);
    bytes = typecast(digest.digest(), 'uint8');
    hex = lower(reshape(dec2hex(bytes, 2)', 1, []));
    assert(length(hex) == 64, 'SHA fixture failed.');
    return;
catch %#ok<CTCH>
end
single_quote = char(39);
q = [single_quote strrep(path_name, single_quote, [single_quote '"' single_quote '"' single_quote]) single_quote];
[status, out] = system(['sha256sum ' q ' 2>/dev/null']);
assert(status == 0, 'SHA fixture unavailable.');
tok = regexp(strtrim(out), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', 'tokens', 'once');
assert(~isempty(tok), 'SHA fixture parse failed.');
hex = lower(strtrim(tok{1}));
end

function local_write(path_name, text)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'Fixture could not be created.');
fwrite(fid, text);
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
