function path = pseudo_CT_runtime_dir(temp_dir)
%PSEUDO_CT_RUNTIME_DIR Allocate an owned, private invocation under job.temp_dir.
% No installation/system-temp fallback. The caller removes only its own files.
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
