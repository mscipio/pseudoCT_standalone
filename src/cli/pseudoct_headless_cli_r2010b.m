% Fixed standalone CLI bootstrap for MATLAB R2010b; invoked through stdin.
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
