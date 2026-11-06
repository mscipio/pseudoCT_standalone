function [ok, message] = pseudo_CT_cleanup_subject_temp(temp_dir)
%PSEUDO_CT_CLEANUP_SUBJECT_TEMP Preserve retained logs and invocation owners.
% Unlike rmdir(job.temp_dir,'s'), success cleanup must not erase scientific
% evidence or another invocation's private transport/status/capture directory.
ok = true; message = '';
if exist(temp_dir, 'dir') ~= 7, return; end
[status, ~] = system(['test ! -L ' local_quote(temp_dir)]);
if status ~= 0
    ok = false; message = 'Refusing cleanup through a symbolic link.'; return;
end
entries = dir(temp_dir);
for ii = 1:length(entries)
    name = entries(ii).name;
    if any(strcmp(name, {'.'; '..'; 'legacy_backend.log'})) || ...
            strncmp(name, 'pseudoct-runtime-', 17) || ...
            strncmp(name, 'pseudoct-cli.', 13) || ...
            strncmp(name, 'pseudoct-headless.', 18) || ...
            strncmp(name, 'pseudoct_v3_compiled_', 21) || ...
            strncmp(name, 'pseudoct-run-', 13)
        continue;
    end
    path = fullfile(temp_dir, name);
    try
        [link_status, ~] = system(['test -L ' local_quote(path)]);
        if link_status == 0
            [removed, detail] = system(['rm -- ' local_quote(path)]);
            if removed ~= 0, ok = false; message = detail; end
        elseif entries(ii).isdir
            [removed, detail] = rmdir(path, 's');
            if ~removed, ok = false; message = detail; end
        else
            delete(path);
        end
    catch ME
        ok = false; message = ME.message;
    end
end
end

function text = local_quote(text)
text = ['''' strrep(text, '''', '''"''"''') ''''];
end
