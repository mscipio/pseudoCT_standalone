function status = pseudoct_headless_status(result)
%PSEUDOCT_HEADLESS_STATUS Process exit status of one validated headless result.
%   STATUS = PSEUDOCT_HEADLESS_STATUS(RESULT) maps a validated result struct
%   to the raw headless exit code used by pseudoct_headless_cli:
%     0   validation ready, authentication succeeded, or a submission whose
%         scientific completion is verified as 'completed' (local or remote);
%     66  authentication or group-account rejection (authenticate action);
%     2   rejected request or profile;
%     3   failed result, or a submitted result whose scientific completion is
%         not verified (dispatch or scheduler acknowledgement is not
%         completion evidence; the remote job may still be running);
%     70  any other shape.
%   Local behavior is unchanged: an unverified local submission is 3.
%   Minimum supported MATLAB: R2010b.

if strcmp(result.status, 'ready') && strcmp(result.action, 'validate')
    status = 0;
elseif strcmp(result.status, 'ready') && strcmp(result.action, 'authenticate')
    % Authentication succeeded and the account was selected; nothing was submitted.
    status = 0;
elseif strcmp(result.status, 'failed') && strcmp(result.action, 'authenticate') && ...
        any(strcmp(result.error_code, {'AUTHENTICATION_FAILED'; 'INVALID_GROUP_ACCOUNT'}))
    % Credential or account rejection: the shell may re-prompt (exit 66).
    status = 66;
elseif strcmp(result.status, 'submitted') && strcmp(result.action, 'submit')
    if strcmp(result.scientific_completion, 'completed')
        status = 0;
    else
        status = 3;
    end
elseif any(strcmp(result.error_code, ...
        {'INVALID_REQUEST'; 'PROFILE_NOT_ALLOWED'}))
    status = 2;
elseif strcmp(result.status, 'failed')
    status = 3;
else
    status = 70;
end
end
