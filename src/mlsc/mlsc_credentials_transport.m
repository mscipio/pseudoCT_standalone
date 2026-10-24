function transport = mlsc_credentials_transport(config, username, password, ...
        host_key_provider)
%MLSC_CREDENTIALS_TRANSPORT Build the credential-free MLSC callback surface.
%   TRANSPORT = MLSC_CREDENTIALS_TRANSPORT(CONFIG, USERNAME, PASSWORD,
%   HOST_KEY_PROVIDER) returns the struct of function-handle callbacks used
%   by the existing approved MLSC remote mechanism: VERIFY, QUERY_ACCOUNTS,
%   SUBMIT_SCRIPT, QUERY_SQUEUE, QUERY_SACCT, QUERY_SQUEUE_BY_NAME,
%   QUERY_SACCT_BY_NAME, CANCEL_JOB, and CLEANUP.  Credentials remain in
%   this runtime closure only and are never accepted in profiles, scripts,
%   command strings, logs, or results.
%
%   This is the shared helper extracted verbatim from RUN_PSEUDO_CT's former
%   private LOCAL_CREATE_MLSC_TRANSPORT (behavior identical).  It is used by
%   RUN_PSEUDO_CT's MLSC path and by the sixth comparison command
%   (mlsc-current-r2010b), so both reach authentication, account discovery,
%   and the Slurm lifecycle through the same transport.  No private
%   transport is duplicated.
%
%   Credentials remain in this runtime closure only.  The optional
%   HOST_KEY_PROVIDER selects the host-key trust model.  When it is empty
%   (the normal MLSC workflow), VERIFY uses the bundled Ganymed password
%   authentication path with an empty verifier, exactly like the Launchpad
%   login model: no known_hosts/fingerprint input and no authentication
%   block, after which account discovery and the Slurm lifecycle proceed
%   normally.  When an explicitly supplied, independently trusted MLSC
%   known_hosts record (character text or a zero-argument provider handle,
%   never a profile field or logged value) is given, VERIFY resolves it
%   into an in-memory Ganymed KnownHosts database and a strict
%   ServerHostKeyVerifier, and Connection.connect(verifier) runs before
%   authentication; missing, malformed, unsupported, new, changed, or
%   mismatched host keys then fail closed before authentication, account
%   discovery, or submission, and only a key reported as HOSTKEY_IS_OK is
%   accepted.  No host-key material is ever persisted or logged.
%
%   Minimum supported MATLAB: R2010b.

connection = [];
host_key_verifier = [];
verified = false;
if nargin < 4
    host_key_provider = [];
