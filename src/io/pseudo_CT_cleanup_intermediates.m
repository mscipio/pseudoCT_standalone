function pseudo_CT_cleanup_intermediates(pathr)

current_dir = pwd;
cd(pathr);
delete('*ute*', '*UTE*','*Atlas*','*seg8.mat','rp_mu*.i*','new_segment*.mat','create_inverse*.mat','dartel_existing*.mat','*_repos.nii')
cd(current_dir);