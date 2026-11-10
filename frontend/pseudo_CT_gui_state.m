function state = pseudo_CT_gui_state(fingerprint, validation, busy)
%PSEUDO_CT_GUI_STATE Run enable flags for the MATLAB frontend window.
%   STATE = PSEUDO_CT_GUI_STATE(FINGERPRINT, VALIDATION, BUSY)
%     FINGERPRINT: fingerprint of the current inputs ('' when inputs are
%                  incomplete or unreadable, from pseudo_CT_launch_request).
%     VALIDATION:  [] or struct with fields fingerprint and ok, from an earlier
%                  validation. The window passes [] (it keeps no earlier result).
%     BUSY:        true while a launcher call is running.
%   Run is disabled while busy and while the inputs cannot be read. Run itself
%   validates and then submits (for MLSC it asks for the login after validation),
%   so the window does not need an earlier validation result. When VALIDATION is
%   a struct, the submit flag is set only for the same fingerprint and a passing
%   result.
%   STATE has fields validate_enabled, submit_enabled and message. The window
%   enables Run from validate_enabled and shows message only while busy.
%   Minimum supported MATLAB: R2010b.

state = struct('validate_enabled', false, 'submit_enabled', false, ...
    'message', '');
if busy
    state.message = 'Working: the launcher is running.';
    return;
end
if isempty(fingerprint)
    state.message = 'Select a profile and an MPRAGE input.';
    return;
end
state.validate_enabled = true;
if ~isstruct(validation) || ~isfield(validation, 'fingerprint') || ...
        ~strcmp(validation.fingerprint, fingerprint)
    state.message = 'Run validates the current inputs before submitting.';
    return;
end
if validation.ok
    state.submit_enabled = true;
    state.message = 'Inputs validated. Run is enabled for these inputs.';
else
    state.message = 'Validation failed for these inputs. Correct them and validate again.';
end
end
