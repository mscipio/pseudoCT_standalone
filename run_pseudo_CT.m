function report = run_pseudo_CT(varargin)
%RUN_PSEUDO_CT Public pseudoCT entrypoint; GUI, script and CLI share orchestration.
%   RUN_PSEUDO_CT(...) dispatches the existing workflow through
%   pseudo_CT_orchestrate. Current preparation and computation remain in the
%   shared compiled/current payload for local-current and MLSC-current.
%   Minimum supported MATLAB: R2010b.

entry_root = fileparts(mfilename('fullpath'));
orchestration_dir = fullfile(entry_root, 'src', 'orchestration');
if exist(orchestration_dir, 'dir') == 7
    addpath(orchestration_dir, '-begin');
end
request = struct('arguments', {varargin});
report = pseudo_CT_orchestrate('run', request);
end
