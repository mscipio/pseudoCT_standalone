function test_compressed_nifti_input()
%TEST_COMPRESSED_NIFTI_INPUT Verify direct dcm2nii NIfTI/.nii.gz paths.

root_dir = fileparts(fileparts(mfilename('fullpath')));
d2n_root = fullfile(root_dir, '..', 'dicom2nifti_standalone');
old_path = path;
old_dir = pwd;
test_root = tempname;
mkdir(test_root);
cleanup = onCleanup(@() local_cleanup(test_root, old_path, old_dir));
if exist(d2n_root, 'dir') == 7
    addpath(d2n_root, '-begin');
end

source_dir = fullfile(test_root, 'source');
mkdir(source_dir);
payload = uint8([0 1 2 10 13 127 128 254 255]);

%% Test 1: Compressed .nii.gz input via dcm2nii
plain_source = fullfile(source_dir, 'synthetic.nii');
local_write_bytes(plain_source, payload);
gzip(plain_source, source_dir);
delete(plain_source);
compressed_source = [plain_source '.gz'];
compressed_before = local_read_bytes(compressed_source);

destination_dir = fullfile(test_root, 'destination');
mkdir(destination_dir);
output_path = dcm2nii(compressed_source, fullfile(destination_dir, 'mprage.nii'));
assert(strcmp(strtrim(output_path), fullfile(destination_dir, 'mprage.nii')));
assert(isequal(local_read_bytes(fullfile(destination_dir, 'mprage.nii')), payload));
assert(exist(compressed_source, 'file') == 2);
assert(isequal(local_read_bytes(compressed_source), compressed_before));
assert(exist(fullfile(destination_dir, 'mprage.nii'), 'file') == 2);

%% Test 2: Plain .nii input via dcm2nii (pass-through)
plain_dest_dir = fullfile(test_root, 'plain_destination');
mkdir(plain_dest_dir);
plain_input = fullfile(source_dir, 'plain.nii');
local_write_bytes(plain_input, payload);
output_path = dcm2nii(plain_input, fullfile(plain_dest_dir, 'mprage.nii'));
assert(strcmp(strtrim(output_path), fullfile(plain_dest_dir, 'mprage.nii')));
assert(isequal(local_read_bytes(fullfile(plain_dest_dir, 'mprage.nii')), payload));
assert(exist(fullfile(plain_dest_dir, 'mprage.nii'), 'file') == 2);

%% Test 3: Corrupted .nii.gz input must fail clearly
bad_source = fullfile(source_dir, 'invalid.nii.gz');
local_write_bytes(bad_source, uint8('not a gzip stream'));
failed_destination_dir = fullfile(test_root, 'failed_destination');
mkdir(failed_destination_dir);
failed_destination = fullfile(failed_destination_dir, 'mprage.nii');
prior_destination = uint8('existing destination');
local_write_bytes(failed_destination, prior_destination);
did_fail = false;
try
    dcm2nii(bad_source, fullfile(failed_destination_dir, 'mprage.nii'));
catch ME %#ok<NASGU>
    cd(old_dir);
    did_fail = true;
end
assert(did_fail);
assert(isequal(local_read_bytes(failed_destination), prior_destination));
assert(exist(bad_source, 'file') == 2);

fprintf('Compressed NIfTI input tests passed.\n');
end

function bytes = local_read_bytes(file_path)
fid = fopen(file_path, 'rb');
assert(fid ~= -1);
closer = onCleanup(@() fclose(fid));
bytes = fread(fid, inf, '*uint8')';
end

function local_write_bytes(file_path, bytes)
fid = fopen(file_path, 'wb');
assert(fid ~= -1);
closer = onCleanup(@() fclose(fid));
fwrite(fid, bytes, 'uint8');
end

function local_assert_only_file(directory, expected_name)
entries = dir(directory);
names = {};
for ii=1:length(entries)
    if ~strcmp(entries(ii).name, '.') && ~strcmp(entries(ii).name, '..')
        names{end + 1} = entries(ii).name; %#ok<AGROW>
    end
end
assert(isequal(names, {expected_name}));
end

function local_cleanup(test_root, old_path, old_dir)
cd(old_dir);
path(old_path);
if exist(test_root, 'dir') == 7
    rmdir(test_root, 's');
end
end
