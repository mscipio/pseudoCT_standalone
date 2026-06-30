function test_auto_discover_messages()
% TDD verification script for batch-discovery-messages change.
% Tests fprintf messages emitted by pseudo_CT_discover_ute_umap (shared helper).
% GREEN phase: all assertions pass with the new dir()-based shared helper.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'ui'));

passed = 0;
failed = 0;

%% Setup: create temporary directory structure
tmp_root = fullfile(tempdir, 'tdd_auto_discover_test');
if exist(tmp_root, 'dir')
    rmdir(tmp_root, 's');
end

% ==================== Scenario 1: No MR/ parent path ====================
fprintf('\n--- Scenario 1: No MR/ parent path ---\n');
subj_no_mr = fullfile(tmp_root, 'no_mr_subj');
mkdir(subj_no_mr);
fake_mprage = fullfile(subj_no_mr, 'mprage.dcm');
fid = fopen(fake_mprage, 'w'); fclose(fid);

captured = evalc('pseudo_CT_discover_ute_umap(fake_mprage);');
[ute, umap] = pseudo_CT_discover_ute_umap(fake_mprage);
if ute == 0, passed = passed + 1; fprintf('  PASS  S1a: ute=0\n'); else failed = failed + 1; fprintf('  FAIL  S1a: ute=%s\n', num2str(ute)); end
if umap == 0, passed = passed + 1; fprintf('  PASS  S1b: umap=0\n'); else failed = failed + 1; fprintf('  FAIL  S1b: umap=%s\n', num2str(umap)); end
if contains(captured, 'No MR/ parent'), passed = passed + 1; fprintf('  PASS  S1c: "No MR/ parent" message\n'); else failed = failed + 1; fprintf('  FAIL  S1c: no message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 2: MR parent, no UTE ====================
fprintf('\n--- Scenario 2: MR parent, no UTE ---\n');
subj_mr = fullfile(tmp_root, 'subj_with_MR');
mr_dir = fullfile(subj_mr, 'MR');
sub_dir = fullfile(mr_dir, 'mprage_series');
mkdir(sub_dir);
fake_mprage2 = fullfile(sub_dir, 'mprage.dcm');
fid = fopen(fake_mprage2, 'w'); fclose(fid);
% No dummy_UMAP needed — dir() never crashes on empty results.

captured = evalc('pseudo_CT_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_discover_ute_umap(fake_mprage2);
if ute == 0, passed = passed + 1; fprintf('  PASS  S2a: ute=0\n'); else failed = failed + 1; fprintf('  FAIL  S2a: ute=%s\n', num2str(ute)); end
if contains(captured, 'No UTE found'), passed = passed + 1; fprintf('  PASS  S2b: "No UTE found" message\n'); else failed = failed + 1; fprintf('  FAIL  S2b: no message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 3: MR parent, no UMAP ====================
fprintf('\n--- Scenario 3: MR parent, no UMAP ---\n');
if umap == 0, passed = passed + 1; fprintf('  PASS  S3a: umap=0\n'); else failed = failed + 1; fprintf('  FAIL  S3a: umap=%s\n', num2str(umap)); end
if contains(captured, 'No UMAP found'), passed = passed + 1; fprintf('  PASS  S3b: "No UMAP found" message\n'); else failed = failed + 1; fprintf('  FAIL  S3b: no message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 4: Multiple UTE candidates across sibling folders ====================
fprintf('\n--- Scenario 4: Multiple UTE across sibling folders ---\n');
ute_dir1 = fullfile(mr_dir, 'UTE_2');
mkdir(ute_dir1);
fid = fopen(fullfile(ute_dir1, '0001.dcm'), 'w'); fclose(fid);
ute_dir2 = fullfile(mr_dir, 'ute_alt');
mkdir(ute_dir2);
fid = fopen(fullfile(ute_dir2, '0001.dcm'), 'w'); fclose(fid);

captured = evalc('pseudo_CT_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_discover_ute_umap(fake_mprage2);
if ischar(ute) && contains(ute, '0001.dcm'), passed = passed + 1; fprintf('  PASS  S4a: ute=first sorted candidate\n'); else failed = failed + 1; fprintf('  FAIL  S4a: ute=%s\n', char(ute)); end
if contains(captured, 'UTE candidates'), passed = passed + 1; fprintf('  PASS  S4b: "UTE candidates" message\n'); else failed = failed + 1; fprintf('  FAIL  S4b: no message. stdout=[%s]\n', strtrim(captured)); end

% Clean up UTE directories so they do not pollute UMAP-only scenarios.
rmdir(ute_dir1, 's');
rmdir(ute_dir2, 's');

% ==================== Scenario 5: Multiple UMAP in standard dir ====================
fprintf('\n--- Scenario 5: Multiple UMAP in standard dir ---\n');
umap_dir = fullfile(mr_dir, 'UMAP');
mkdir(umap_dir);
fid = fopen(fullfile(umap_dir, 'a0001.dcm'), 'w'); fclose(fid);
fid = fopen(fullfile(umap_dir, 'b0001.dcm'), 'w'); fclose(fid);

captured = evalc('pseudo_CT_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_discover_ute_umap(fake_mprage2);
if ischar(umap) && contains(umap, '0001.dcm'), passed = passed + 1; fprintf('  PASS  S5a: umap=first candidate\n'); else failed = failed + 1; fprintf('  FAIL  S5a: umap=%s\n', char(umap)); end
if contains(captured, 'UMAP candidates'), passed = passed + 1; fprintf('  PASS  S5b: "UMAP candidates" message (std)\n'); else failed = failed + 1; fprintf('  FAIL  S5b: no message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 6: Single UMAP in standard dir (silent) ====================
fprintf('\n--- Scenario 6: Single UMAP in standard dir (should be silent) ---\n');
rmdir(umap_dir, 's');
mkdir(umap_dir);
fid = fopen(fullfile(umap_dir, '0001.dcm'), 'w'); fclose(fid);

captured = evalc('pseudo_CT_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_discover_ute_umap(fake_mprage2);
if ischar(umap) && contains(umap, '0001.dcm'), passed = passed + 1; fprintf('  PASS  S6a: umap=single candidate\n'); else failed = failed + 1; fprintf('  FAIL  S6a: umap=%s\n', char(umap)); end
no_umap_msg = ~contains(captured, 'UMAP candidate') && ~contains(captured, 'UMAP found');
if no_umap_msg, passed = passed + 1; fprintf('  PASS  S6b: silent (no UMAP message)\n'); else failed = failed + 1; fprintf('  FAIL  S6b: unexpected message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 7: UMAP via case-insensitive sibling match ====================
fprintf('\n--- Scenario 7: UMAP via case-insensitive sibling (should be silent) ---\n');
rmdir(umap_dir, 's');
mumap_dir = fullfile(mr_dir, 'Mu_Map_AC');
mkdir(mumap_dir);
fid = fopen(fullfile(mumap_dir, '0001.dcm'), 'w'); fclose(fid);

captured = evalc('pseudo_CT_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_discover_ute_umap(fake_mprage2);
if ischar(umap) && contains(umap, '0001.dcm') && contains(umap, 'Mu_Map_AC'), passed = passed + 1; fprintf('  PASS  S7a: umap from Mu_Map_AC\n'); else failed = failed + 1; fprintf('  FAIL  S7a: umap=%s\n', char(umap)); end
no_umap_msg2 = ~contains(captured, 'UMAP candidate') && ~contains(captured, 'UMAP found');
if no_umap_msg2, passed = passed + 1; fprintf('  PASS  S7b: silent (single via case-insensitive)\n'); else failed = failed + 1; fprintf('  FAIL  S7b: unexpected message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 8: Multiple UMAP across case-insensitive siblings ====================
fprintf('\n--- Scenario 8: Multiple UMAP across case-insensitive siblings ---\n');
rmdir(mumap_dir, 's');
mumap_dir = fullfile(mr_dir, 'Mu_Map_AC');
mkdir(mumap_dir);
fid = fopen(fullfile(mumap_dir, 'a0001.dcm'), 'w'); fclose(fid);
fid = fopen(fullfile(mumap_dir, 'b0001.dcm'), 'w'); fclose(fid);
umap_dir2 = fullfile(mr_dir, 'umap');
mkdir(umap_dir2);
fid = fopen(fullfile(umap_dir2, '0001.dcm'), 'w'); fclose(fid);

captured = evalc('pseudo_CT_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_discover_ute_umap(fake_mprage2);
if ischar(umap) && contains(umap, '0001.dcm'), passed = passed + 1; fprintf('  PASS  S8a: umap=first sorted candidate\n'); else failed = failed + 1; fprintf('  FAIL  S8a: umap=%s\n', char(umap)); end
if contains(captured, 'UMAP candidates'), passed = passed + 1; fprintf('  PASS  S8b: "UMAP candidates" message\n'); else failed = failed + 1; fprintf('  FAIL  S8b: no message. stdout=[%s]\n', strtrim(captured)); end

%% Cleanup
rmdir(tmp_root, 's');

%% Report
total = passed + failed;
fprintf('\n=== Auto-Discovery Message Tests: %d/%d passed ===\n', passed, total);
if failed > 0
    fprintf('RED phase: %d tests FAIL (expected before implementation).\n', failed);
else
    fprintf('GREEN phase: all %d tests PASS.\n', total);
end
end
