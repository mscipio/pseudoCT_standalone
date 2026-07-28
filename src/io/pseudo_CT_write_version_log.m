function status = pseudo_CT_write_version_log(code_version, dest_dir, varargin)
%Writes Pseudo_CT_AC_Version.txt to dest_dir by copying CHANGELOG.md.
%If CHANGELOG.md cannot be read, writes a minimal fallback with code_version
%and date. Never errors — fallback ensures pipeline continuation.
%
%code_version: resolved by caller from CHANGELOG.md line 1 (or fallback)
%dest_dir:     the subject processing directory (e.g., MR_PET/)
%
%status:  1 = full CHANGELOG.md copy succeeded
%         0 = fallback written (CHANGELOG.md unreadable or destination unwritable)
%        -1 = complete failure (even fallback could not be written)
%
%Uses only R2010b-safe I/O: fopen/fread/fwrite/fclose.
%
%Path resolution: fileparts(fileparts(fileparts(mfilename('fullpath'))))
%matches the pattern used in atlas_based_attenuation_map.m.

    output_context = struct();
    if ~isempty(varargin) && isstruct(varargin{1})
        output_context = varargin{1};
    end
    dest_file = fullfile(dest_dir, 'Pseudo_CT_AC_Version.txt');
    status = 0;  % default to fallback

    try
        %% Resolve repo root
        root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        changelog_path = fullfile(root_dir, 'CHANGELOG.md');

        fid_src = fopen(changelog_path, 'r');
        if fid_src == -1
            error('pseudo_CT_write_version_log:cannotRead', ...
                  'CHANGELOG.md not found at %s', changelog_path);
        end

        %% Copy CHANGELOG.md -> Pseudo_CT_AC_Version.txt
        content = fread(fid_src, inf, '*char')';
        fclose(fid_src);

        fid_dst = fopen(dest_file, 'w');
        if fid_dst == -1
            error('pseudo_CT_write_version_log:cannotWrite', ...
                  'Cannot write to %s', dest_file);
        end
        fwrite(fid_dst, content, 'char');
        fclose(fid_dst);

        status = 1;  % full copy succeeded

    catch ME  %#ok<CTCH>
        %% Graceful fallback — write version + date, never error
        % Legacy output: disp(['WARNING: pseudo_CT_write_version_log fallback — CHANGELOG.md ' ...
        %       'copy failed: ' ME.message]);
        pseudo_CT_output('WARN', output_context, ...
            'Version log fallback used: %s', ME.message);
        try
            fid = fopen(dest_file, 'w');
            if fid ~= -1
                fprintf(fid, 'Pseudo-CT code version: %s\nDate: %s\n', ...
                        code_version, date);
                fclose(fid);
            else
                status = -1;  % complete failure
                % Legacy output: disp(['ERROR: pseudo_CT_write_version_log cannot write ' ...
                %       'Pseudo_CT_AC_Version.txt to ' dest_file]);
                pseudo_CT_output('ERROR', output_context, 'Version log could not be written.');
            end
        catch  %#ok<CTCH>
            status = -1;  % complete failure
            % Legacy output: disp(['ERROR: pseudo_CT_write_version_log cannot write ' ...
            %       'Pseudo_CT_AC_Version.txt to ' dest_file]);
            pseudo_CT_output('ERROR', output_context, 'Version log could not be written.');
        end
    end
end
