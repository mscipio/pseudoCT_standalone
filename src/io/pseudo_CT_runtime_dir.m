function path = pseudo_CT_runtime_dir(temp_dir)
%PSEUDO_CT_RUNTIME_DIR Allocate a private invocation folder under the subject temp folder.
%   PATH = PSEUDO_CT_RUNTIME_DIR(TEMP_DIR) creates a new folder named
%   pseudoct-runtime-XXXXXXXX inside TEMP_DIR, with mode 0700, and returns its
%   path. There is no fallback to the system temp folder. TEMP_DIR must exist
%   and must not be a symbolic link. The caller removes only its own files.
%   Side effects: creates one folder. Errors: pseudo_CT:RuntimeDirectory when
%   the folder cannot be created or secured. Minimum supported MATLAB: R2010b.
if ~ischar(temp_dir) || isempty(temp_dir) || exist(temp_dir, 'dir') ~= 7
    error('pseudo_CT:RuntimeDirectory', 'The subject temporary directory is unavailable.');
end
[status, ~] = system(['test ! -L ' local_quote(temp_dir)]);
if status ~= 0
    error('pseudo_CT:RuntimeDirectory', 'The subject temporary directory must not be a link.');
end
[status, path] = system(['umask 077; mktemp -d -- ' ...
    local_quote(fullfile(temp_dir, 'pseudoct-runtime-XXXXXXXX'))]);
path = strtrim(path);
if status ~= 0 || isempty(path)
    error('pseudo_CT:RuntimeDirectory', 'Cannot allocate a private subject runtime directory.');
end
[status, ~] = system(['chmod 00700 -- ' local_quote(path)]);
if status ~= 0
    rmdir(path);
    error('pseudo_CT:RuntimeDirectory', 'Cannot secure subject runtime directory.');
end
end

function text = local_quote(text)
text = ['''' strrep(text, '''', '''"''"''') ''''];
end
