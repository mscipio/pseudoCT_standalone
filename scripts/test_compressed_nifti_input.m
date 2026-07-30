function test_compressed_nifti_input()
%TEST_COMPRESSED_NIFTI_INPUT Verify safe .nii.gz MPRAGE staging.

root_dir = fileparts(fileparts(mfilename('fullpath')));
io_dir = fullfile(root_dir, 'src', 'io');
old_path = path;
old_dir = pwd;
test_root = tempname;
mkdir(test_root);
cleanup = onCleanup(@() local_cleanup(test_root, old_path, old_dir));
addpath(io_dir, '-begin');

source_dir = fullfile(test_root, 'source');
mkdir(source_dir);
payload = uint8([0 1 2 10 13 127 128 254 255]);
plain_source = fullfile(source_dir, 'synthetic.nii');
local_write_bytes(plain_source, payload);
gzip(plain_source, source_dir);
delete(plain_source);
compressed_source = [plain_source '.gz'];
compressed_before = local_read_bytes(compressed_source);

% If compressed NIfTI detection regresses, this guard makes the DICOM path
% fail with a deterministic error before any SPM dependency is reached.
local_write_text(fullfile(source_dir, 'dicominfo.m'), ...
    ['function value = dicominfo(varargin)' char(10) ...
     'value = [];' char(10) ...
     'error(''test:DicomPathUsed'', ''Compressed NIfTI entered DICOM path.'');' char(10) ...
     'end' char(10)]);

destination_dir = fullfile(test_root, 'destination');
[Pnew, dcmnew] = convert_dicom_i_2_nii(compressed_source, ...
    'mprage.nii', destination_dir);
destination = fullfile(destination_dir, 'mprage.nii');
assert(strcmp(strtrim(Pnew), destination));
assert(isempty(dcmnew));
assert(isequal(local_read_bytes(destination), payload));
assert(exist(compressed_source, 'file') == 2);
assert(isequal(local_read_bytes(compressed_source), compressed_before));
local_assert_only_file(destination_dir, 'mprage.nii');

mixed_source = fullfile(source_dir, 'synthetic.NII.GZ');
copyfile(compressed_source, mixed_source);
mixed_before = local_read_bytes(mixed_source);
mixed_destination_dir = fullfile(test_root, 'mixed_destination');
Pnew = convert_dicom_i_2_nii(mixed_source, 'mprage.nii', ...
    mixed_destination_dir);
mixed_destination = fullfile(mixed_destination_dir, 'mprage.nii');
assert(strcmp(strtrim(Pnew), mixed_destination));
assert(isequal(local_read_bytes(mixed_destination), payload));
assert(isequal(local_read_bytes(mixed_source), mixed_before));
local_assert_only_file(mixed_destination_dir, 'mprage.nii');

bad_source = fullfile(source_dir, 'invalid.nii.gz');
local_write_bytes(bad_source, uint8('not a gzip stream'));
failed_destination_dir = fullfile(test_root, 'failed_destination');
mkdir(failed_destination_dir);
failed_destination = fullfile(failed_destination_dir, 'mprage.nii');
prior_destination = uint8('existing destination');
local_write_bytes(failed_destination, prior_destination);
did_fail = false;
try
    convert_dicom_i_2_nii(bad_source, 'mprage.nii', failed_destination_dir);
catch ME
    cd(old_dir);
    did_fail = ~strcmp(ME.identifier, 'test:DicomPathUsed');
end
assert(did_fail);
assert(isequal(local_read_bytes(failed_destination), prior_destination));
assert(exist(bad_source, 'file') == 2);
local_assert_only_file(failed_destination_dir, 'mprage.nii');

fprintf('Compressed NIfTI input tests passed.\n');
end

function bytes = local_read_bytes(file_path)
fid = fopen(file_path, 'rb');
assert(fid ~= -1);
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, inf, '*uint8')';
end

function local_write_bytes(file_path, bytes)
fid = fopen(file_path, 'wb');
assert(fid ~= -1);
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, bytes, 'uint8');
end

function local_write_text(file_path, text)
fid = fopen(file_path, 'w');
assert(fid ~= -1);
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, text);
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
