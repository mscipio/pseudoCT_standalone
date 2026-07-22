function test_r6313_provenance()
%TEST_R6313_PROVENANCE RED-first checks for the bundled SPM8 r6313 record.
%   The test drives the deterministic generator/validator against isolated
%   temporary trees.  The tracked SPM tree is validated but never modified.
%   No SPM batch, DICOM conversion, SSH/PBS, or subject mutation is run.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
generator = fullfile(scripts_dir, 'generate_r6313_provenance.py');
tracked_tree = fullfile(root_dir, 'spm8-r6313');
addpath(fullfile(root_dir, 'src', 'config'));
temp_root = tempname;
mkdir(temp_root);
cleanup = onCleanup(@() rmdir(temp_root, 's')); %#ok<NASGU>

passed = 0;
failed = 0;

run_test('generator exists', exist(generator, 'file') == 2);
run_test('tracked r6313 record validates', ...
    run_tool(generator, sprintf('--tree "%s" --validate', tracked_tree)) == 0);
record = pseudo_CT_provenance_record(tracked_tree);
run_test('MATLAB provenance helper consumes r6313 records', ...
    strcmp(record.expected_spm_version, 'r6313') && record.file_count == 4020);

fixture = make_fixture(temp_root, root_dir);
run_test('fixture generation succeeds', ...
    run_tool(generator, sprintf('--tree "%s" --write', fixture)) == 0);
run_test('generated fixture validates', ...
    run_tool(generator, sprintf('--tree "%s" --validate', fixture)) == 0);

run_test('tampered file fails closed', ...
    mutate_and_validate(generator, fixture, 'sample.m', 'tampered') ~= 0);
fixture = make_fixture(temp_root, root_dir);
run_tool(generator, sprintf('--tree "%s" --write', fixture));
delete(fullfile(fixture, 'sample.m'));
run_test('missing file fails closed', ...
    run_tool(generator, sprintf('--tree "%s" --validate', fixture)) ~= 0);

fixture = make_fixture(temp_root, root_dir);
run_tool(generator, sprintf('--tree "%s" --write', fixture));
touch(fullfile(fixture, 'extra.txt'), 'extra');
run_test('extra in-scope file fails closed', ...
    run_tool(generator, sprintf('--tree "%s" --validate', fixture)) ~= 0);

fixture = make_fixture(temp_root, root_dir);
run_tool(generator, sprintf('--tree "%s" --write', fixture));
write_text(fullfile(fixture, 'INVENTORY.json'), '{ malformed');
run_test('malformed inventory fails closed', ...
    run_tool(generator, sprintf('--tree "%s" --validate', fixture)) ~= 0);

fixture = make_fixture(temp_root, root_dir);
run_tool(generator, sprintf('--tree "%s" --write', fixture));
write_text(fullfile(fixture, 'CHECKSUMS.sha256'), ...
    'not-a-sha256  sample.m\n');
run_test('malformed checksum fails closed', ...
    run_tool(generator, sprintf('--tree "%s" --validate', fixture)) ~= 0);

fixture = make_fixture(temp_root, root_dir);
run_tool(generator, sprintf('--tree "%s" --write', fixture));
checksum_text = read_text(fullfile(fixture, 'CHECKSUMS.sha256'));
lines = regexp(checksum_text, '\n', 'split');
lines = lines(~cellfun('isempty', lines));
write_text(fullfile(fixture, 'CHECKSUMS.sha256'), ...
    sprintf('%s\n%s\n', lines{2}, lines{1}));
run_test('non-canonical checksum ordering fails closed', ...
    run_tool(generator, sprintf('--tree "%s" --validate', fixture)) ~= 0);

fixture = make_fixture(temp_root, root_dir);
run_tool(generator, sprintf('--tree "%s" --write', fixture));
inventory = read_text(fullfile(fixture, 'INVENTORY.json'));
inventory = strrep(inventory, '"r6313"', '"r4667"');
write_text(fullfile(fixture, 'INVENTORY.json'), inventory);
run_test('unexpected SPM identity fails closed', ...
    run_tool(generator, sprintf('--tree "%s" --validate', fixture)) ~= 0);

fixture = make_fixture(temp_root, root_dir);
run_tool(generator, sprintf('--tree "%s" --write', fixture));
write_text(fullfile(fixture, 'CHECKSUMS.sha256'), ...
    '../escape  sample.m\n');
run_test('unsafe checksum path fails closed', ...
    run_tool(generator, sprintf('--tree "%s" --validate', fixture)) ~= 0);

fixture = make_fixture(temp_root, root_dir);
run_tool(generator, sprintf('--tree "%s" --write', fixture));
first_inventory = read_text(fullfile(fixture, 'INVENTORY.json'));
first_checksums = read_text(fullfile(fixture, 'CHECKSUMS.sha256'));
run_tool(generator, sprintf('--tree "%s" --write', fixture));
run_test('rerun inventory is byte-identical', ...
    strcmp(first_inventory, read_text(fullfile(fixture, 'INVENTORY.json'))));
run_test('rerun checksums are byte-identical', ...
    strcmp(first_checksums, read_text(fullfile(fixture, 'CHECKSUMS.sha256'))));

fprintf('\n=== r6313 Provenance Tests: %d/%d passed ===\n', passed, passed + failed);
if failed > 0
    error('test_r6313_provenance:Failures', '%d test(s) failed.', failed);
end

    function run_test(label, ok)
        if ok
            passed = passed + 1;
            fprintf('  PASS  %s\n', label);
        else
            failed = failed + 1;
            fprintf('  FAIL  %s\n', label);
        end
    end

    function status = run_tool(tool, args)
        command = sprintf('python3 "%s" %s', tool, args);
        [status, ~] = system(command);
    end

    function status = mutate_and_validate(tool, tree, relative_path, content)
        write_text(fullfile(tree, relative_path), content);
        status = run_tool(tool, sprintf('--tree "%s" --validate', tree));
    end

    function tree = make_fixture(parent, source_root)
        fixture_root = tempname(parent);
        mkdir(fixture_root);
        tree = fullfile(fixture_root, 'spm8-r6313');
        mkdir(tree);
        copyfile(fullfile(source_root, 'spm8-r6313', 'Contents.m'), tree);
        copyfile(fullfile(source_root, 'spm8-r6313', 'README.txt'), tree);
        copyfile(fullfile(source_root, 'spm8-r6313', 'spm_LICENCE.man'), tree);
        touch(fullfile(tree, 'sample.m'), 'fixture');
    end

    function touch(path, content)
        write_text(path, content);
    end

    function write_text(path, content)
        fid = fopen(path, 'w');
        if fid == -1
            error('test_r6313_provenance:WriteFailed', 'Cannot write %s.', path);
        end
        fwrite(fid, content, 'char');
        fclose(fid);
    end

    function text = read_text(path)
        fid = fopen(path, 'r');
        if fid == -1
            error('test_r6313_provenance:ReadFailed', 'Cannot read %s.', path);
        end
        text = fread(fid, inf, '*char')';
        fclose(fid);
    end

end
