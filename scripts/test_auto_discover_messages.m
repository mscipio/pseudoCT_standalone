function test_auto_discover_messages()
% TDD verification script for batch-discovery-messages change.
% Tests fprintf messages emitted by pseudo_CT_auto_discover_ute_umap.
% RED phase: message-check assertions FAIL (no fprintf yet).
% GREEN phase: all assertions pass after adding fprintf calls.

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

captured = evalc('pseudo_CT_auto_discover_ute_umap(fake_mprage);');
[ute, umap] = pseudo_CT_auto_discover_ute_umap(fake_mprage);
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
% Create a dummy *UMAP* dir to avoid ls() crash in wildcard fallback.
% The function's ls('*UMAP*') errors if no matching dirs exist — pre-existing.
dummy_umap_dir = fullfile(mr_dir, 'dummy_UMAP');
mkdir(dummy_umap_dir);

captured = evalc('pseudo_CT_auto_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_auto_discover_ute_umap(fake_mprage2);
if ute == 0, passed = passed + 1; fprintf('  PASS  S2a: ute=0\n'); else failed = failed + 1; fprintf('  FAIL  S2a: ute=%s\n', num2str(ute)); end
if contains(captured, 'No UTE found'), passed = passed + 1; fprintf('  PASS  S2b: "No UTE found" message\n'); else failed = failed + 1; fprintf('  FAIL  S2b: no message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 3: MR parent, no UMAP ====================
fprintf('\n--- Scenario 3: MR parent, no UMAP ---\n');
if umap == 0, passed = passed + 1; fprintf('  PASS  S3a: umap=0\n'); else failed = failed + 1; fprintf('  FAIL  S3a: umap=%s\n', num2str(umap)); end
if contains(captured, 'No UMAP found'), passed = passed + 1; fprintf('  PASS  S3b: "No UMAP found" message\n'); else failed = failed + 1; fprintf('  FAIL  S3b: no message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 4: Multiple UTE candidates ====================
fprintf('\n--- Scenario 4: Multiple UTE candidates ---\n');
ute_dir = fullfile(mr_dir, 'UTE_2');
mkdir(ute_dir);
fid = fopen(fullfile(ute_dir, 'a0001.dcm'), 'w'); fclose(fid);
fid = fopen(fullfile(ute_dir, 'b0001.dcm'), 'w'); fclose(fid);

captured = evalc('pseudo_CT_auto_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_auto_discover_ute_umap(fake_mprage2);
if ischar(ute) && contains(ute, '0001.dcm'), passed = passed + 1; fprintf('  PASS  S4a: ute=first candidate\n'); else failed = failed + 1; fprintf('  FAIL  S4a: ute=%s\n', char(ute)); end
if contains(captured, 'UTE candidates'), passed = passed + 1; fprintf('  PASS  S4b: "UTE candidates" message\n'); else failed = failed + 1; fprintf('  FAIL  S4b: no message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 5: Multiple UMAP in standard dir ====================
fprintf('\n--- Scenario 5: Multiple UMAP in standard dir ---\n');
umap_dir = fullfile(mr_dir, 'UMAP');
mkdir(umap_dir);
fid = fopen(fullfile(umap_dir, 'a0001.dcm'), 'w'); fclose(fid);
fid = fopen(fullfile(umap_dir, 'b0001.dcm'), 'w'); fclose(fid);

captured = evalc('pseudo_CT_auto_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_auto_discover_ute_umap(fake_mprage2);
if ischar(umap) && contains(umap, '0001.dcm'), passed = passed + 1; fprintf('  PASS  S5a: umap=first candidate\n'); else failed = failed + 1; fprintf('  FAIL  S5a: umap=%s\n', char(umap)); end
if contains(captured, 'UMAP candidates'), passed = passed + 1; fprintf('  PASS  S5b: "UMAP candidates" message (std)\n'); else failed = failed + 1; fprintf('  FAIL  S5b: no message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 6: Multiple UMAP via wildcard ====================
fprintf('\n--- Scenario 6: Multiple UMAP via wildcard ---\n');
rmdir(umap_dir, 's');
rmdir(dummy_umap_dir, 's');  % remove dummy so wildcard finds MR_UMAP first
wildcard_dir = fullfile(mr_dir, 'MR_UMAP');
mkdir(wildcard_dir);
fid = fopen(fullfile(wildcard_dir, 'a0001.dcm'), 'w'); fclose(fid);
fid = fopen(fullfile(wildcard_dir, 'b0001.dcm'), 'w'); fclose(fid);

captured = evalc('pseudo_CT_auto_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_auto_discover_ute_umap(fake_mprage2);
if ischar(umap) && contains(umap, '0001.dcm'), passed = passed + 1; fprintf('  PASS  S6a: umap=first via wildcard\n'); else failed = failed + 1; fprintf('  FAIL  S6a: umap=%s\n', char(umap)); end
if contains(captured, 'UMAP candidates'), passed = passed + 1; fprintf('  PASS  S6b: "UMAP candidates" message (wildcard)\n'); else failed = failed + 1; fprintf('  FAIL  S6b: no message. stdout=[%s]\n', strtrim(captured)); end

% ==================== Scenario 7: Single UMAP via wildcard (silent) ====================
fprintf('\n--- Scenario 7: Single UMAP via wildcard (should be silent) ---\n');
rmdir(wildcard_dir, 's');
mkdir(wildcard_dir);
fid = fopen(fullfile(wildcard_dir, '0001.dcm'), 'w'); fclose(fid);

captured = evalc('pseudo_CT_auto_discover_ute_umap(fake_mprage2);');
[ute, umap] = pseudo_CT_auto_discover_ute_umap(fake_mprage2);
if ischar(umap) && contains(umap, '0001.dcm'), passed = passed + 1; fprintf('  PASS  S7a: umap=first via wildcard\n'); else failed = failed + 1; fprintf('  FAIL  S7a: umap=%s\n', char(umap)); end
no_umap_msg = ~contains(captured, 'UMAP candidate') && ~contains(captured, 'UMAP found');
if no_umap_msg, passed = passed + 1; fprintf('  PASS  S7b: silent (no UMAP message)\n'); else failed = failed + 1; fprintf('  FAIL  S7b: unexpected message. stdout=[%s]\n', strtrim(captured)); end

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
