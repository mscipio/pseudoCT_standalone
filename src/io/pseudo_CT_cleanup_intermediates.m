function pseudo_CT_cleanup_intermediates(pathr)
%PSEUDO_CT_CLEANUP_INTERMEDIATES Delete known intermediate files in a processing folder.
%   PSEUDO_CT_CLEANUP_INTERMEDIATES(PATHR) changes into PATHR, deletes the files
%   matching the intermediate patterns (UTE and Atlas images, seg8.mat,
%   rp_mu*.i*, new_segment*.mat, create_inverse*.mat, dartel_existing*.mat and
%   *_repos.nii), then returns to the previous folder. If an error occurs, the
%   folder is not restored. No caller remains in the current pipeline; the
%   subject temporary folder is removed by pseudo_CT_cleanup_subject_temp.
%   Side effects: deletes files in PATHR. Minimum supported MATLAB: R2010b.

current_dir = pwd;
cd(pathr);
delete('*ute*', '*UTE*','*Atlas*','*seg8.mat','rp_mu*.i*','new_segment*.mat','create_inverse*.mat','dartel_existing*.mat','*_repos.nii')
cd(current_dir);