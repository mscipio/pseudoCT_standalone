function status = pseudoct_standalone(varargin)
%PSEUDOCT_STANDALONE Compiled dispatcher for standalone CLI and headless runs.
%   STATUS = PSEUDOCT_STANDALONE(MODE) is the single standalone compile target
%   (built by scripts/build_application.m into standalone/pseudoct_standalone).
%   It only delegates; no serialization or validation is duplicated here:
%     prepare_validate, prepare_submit, verify_result, store_credentials
%         -> PSEUDOCT_CLI_BRIDGE(MODE), operations read from the environment.
%     headless
%         -> PSEUDOCT_HEADLESS_CLI(), which reads PSEUDOCT_REQUEST_MAT and
%            PSEUDOCT_RESULT_MAT and calls PSEUDO_CT_HEADLESS(request, result).
%   Any other mode, or a missing or extra argument, returns 70 before any
%   dispatch. No path setup is performed: the runtime is compiled in by mcc
%   (-I over src/ plus automatic dependency analysis), so repository src/ is
%   never put on the path.
%   When called as a compiled main (nargout == 0) STATUS becomes the process
%   exit code, as bin/pseudoct expects. Outside the compiled build, call with an
%   output: a bare call would exit the MATLAB session.
%   Minimum supported MATLAB: R2010b.

status = 70;
try
    if nargin ~= 1 || ~ischar(varargin{1})
        fprintf(2, 'pseudoct: standalone dispatch requires exactly one mode.\n');
    elseif strcmp(varargin{1}, 'headless')
        status = pseudoct_headless_cli();
    elseif any(strcmp(varargin{1}, {'prepare_validate'; 'prepare_submit'; ...
            'verify_result'; 'store_credentials'}))
        status = pseudoct_cli_bridge(varargin{1});
    else
        fprintf(2, 'pseudoct: unknown standalone operation.\n');
    end
catch
    % Do not expose exception text or paths; the launcher maps 70 to runtime.
    fprintf(2, 'pseudoct: standalone dispatch failed.\n');
    status = 70;
end
if ~isnumeric(status) || ~isscalar(status)
    status = 70;
end
if nargout == 0
    exit(status);
end
end
