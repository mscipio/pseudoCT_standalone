classdef pseudo_CT_subject_outcome < handle
%PSEUDO_CT_SUBJECT_OUTCOME Guarantee one terminal line per subject.
%   Create one outcome per subject before its processing boundary and guard it:
%       outcome = pseudo_CT_subject_outcome(context, jobs(jj).subject_started);
%       guard = onCleanup(@() pseudo_CT_subject_outcome.release(outcome));
%   Call outcome.markClosed() once the subject has written its own SUCCESS or
%   ERROR line. Clear the guard at the end of the iteration. If the boundary is
%   left without a closed outcome, release writes exactly one subject-scoped
%   ERROR. Logging failures are suppressed so they never mask the propagating
%   error. Minimum supported MATLAB: R2010b.

    properties
        Closed = false
        Recorded = false
        Context
        Started
    end

    methods
        function obj = pseudo_CT_subject_outcome(context, started)
            obj.Context = context;
            obj.Started = started;
        end

        function markClosed(obj, outcome, source)
            % Optional OUTCOME ('SUCCEEDED', 'FAILED' or 'CANCELLED') appends one
            % native run record, at most once per subject. Callers pass it only
            % after the subject's terminal state is known: for MLSC, the Slurm
            % job observed terminal (so the remote worker is no longer writing);
            % for Local, the orchestrator is the only writer. Advisory: never throws.
            obj.Closed = true;
            if obj.Recorded || nargin < 2 || isempty(outcome)
                return;
            end
            try
                target = pseudo_CT_scientific_event_target(obj.Context);
                if isempty(target.path)
                    return;
                end
                switch outcome
                    case 'SUCCEEDED'
                        message = 'Subject completed successfully.';
                    case 'CANCELLED'
                        message = 'Subject cancelled.';
                    otherwise
                        message = 'Subject failed.';
                end
                if pseudo_CT_scientific_event(target, struct('event_type', 'run', ...
                        'outcome', outcome, 'message', message, 'source', source))
                    obj.Recorded = true;
                end
            catch %#ok<CTCH>
            end
        end
    end

    methods (Static)
        function release(obj)
            if obj.Closed
                return;
            end
            try
                pseudo_CT_output('ERROR', obj.Context, ...
                    'Subject did not complete (elapsed %s).', ...
                    pseudo_CT_subject_outcome.elapsedText(toc(obj.Started)));
            catch %#ok<CTCH>
            end
        end
    end

    methods (Static, Access = private)
        function value = elapsedText(seconds)
        % Same formatting as local_elapsed in pseudo_CT_run_lifecycle.
        seconds = max(0, floor(seconds));
        hours = floor(seconds / 3600);
        minutes = floor(rem(seconds, 3600) / 60);
        seconds = rem(seconds, 60);
        value = sprintf('%02d:%02d:%02d', hours, minutes, seconds);
        end
    end
end
