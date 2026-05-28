% Date: 06/04/2013;
% Name: convert_dicom_i_2_nii.m
% Function to convert dicom of flat (*.i) into nii.  This function was
% already running in run_atlas_based_AC_mMR.m before as a subfunction

function [Pnew, dcmnew] = convert_dicom_i_2_nii(P, nii_name, dir_final)

%given_nii_name = nii_name;
fname = 1;% If there is a filename as input argument;
if nargin < 3, dir_final = ''; end
if (nargin < 2) | ~isstr(nii_name) | (length(nii_name) == 0) , nii_name = 'MPRAGE_spm.nii'; fname = 0; end
has_dir_final = ischar(dir_final) & ~isempty(strtrim(dir_final));

if has_dir_final & ~isdir(dir_final)
    [success, msg] = mkdir(dir_final);
    if success == 0
        error('convert_dicom_i_2_nii:CreateOutputDirFailed', 'Could not create destination folder %s: %s', dir_final, msg);
    end
end

Pnew = ''; % If image is already a *.nii!
dcmnew = '';

[nf, aux] = size(P);
current_dir = pwd;

for ii=1:nf
    [pathd,fnd,extd] = fileparts(deblank(P(ii, :)));
    str_f = strfind(pathd, filesep); ll = length(str_f);
    cd(pathd);
%     if length(strfind(extd, '.ima')) | length(strfind(extd, '.IMA'))
%         disp('Converting the *.IMA into *.dcm');
%         renameima2dcm; % To convert the *.ima into *.dcm!
%         list_dcm = dir('*.dcm');
%         [aux,fnd,extd] = fileparts(list_dcm(1).name);
%     end
    if length(strfind(extd, '.dcm')) | length(strfind(extd, '.DCM')) | length(strfind(extd, '.ima')) | length(strfind(extd, '.IMA')) | (length(strfind(extd, '.i'))==0 & (length(strfind(extd, '.nii'))==0) )
        disp('Converting the *.dcm into *.nii');
%         dcm2flat(strcat(fnd, extd)); % This is Dan's method! Not good if
%         list_i = dir('*.i'); % using Spencer transform into Dicom!
%         [aux,fnd,extd] = fileparts(list_i(1).name);
        % Using SPM to convert dicom into nifty!
        switch extd
            case {'.ima'}
                list_dcm = dir('*.ima');
            case '.IMA'
                list_dcm = dir('*.IMA');
            case '.dcm'
                list_dcm = dir('*.dcm');
            case '.DCM'
                list_dcm = dir('*.DCM');
            otherwise
                list_dcm = dir(strcat(fnd(1:3), '*')); % For those special cases, like for Julie's images
        end
        dcmnew = fullfile(pathd, list_dcm(1).name);
        % Check if it is PET:
        di = dicominfo(deblank(P(ii, :)));
        if ~isfield(di, 'Modality') % Added a fake Ph modality (for phantom);
            di.Modality = 'Ph';
        end
        if strcmp(di.Modality, 'PT') | strcmp(di.Modality, 'PET')
            [aux] = convert_4D_PET_dicom_2nii(deblank(P(ii, :)));
            %if (nargin < 2) | ~isstr(given_nii_name) | (length(given_nii_name) == 0), nii_name = 'PET_4D.nii'; end
            if has_dir_final
                if fname
                    aux2 = fullfile(dir_final, nii_name);
                else
                    [pathm, fm, extm] = fileparts(aux);
                    aux2 = fullfile(dir_final, strcat(fm, extm));
                end
                [pathm, fm, extm] = fileparts(aux);
                [pathm2, fm2, extm2] = fileparts(aux2);
                movefile(aux, aux2);
                copyfile(fullfile(pathm, 'Frame_info.txt'), fullfile(dir_final, sprintf('Frame_info_%s.txt', fm2))); % Copy the Frame_info.txt into Frame_info_<name of nii>.txt
                aux = aux2;
            end
            Pnew(ii, 1:length(aux)) = aux;
            continue
        else % It is MR (or CT or similar)
            dcm_fn = strvcat(list_dcm.name);
            hdr = spm_dicom_headers(dcm_fn, true);
            out = spm_dicom_convert(hdr,'all','flat','nii');
            aux = fullfile(pathd, 'Temp_spm.nii'); % Make sure spm_dicom_convert contains in line 483 the following: fname = fullfile(pwd, 'Temp_spm.nii');
        end
        aux2 = fullfile(pathd(1:str_f(end-1)), 'MR_PET');
        if ~has_dir_final & ~length(strfind(aux, 'MR_PET')) & ~isdir(aux2)
            [success, msg] = mkdir(aux2);
            if success == 0
                error('convert_dicom_i_2_nii:CreateImplicitMrPetFailed', 'Could not create implicit MR_PET folder %s: %s', aux2, msg);
            end
        end
        if has_dir_final
            aux2 = fullfile(dir_final, nii_name);
            movefile(aux, aux2);
            Pnew(ii, 1:length(aux2)) = aux2;
        elseif length(strfind(aux, 'MR_PET'))
            Pnew(ii, 1:length(aux)) = aux;
        elseif isdir(aux2)
            aux2 = fullfile(aux2, nii_name);
            movefile(aux, aux2);
            Pnew(ii, 1:length(aux2)) = aux2;
        else
            disp(sprintf('Neither the destination folder %s nor MR_PET does exits!!', dir_final));
            Pnew(ii, 1:length(aux)) = aux;
        end
    end
    if length(strfind(extd, '.i')) & length(strfind(lower(extd), '.ima')) == 0
        disp('Converting the *.i into *.nii');
        gen_mr_anz_hdr(strcat(fnd, extd), 0, 'nii');
        aux = fullfile(pathd, strcat(fnd, '.nii'));
        aux2 = fullfile(pathd(1:str_f(end-1)), 'MR_PET');
        if ~has_dir_final & ~length(strfind(aux, 'MR_PET')) & ~isdir(aux2)
            [success, msg] = mkdir(aux2);
            if success == 0
                error('convert_dicom_i_2_nii:CreateImplicitMrPetFailed', 'Could not create implicit MR_PET folder %s: %s', aux2, msg);
            end
        end
        if has_dir_final
            aux2 = fullfile(dir_final, nii_name);
            movefile(aux, aux2);
            Pnew(ii, 1:length(aux2)) = aux2;
        elseif length(strfind(aux, 'MR_PET'))
            Pnew(ii, 1:length(aux)) = aux;
        elseif isdir(aux2)
            movefile(aux, aux2);
            aux2 = fullfile(aux2, strcat(fnd, '.nii'));
            Pnew(ii, 1:length(aux2)) = aux2;
        else
            disp(sprintf('Neither the destination folder %s nor MR_PET does exits! Program quit!', dir_final));
        end
    end
    if length(strfind(extd, '.nii'))
        aux = P(ii, :);
        Pnew(ii, 1:length(aux)) = aux;
    end
end

cd(current_dir);

return