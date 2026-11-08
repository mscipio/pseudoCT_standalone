function status = pseudo_CT_write_version_log(code_version, dest_dir, varargin)
%PSEUDO_CT_WRITE_VERSION_LOG Write Pseudo_CT_AC_Version.txt into a processing folder.
%   STATUS = PSEUDO_CT_WRITE_VERSION_LOG(CODE_VERSION, DEST_DIR, OUTPUT_CONTEXT)
%   Copies CHANGELOG.md from the repository root to DEST_DIR/Pseudo_CT_AC_Version.txt.
%   If CHANGELOG.md cannot be read or the copy fails, a fallback file with
%   CODE_VERSION and the date is written instead. The function does not raise
%   errors.
%   CODE_VERSION is the version string resolved by the caller from CHANGELOG.md
%   line 1 (the caller fails closed when it cannot be read). DEST_DIR is the subject processing folder (MR_PET).
%   OUTPUT_CONTEXT is an optional logging struct; a WARN is logged when the
%   fallback is used.
%   STATUS: 1 = full CHANGELOG.md copy written; 0 = fallback written; -1 = the
%   fallback could not be written either, including when the destination cannot
%   be opened.
%   Side effects: writes DEST_DIR/Pseudo_CT_AC_Version.txt. Uses only fopen,
%   fread, fwrite and fclose. Minimum supported MATLAB: R2010b.

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
                pseudo_CT_output('ERROR', output_context, 'Version log could not be written.');
            end
        catch  %#ok<CTCH>
            status = -1;  % complete failure
            pseudo_CT_output('ERROR', output_context, 'Version log could not be written.');
        end
    end
end
