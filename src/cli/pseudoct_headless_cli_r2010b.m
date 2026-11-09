%PSEUDOCT_HEADLESS_CLI_R2010B Script bootstrap for the job-manager headless CLI on MATLAB R2010b.
%   Run by bin/pseudoct through MATLAB -nodisplay with a fixed bootstrap on stdin
%   (no paths or request values are interpolated). The bootstrap adds
%   src/cli to the path; this script then computes the package root (two
%   levels above its own folder), adds the src runtime folders, and calls
%   PSEUDOCT_HEADLESS_CLI. The result is left in the variable STATUS: 0 on
%   success, and 70 when the bootstrap or the CLI fails. The caller exits with
%   STATUS. Minimum supported MATLAB: R2010b (MATLAB 7.11).
try
    bootstrap_path = mfilename('fullpath');
    cli_dir = fileparts(bootstrap_path);
    install_root = fileparts(fileparts(cli_dir));
    addpath(install_root, '-begin');
    runtime_dirs = {'api'; 'cli'; 'gui'; 'orchestration'; 'backends'; ...
        'config'; 'io'; 'qc'};
    for ii = 1:length(runtime_dirs)
        path_here = fullfile(install_root, 'src', runtime_dirs{ii});
        if exist(path_here, 'dir') == 7
            addpath(genpath(path_here), '-begin');
        end
    end
    status = pseudoct_headless_cli();
catch
    status = 70;
end