end
strict_host_key_trust = ~isempty(host_key_provider);
transport = struct('verify', @local_verify, ...
    'query_accounts', @local_query_accounts, ...
    'submit_script', @local_submit_script, ...
    'query_squeue', @local_query_squeue, ...
    'query_sacct', @local_query_sacct, ...
    'query_squeue_by_name', @local_query_squeue_by_name, ...
    'query_sacct_by_name', @local_query_sacct_by_name, ...
    'cancel_job', @local_cancel_job, ...
    'cleanup', @local_cleanup);

    function accepted = local_verify()
        accepted = false; %#ok<NASGU>
        % Idempotent: an authenticated connection from an earlier verify
        % (run_pseudo_CT and mlsc_backend both call verify) is reused rather
        % than re-opened, so no duplicate socket is ever created.
        if verified && ~isempty(connection) && ...
                isfield(connection, 'authenticated') && ...
                connection.authenticated == 1
            accepted = true;
            return;
        end
        verified = false;
        if strict_host_key_trust
            % Resolve the trusted material and bind a strict verifier BEFORE
            % any connection; a missing/malformed/unsupported source fails
            % closed here.
            verifier = [];
            try
                verifier = mlsc_host_key_trust( ...
                    config.mlsc.host, 22, host_key_provider);
            catch ME
                error('pseudo_CT:MLSCTransportRejected', ...
                    ['The supplied MLSC host-key provider could not ', ...
                     'establish strict pinned host-key trust; no ', ...
                     'connection, authentication, account query, or ', ...
                     'submission was attempted. (%s)'], ME.message);
            end
            if isempty(verifier)
                error('pseudo_CT:MLSCTransportRejected', ...
                    ['The supplied MLSC host-key provider requires a ', ...
                     'non-null strict host-key verifier; no connection or ', ...
                     'submission was attempted.']);
            end
            host_key_verifier = verifier;
        end
        % Provider-free: host_key_verifier stays empty and ssh2_main uses its
        % existing password-authentication connect branch, matching the
        % Launchpad operational model without any host-key input.
        % Open the connection: ssh2_main runs Connection.connect (strictly
        % through the verifier when one was resolved) before
        % authenticateWithPassword, so a rejected host key aborts the
        % handshake before any credential use.
        try
            connection = local_open_verified_connection();
        catch ME
            connection = [];
            host_key_verifier = [];
            if strict_host_key_trust
                error('pseudo_CT:MLSCTransportRejected', ...
                    ['Strict MLSC host-key verification or password ', ...
                     'authentication failed before account discovery; no ', ...
                     'account query or submission was attempted. (%s)'], ...
                    ME.message);
            end
            error('pseudo_CT:MLSCTransportRejected', ...
                ['MLSC password authentication failed; no account query or ', ...
                 'submission was attempted. (%s)'], ME.message);
        end
        verified = true;
        accepted = true;
    end

    function response = local_query_accounts()
        local_require_verified();
        response = local_remote_command('sshare -U -u $USER');
    end

    function response = local_submit_script(command)
        local_require_verified();
        response = local_remote_command(command);
    end

    function response = local_query_squeue(job_id)
        local_require_verified();
        response = local_remote_command(['squeue --noheader --jobs=' ...
            local_job_id_text(job_id) ' --format=%T']);
    end

    function response = local_query_sacct(job_id)
        local_require_verified();
        response = local_remote_command(['sacct --allocations --noheader ', ...
            '--parsable2 --jobs=' local_job_id_text(job_id) ...
            ' --format=JobIDRaw,State,ExitCode,Start,End,Elapsed']);
    end

    function response = local_query_squeue_by_name(job_name)
        local_require_verified();
        response = local_remote_command(['squeue --noheader --user="$USER" ', ...
            '--name=' local_job_name_text(job_name) ' --format=%A']);
    end

    function response = local_query_sacct_by_name(job_name)
        local_require_verified();
        response = local_remote_command(['sacct --allocations --noheader ', ...
            '--parsable2 --user="$USER" --name=' local_job_name_text(job_name) ...
            ' --format=JobIDRaw,State,ExitCode,Start,End,Elapsed']);
    end

    function response = local_cancel_job(job_id)
        local_require_verified();
        response = local_remote_command(['scancel -- ' local_job_id_text(job_id)]);
    end

    function response = local_remote_command(command)
        if isempty(connection)
            connection = local_open_verified_connection();
        end
        [connection, response] = ssh2_command(connection, command, 0);
    end

    function verified_connection = local_open_verified_connection()
        % Build a connection struct that carries the verifier selected for
        % this runtime: the non-null strict verifier when a host-key provider
        % was supplied, or empty for the provider-free Launchpad-style
        % password-authentication workflow, whose empty verifier routes
        % ssh2_main to its existing connect()/authenticateWithPassword
        % branch.  A supplied provider must never reach the empty-verifier
        % branch: the null verifier is rejected here.
        if strict_host_key_trust && isempty(host_key_verifier)
            error('pseudo_CT:MLSCTransportRejected', ...
                ['MLSC requires a non-null strict host-key verifier before any ', ...
                 'secure connection; no connection or submission was attempted.']);
        end
        verified_connection = ssh2_config(config.mlsc.host, username, password, 22);
        verified_connection.server_host_key_verifier = host_key_verifier;
        % Connect + authenticate now (empty command), then reuse the
        % authenticated connection for subsequent commands.
        verified_connection = ssh2(verified_connection);
        if ~(isfield(verified_connection, 'authenticated') && ...
                verified_connection.authenticated == 1)
            error('pseudo_CT:MLSCTransportRejected', ...
                ['MLSC authentication did not complete on the secure ', ...
                 'connection; no account query or submission was attempted.']);
        end
    end

    function local_require_verified()
        if ~verified
            error('pseudo_CT:MLSCTransportRejected', ...
                'MLSC transport was not verified.');
        end
    end

    function text = local_job_id_text(job_id)
        if ~isnumeric(job_id) || ~isscalar(job_id) || ~isfinite(job_id) || ...
                job_id ~= floor(job_id) || job_id < 1
            error('pseudo_CT:MLSCJobId', ...
                'A positive numeric Slurm job ID is required.');
        end
        text = num2str(job_id, '%.0f');
    end

    function text = local_job_name_text(job_name)
        if ~ischar(job_name) || isempty(job_name) || length(job_name) > 128 || ...
                isempty(regexp(job_name, '^[A-Za-z0-9_.-]+$', 'once'))
            error('pseudo_CT:MLSCJobName', ...
                'A safe MLSC correlation job name is required.');
        end
        text = job_name;
    end

    function local_cleanup()
        if ~isempty(connection)
            try
                ssh2_close(connection);
            catch
            end
        end
        connection = [];
        username = '';
        password = '';
        host_key_verifier = [];
        verified = false;
    end
end
