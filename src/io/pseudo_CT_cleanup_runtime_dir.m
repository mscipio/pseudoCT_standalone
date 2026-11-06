function pseudo_CT_cleanup_runtime_dir(path)
%PSEUDO_CT_CLEANUP_RUNTIME_DIR Remove only an invocation-owned ephemeral tree.
% Retained scientific files stay put. Never call this for a subject directory.
[~, name] = fileparts(path);
if ~strncmp(name, 'pseudoct-runtime-', 17), return; end
try
    % Cancellation may unwind the MATLAB monitor before its owned producer
    % has stopped. Never remove a live child's cache/status directory. The
    % launch wrapper sees monitor.closed and finishes cleanup after child EOF.
    pid_file = fullfile(path, 'runner.pid');
    fid = fopen(pid_file, 'r');
    if fid ~= -1
        pid = fscanf(fid, '%d', 1); fclose(fid);
        done = exist(fullfile(path, 'runner.exit'), 'file') == 2 || ...
            exist(fullfile(path, 'legacy_backend.exit'), 'file') == 2;
        if ~done && ~isempty(pid) && pid > 0
            [alive, ~] = system(sprintf('kill -0 %d 2>/dev/null', pid));
            if alive == 0
                fid = fopen(fullfile(path, 'monitor.closed'), 'w');
                if fid ~= -1, fclose(fid); end
                done = exist(fullfile(path, 'runner.exit'), 'file') == 2 || ...
                    exist(fullfile(path, 'legacy_backend.exit'), 'file') == 2;
                if ~done, return; end
            end
        end
    end
    entries = dir(path);
    retained = false;
    for ii = 1:length(entries)
        name = entries(ii).name;
        if any(strcmp(name, {'.'; '..'})), continue; end
        if strncmp(name, 'pseudoct_v3_compiled_', 21) && ~entries(ii).isdir
            retained = true;
            continue;
        end
        % rm does not follow directory symlinks. PATH is this invocation's
        % exclusive allocation; never recurse into MR_PET/tmp itself.
        file = fullfile(path, name);
        quoted = ['''' strrep(file, '''', '''"''"''') ''''];
        system(['rm -rf -- ' quoted]);
    end
    if ~retained, rmdir(path); end
catch %#ok<CTCH>
    % Cleanup must never replace scientific failure/cancellation diagnostics.
end
end
