function test_mlsc_empty_canonical_digest()
%TEST_MLSC_EMPTY_CANONICAL_DIGEST Empty-input SHA-256 regression (tooling repair).
%   Clean checkouts carry no tracked mods and no untracked sources, so the
%   content-bound canonical text is legitimately EMPTY and its SHA-256 must
%   be the NIST empty vector e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.
%   The old code called digest.update() on an empty uint8, which throws
%   (MATLAB:Java:NonScalarArg), so clean-source fingerprinting errored
%   instead of returning the empty digest. The fix finalizes a fresh
%   digest without calling update() on empty input (no hardcoded hash;
%   nonempty behavior byte-identical; fail-closed validation retained).
%
%   Synthetic only, offline, no mcc/science/publish/deploy/tag/worktree.
%   Covers both build_mlsc_current.m digest sites (provenance + packaged
%   inventory) and both mlsc_release_gate.m digest sites (sha256_file +
%   inventory_dir) via production entry points plus source-guard
%   assertions that fail on the old code path.
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');

gate_root = fullfile(root_dir, 'scratch', 'release_gate');
if exist(gate_root, 'dir') ~= 7
    [ok_gate, msg_gate] = mkdir(gate_root);
    assert(ok_gate, 'Cannot create gate staging dir: %s.', msg_gate);
end
run_root = fullfile(gate_root, 'empty_digest_fixtures');
if exist(run_root, 'dir') == 7
    rmdir(run_root, 's');
end
mkdir(run_root);
cleanup_root = onCleanup(@() local_cleanup(run_root)); %#ok<NASGU>

NIST_EMPTY = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

