function state = pseudo_CT_gui_state(fingerprint, validation, busy)
%PSEUDO_CT_GUI_STATE Validate/Submit enable flags for the MATLAB frontend window.
%   STATE = PSEUDO_CT_GUI_STATE(FINGERPRINT, VALIDATION, BUSY)
%     FINGERPRINT: fingerprint of the current inputs ('' when inputs are
%                  incomplete or unreadable, from pseudo_CT_launch_request).
%     VALIDATION:  [] or struct with fields fingerprint and ok, stored by the
%                  last Validate.
%     BUSY:        true while a launcher call is running.
%   Submit is enabled only when the last validation succeeded for exactly the
%   current fingerprint. Any change to an input or option (or an input file)
%   therefore disables Submit until Validate runs again.
%   STATE has fields validate_enabled, submit_enabled and message.
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
    state.message = 'Validate the current inputs before Submit.';
    return;
end
if validation.ok
    state.submit_enabled = true;
    state.message = 'Validated. Submit is enabled for these inputs.';
else
    state.message = 'Validation failed for these inputs. Correct them and validate again.';
end
end