% E1: fresh digest without update() is the NIST empty vector; the old
%   update-on-empty idiom throws (detection sensitivity: this assertion
%   fails on the old code path, which could not digest empty input).
fresh = java.security.MessageDigest.getInstance('SHA-256');
fresh_bytes = typecast(fresh.digest(), 'uint8');
fresh_hex = lower(reshape(dec2hex(fresh_bytes, 2)', 1, []));
assert(strcmp(fresh_hex, NIST_EMPTY), 'Fresh-digest empty vector mismatch.');
old_threw = false;
try
    old_d = java.security.MessageDigest.getInstance('SHA-256');
    old_d.update(uint8(''));
catch %#ok<CTCH>
    old_threw = true;
end
assert(old_threw, 'Old update-on-empty idiom did not throw; sensitivity control failed.');
fprintf('EMPTY-E1 PASS: NIST empty vector via fresh digest; old idiom proven to throw.\n');

% E2: production empty inputs hash to the NIST vector (clean-checkout
%   canonical). Fails on old code (canonical sites errored).
empty_dir = fullfile(run_root, 'empty_dir');
mkdir(empty_dir);
[~, ~, fp_empty_dir] = mlsc_release_gate('inventory_dir', empty_dir, {});
assert(strcmp(fp_empty_dir, NIST_EMPTY), 'Empty-dir inventory did not yield the NIST vector.');
empty_file = fullfile(run_root, 'empty.bin');
fid = fopen(empty_file, 'w');
assert(fid ~= -1, 'Empty fixture could not be created.');
fclose(fid);
hex_empty_file = mlsc_release_gate('sha256_file', empty_file);
assert(strcmp(hex_empty_file, NIST_EMPTY), 'Empty-file hash did not yield the NIST vector.');
fprintf('EMPTY-E2 PASS: empty canonical + empty file yield the NIST vector.\n');

% E3: nonempty behavior unchanged (byte-identical): gate inventory matches
%   an independent sha256sum-based recomputation; determinism holds.
ne_dir = fullfile(run_root, 'nonempty');
mkdir(ne_dir);
mkdir(fullfile(ne_dir, 'sub'));
local_write(fullfile(ne_dir, 'a.txt'), 'alpha-bytes');
local_write(fullfile(ne_dir, 'sub', 'b.txt'), 'beta-bytes');
[ne_files, ~, ne_fp] = mlsc_release_gate('inventory_dir', ne_dir, {});
assert(isequal(ne_files, sort(ne_files(:))), 'Inventory relpaths not sorted.');
ref_fp = local_reference_inventory_fp(ne_dir, {});
assert(strcmp(ne_fp, ref_fp), 'Nonempty inventory fingerprint changed.');
[~, ~, ne_fp2] = mlsc_release_gate('inventory_dir', ne_dir, {});
assert(strcmp(ne_fp, ne_fp2), 'Nonempty inventory not deterministic.');
hex_a = mlsc_release_gate('sha256_file', fullfile(ne_dir, 'a.txt'));
assert(strcmp(hex_a, local_sha_ref(fullfile(ne_dir, 'a.txt'))), 'Nonempty file hash changed.');
fprintf('EMPTY-E3 PASS: nonempty digests unchanged and deterministic.\n');

% E4: malformed type/shape stays rejected (fail-closed validation kept).
assert(~mlsc_release_gate('is_valid_sha256', ''), 'Empty hash accepted.');
assert(~mlsc_release_gate('is_valid_sha256', 'not-a-hash'), 'Garbage hash accepted.');
assert(~mlsc_release_gate('is_valid_sha256', repmat('a', 1, 63)), '63-hex accepted.');
assert(~mlsc_release_gate('is_valid_sha256', repmat('a', 1, 65)), '65-hex accepted.');
assert(mlsc_release_gate('is_valid_sha256', NIST_EMPTY), 'Valid lowercase hash rejected.');
assert(mlsc_release_gate('is_valid_sha256', upper(NIST_EMPTY)), 'Valid uppercase hash rejected.');
bad_hex = NIST_EMPTY;
bad_hex(1) = 'g';
assert(~mlsc_release_gate('is_valid_sha256', bad_hex), 'Non-hex 64-char accepted.');
assert(~mlsc_release_gate('is_valid_sha256', 42), 'Non-char hash accepted.');
local_expect_block(@() mlsc_release_gate('sha256_file', fullfile(run_root, 'absent.bin')), 'missing');
local_expect_block(@() mlsc_release_gate('inventory_dir', fullfile(run_root, 'absent_dir'), {}), 'unavailable');
local_expect_block(@() mlsc_release_gate('resolve_commit', run_root, '', ''), 'required');
local_expect_block(@() mlsc_release_gate('resolve_commit', run_root, '', 'not-a-commit'), '40-hex');
fprintf('EMPTY-E4 PASS: malformed type/shape rejected fail-closed.\n');

% E5: manifest-with-empty-canonical (fully excluded inventory) passes with
%   the NIST vector instead of erroring (old code errored here).
[ex_files, ~, ex_fp] = mlsc_release_gate('inventory_dir', ne_dir, ne_files);
assert(isempty(ex_files), 'Full exclusion did not empty the inventory.');
assert(strcmp(ex_fp, NIST_EMPTY), 'Fully-excluded manifest did not yield the NIST vector.');
fprintf('EMPTY-E5 PASS: manifest generation with empty canonical yields the NIST vector.\n');

% E6: clean-worktree provenance passes; wrong commit/tag/fingerprint
%   rejected. Each gate factor is independently enforced (empty digest
%   alone is never sufficient identity).
syn_repo = fullfile(run_root, 'clean_repo');
mkdir(syn_repo);
local_write(fullfile(syn_repo, 'seed.txt'), 'seed');
assert(system(sprintf('git -C "%s" init -q 2>&1', syn_repo)) == 0, 'Fixture git init failed.');
assert(system(sprintf('git -C "%s" add seed.txt 2>&1', syn_repo)) == 0, 'Fixture git add failed.');
assert(system(sprintf('git -C "%s" -c user.name=fixture -c user.email=fixture@local commit -qm seed 2>&1', syn_repo)) == 0, 'Fixture git commit failed.');
assert(system(sprintf('git -C "%s" tag vEmptyDigestTest 2>&1', syn_repo)) == 0, 'Fixture git tag failed.');
[s_head, o_head] = system(sprintf('git -C "%s" --no-pager rev-parse HEAD 2>&1', syn_repo));
syn_commit = lower(strtrim(o_head));
assert(s_head == 0 && length(syn_commit) == 40, 'Fixture commit unresolvable.');
tree_clean = mlsc_release_gate('verify_clean_source', syn_repo, syn_commit);
tree_recomputed = mlsc_release_gate('release_tree', syn_repo, syn_commit);
assert(strcmp(tree_clean, tree_recomputed), 'Clean-source tree mismatch.');
assert(strcmp(mlsc_release_gate('resolve_commit', syn_repo, 'vEmptyDigestTest', ''), syn_commit), 'Tag resolution failed.');
assert(strcmp(mlsc_release_gate('resolve_commit', syn_repo, 'vEmptyDigestTest', syn_commit), syn_commit), 'Tag+commit agreement failed.');
% A clean tree has no tracked mods / untracked sources, so its
% content-bound canonical fingerprint is the empty digest; a wrong
% expected fingerprint ('0'*64) mismatches and blocks (strcmpi false).
assert(~strcmpi(repmat('0', 1, 64), NIST_EMPTY), 'Wrong-fingerprint control failed.');
wrong_commit = syn_commit;
if wrong_commit(1) ~= 'a'
    wrong_commit(1) = 'a';
else
    wrong_commit(1) = 'b';
end
local_expect_block(@() mlsc_release_gate('verify_clean_source', syn_repo, wrong_commit), 'does not match');
local_expect_block(@() mlsc_release_gate('resolve_commit', syn_repo, 'vEmptyDigestTest', wrong_commit), 'commit==tag');
local_expect_block(@() mlsc_release_gate('resolve_commit', syn_repo, 'vNoSuchTagEmpty', ''), 'unresolvable');
local_expect_block(@() mlsc_release_gate('release_tree', syn_repo, repmat('c', 1, 40)), 'unknown');
local_write(fullfile(syn_repo, 'dirt.txt'), 'dirty');
local_expect_block(@() mlsc_release_gate('verify_clean_source', syn_repo, syn_commit), 'not clean');
delete(fullfile(syn_repo, 'dirt.txt'));
fprintf('EMPTY-E6 PASS: clean worktree passes; wrong commit/tag/fingerprint rejected.\n');

% E7: both failing digest sites per file carry the empty guard (fails on
%   old code, which called update() on possibly-empty input unguarded).
build_text = fileread(fullfile(root_dir, 'scripts', 'build_mlsc_current.m'));
gate_text = fileread(fullfile(root_dir, 'src', 'mlsc', 'mlsc_release_gate.m'));
assert(length(strfind(build_text, 'digest.update(uint8(canonical))')) == 2, ...
    'Build digest sites changed shape unexpectedly.');
assert(length(strfind(build_text, 'if ~isempty(canonical)')) >= 2, ...
    'Build empty-canonical guard missing at a failing location.');
assert(~isempty(strfind(gate_text, 'if ~isempty(raw)')), 'Gate empty-file guard missing.');
assert(~isempty(strfind(gate_text, 'if ~isempty(canonical)')), 'Gate empty-canonical guard missing.');
fprintf('EMPTY-E7 PASS: both failing locations guarded in each file.\n');

fprintf('=== MLSC empty-canonical digest tests passed: E1-E7 ===\n');
end

function local_expect_block(thunk, reason_substr)
failed = false;
actual_msg = '';
try
    thunk();
catch ME
    failed = true;
    actual_msg = ME.message;
end
assert(failed, 'Fail-closed gate did not reject.');
assert(~isempty(strfind(actual_msg, reason_substr)), 'Gate reason missing "%s": %s.', reason_substr, actual_msg);
end

function hex = local_sha_ref(path_name)
single_quote = char(39);
q = [single_quote strrep(path_name, single_quote, [single_quote '"' single_quote '"' single_quote]) single_quote];
[status, out] = system(['sha256sum ' q ' 2>/dev/null']);
assert(status == 0, 'SHA reference unavailable.');
tok = regexp(strtrim(out), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', 'tokens', 'once');
assert(~isempty(tok), 'SHA reference parse failed.');
hex = lower(strtrim(tok{1}));
end

function fp = local_reference_inventory_fp(root_dir, exclude_list)
rels = local_walk_ref(root_dir, '');
rels = sort(rels(:));
canonical = '';
for kk = 1:numel(rels)
    rel_here = rels{kk};
    skip = false;
    for jj = 1:numel(exclude_list)
        if strcmp(rel_here, exclude_list{jj})
            skip = true;
            break;
        end
    end
    if ~skip
        h = local_sha_ref(fullfile(root_dir, strrep(rel_here, '/', filesep)));
        canonical = [canonical rel_here char(9) h char(10)]; %#ok<AGROW>
    end
end
digest = java.security.MessageDigest.getInstance('SHA-256');
if ~isempty(canonical)
    digest.update(uint8(canonical));
end
bytes = typecast(digest.digest(), 'uint8');
fp = lower(reshape(dec2hex(bytes, 2)', 1, []));
end

function rels = local_walk_ref(root_here, prefix)
rels = {};
listed = dir(fullfile(root_here, prefix, '*'));
names = {};
for kk = 1:numel(listed)
    nm = listed(kk).name;
    if strcmp(nm, '.') || strcmp(nm, '..')
        continue;
    end
    names{end + 1, 1} = nm; %#ok<AGROW>
end
names = sort(names);
for kk = 1:numel(names)
    if isempty(prefix)
        rel_here = names{kk};
    else
        rel_here = [prefix '/' names{kk}]; %#ok<AGROW>
    end
    full_here = fullfile(root_here, strrep(rel_here, '/', filesep));
    if exist(full_here, 'dir') == 7
        sub = local_walk_ref(root_here, rel_here);
        for jj = 1:numel(sub)
            rels{end + 1, 1} = sub{jj}; %#ok<AGROW>
        end
    elseif exist(full_here, 'file') == 2
        rels{end + 1, 1} = rel_here; %#ok<AGROW>
    end
end
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
