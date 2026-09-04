function test_mlsc_ssh2_compatibility()
%TEST_MLSC_SSH2_COMPATIBILITY Verify the non-destructive SSH2 audit gate.
%
% Every check here is credential-free and network-free: no MLSC connection,
% no Slurm command, no prompt, no credentials, and no trusted host-key
% material is ever read, written, or transmitted. The normal MLSC workflow
% is provider-free (Launchpad-style dialog, password authentication,
% sshare account discovery, Slurm lifecycle); a missing provider is not a
% blocker. The strict-verifier checks below exercise the OPTIONAL
% development/testing opt-in using the bundled Ganymed classes with
% synthetic, well-formed PUBLIC test key blobs only (public key material
% carries no secret). The exact operator identity from the manual
% diagnostic is deliberately never written into this file, into
% documentation, or into any committed content; the username check below
% rebuilds the needle dynamically so this source stays free of the literal
% identity.

root_dir = fileparts(fileparts(mfilename('fullpath')));
scripts_dir = fullfile(root_dir, 'scripts');
ssh2_dir = fullfile(root_dir, 'ssh2_v2_m1_r5', 'ssh2_v2_m1_r5');
mlsc_dir = fullfile(root_dir, 'src', 'mlsc');
addpath(scripts_dir, '-begin');

%% ---------------------------------------------------------------- gate report
report = run_mlsc_ssh2_compatibility();
assert(strcmp(report.schema, 'pseudo-CT.mlsc-ssh2-compatibility/v2'));
assert(strcmp(report.target_host, 'mlsc.nmr.mgh.harvard.edu'));
assert(report.target_port == 22);
assert(strcmp(report.command, 'true'));
assert(strcmp(report.normal_path, 'PROVIDER_FREE'));
assert(strcmp(report.live_validation, 'NOT_ATTEMPTED'));
assert(strcmp(report.host_key_verification, 'OPT_IN'));
assert(strcmp(report.command_exit_status, 'SEAM_VERIFIED'));
assert(strcmp(report.authentication, 'PROVEN'));
assert(strcmp(report.crypto_compatibility, 'PROVEN'));
assert(strcmp(report.status, 'PASS_LOCAL_AUDIT'));
assert(~isfield(report, 'username') && ~isfield(report, 'password'));
assert(~isfield(report, 'passphrase') && ~isfield(report, 'secret'));
assert(~isfield(report, 'private_key') && ~isfield(report, 'known_hosts'));
assert(~isempty(strfind(report.credential_source, 'not supplied')));
assert(~isempty(strfind(report.host_key_material, 'not supplied')));
assert(~isempty(strfind(report.host_key_material, 'optional')));

% The proven manual diagnostic: negotiation, authentication, and execution
% through the bundled Ganymed library, returning the login hostname. The
% operator identity stays withheld and is never claimed to be published.
assert(strcmp(report.manual_diagnostic_target, 'mlsc.nmr.mgh.harvard.edu'));
assert(strcmp(report.manual_diagnostic_command, 'hostname; whoami'));
assert(strcmp(report.manual_diagnostic_login_hostname, ...
    'mlsc-login.nmr.mgh.harvard.edu'));
assert(strcmp(report.manual_diagnostic_result, 'PROVEN'));
assert(~isempty(strfind(report.manual_diagnostic_identity, 'withheld')));
assert(~isempty(strfind(report.manual_diagnostic_scope, 'not a strictly verified')));
assert(~isempty(strfind(report.manual_diagnostic_scope, 'not a substitute')));
assert(~strcmp(report.manual_diagnostic_command, report.command));

% Revised contract: the credential-free local audit passes with zero
% blockers. A missing host-key provider is no longer reported as a
% normal-workflow trusted-material blocker; strict verification is
% optional, the numeric exit-status seam is verified from source, crypto
% is PROVEN, and the pending live items are evidence, not blockers.
assert(isempty(report.blockers));
has_opt_in_evidence = false;
has_normal_path_evidence = false;
has_exit_status_evidence = false;
has_live_pending_evidence = false;
for ii = 1:length(report.evidence)
    has_opt_in_evidence = has_opt_in_evidence || ...
        ~isempty(strfind(report.evidence{ii}, 'HOST_KEY_VERIFICATION'));
    has_normal_path_evidence = has_normal_path_evidence || ...
        ~isempty(strfind(report.evidence{ii}, 'NORMAL_PATH'));
    has_exit_status_evidence = has_exit_status_evidence || ...
        ~isempty(strfind(report.evidence{ii}, 'COMMAND_EXIT_STATUS'));
    has_live_pending_evidence = has_live_pending_evidence || ...
        ~isempty(strfind(report.evidence{ii}, 'CREDENTIAL_FREE')) || ...
        ~isempty(strfind(report.evidence{ii}, 'LIVE_NOT_PERFORMED_BY_HARNESS'));
end
assert(has_opt_in_evidence);
assert(has_normal_path_evidence);
assert(has_exit_status_evidence);
assert(has_live_pending_evidence);
local_assert_report_invariants(report);

% The explicit live selector stays fail-safe: the harness never prompts,
% connects, or submits, so a requested live check is declined by design
% and never reported as performed or blocked on trusted material.
live_report = run_mlsc_ssh2_compatibility('live');
assert(live_report.live_requested);
assert(strcmp(live_report.live_validation, 'NOT_ATTEMPTED'));
assert(strcmp(live_report.status, 'PASS_LOCAL_AUDIT'));
assert(isempty(live_report.blockers));
local_assert_report_invariants(live_report);

argument_failed = false;
try
    run_mlsc_ssh2_compatibility('unsupported');
catch ME
    argument_failed = strcmp(ME.identifier, ...
        'pseudo_CT:SSH2HarnessArguments');
end
assert(argument_failed);

harness_source = local_read_text(fullfile(scripts_dir, ...
    'run_mlsc_ssh2_compatibility.m'));
assert(isempty(strfind(harness_source, 'ssh2_config(')));
assert(isempty(strfind(harness_source, 'ssh2_command(')));
assert(isempty(strfind(harness_source, 'javaaddpath(')));
assert(isempty(strfind(harness_source, 'system(')));
assert(isempty(strfind(harness_source, 'scp_put(')));
% The audit itself never prompts for or accepts credentials.
assert(isempty(strfind(harness_source, 'passwordEntryDialog(')));
assert(isempty(strfind(harness_source, local_operator_needle())));

%% --------------------------- optional strict verifier seam (dev/testing opt-in)
% Build a strict verifier from synthetic, publicly-generated trusted
% known_hosts text. This exercises the opt-in path only: it is never a
% requirement of the normal workflow. These checks load the bundled Ganymed
% classes in memory only; no socket, credential, or MLSC interaction
% occurs.
addpath(mlsc_dir, '-begin');
addpath(ssh2_dir, '-begin');
pinned_host = 'mlsc.nmr.mgh.harvard.edu';
blob_a = 'AAAAB3NzaC1yc2EAAAADAQABAAAACQDA/+4A3Q3wDQ==';
blob_b = 'AAAAB3NzaC1yc2EAAAADAQABAAAACQC+796tvu8EIA==';
trusted_line = [pinned_host ' ssh-rsa ' blob_a char(10)];

[verifier, host_key_source] = mlsc_host_key_trust(pinned_host, 22, ...
    trusted_line);
assert(isa(verifier, 'ch.ethz.ssh2.ServerHostKeyVerifier'));
assert(strcmp(host_key_source, 'runtime text'));
[verifier_fn, host_key_source_fn] = mlsc_host_key_trust(pinned_host, 22, ...
    @() trusted_line);
assert(isa(verifier_fn, 'ch.ethz.ssh2.ServerHostKeyVerifier'));
assert(strcmp(host_key_source_fn, 'runtime provider'));
key_a = ch.ethz.ssh2.crypto.Base64.decode(java.lang.String(blob_a).toCharArray());
key_b = ch.ethz.ssh2.crypto.Base64.decode(java.lang.String(blob_b).toCharArray());

% Trusted key: accepted. Mismatched (changed) key, wrong host, wrong port,
% unsupported algorithm, and unparseable blobs are all rejected by the
% strict verifier without any network access.
assert(verifier.verifyServerHostKey(pinned_host, 22, 'ssh-rsa', key_a) ...
    == true, 'Trusted pinned key must verify OK.');
assert(verifier.verifyServerHostKey(pinned_host, 22, 'ssh-rsa', key_b) ...
    == false, 'A changed/mismatched key must fail closed.');
assert(verifier.verifyServerHostKey('malicious.example.com', 22, ...
    'ssh-rsa', key_a) == false, 'A different host must fail closed.');
assert(verifier.verifyServerHostKey(pinned_host, 2222, 'ssh-rsa', key_a) ...
    == false, 'A different port must fail closed.');
assert(verifier.verifyServerHostKey(pinned_host, 22, 'ssh-ed25519', key_a) ...
    == false, 'An unsupported host-key algorithm must fail closed.');
assert(verifier.verifyServerHostKey(pinned_host, 22, 'ssh-rsa', ...
    int8([1 2 3])) == false, 'An unparseable key blob must fail closed.');

% Missing, blank, and unsupported trust material fail closed before any
% connection could be attempted.
local_assert_host_key_error(@() mlsc_host_key_trust(pinned_host, 22, []), ...
    'pseudo_CT:MLSCSSH2HostKeyMissing', 'missing material');
local_assert_host_key_error(@() mlsc_host_key_trust(pinned_host, 22, ...
    ['   ' char(10) '  ']), 'pseudo_CT:MLSCSSH2HostKeyMissing', ...
    'blank material');
local_assert_host_key_error(@() mlsc_host_key_trust(pinned_host, 22, ...
    [pinned_host ' ecdsa-sha2-nistp256 ' blob_a char(10)]), ...
    'pseudo_CT:MLSCSSH2HostKeyUnsupported', 'unsupported algorithm');
local_assert_host_key_error(@() mlsc_host_key_trust(pinned_host, 22, ...
    ['other.invalid ssh-rsa ' blob_a char(10)]), ...
    'pseudo_CT:MLSCSSH2HostKeyUnsupported', 'material for another host');
local_assert_host_key_error(@() mlsc_host_key_trust(pinned_host, 22, ...
    [pinned_host ' ssh-rsa not-base64!!!' char(10)]), ...
    'pseudo_CT:MLSCSSH2HostKeyMalformed', 'malformed material');

%% ------------------------------------- verifier reaches Connection.connect
% ssh2_main must hand the supplied verifier to Connection.connect(...)
% BEFORE authentication, and the MLSC runtime must refuse a null verifier.
ssh2_main_source = local_read_text(fullfile(ssh2_dir, 'ssh2_main.m'));
assert(~isempty(ssh2_main_source));
pos_guard = strfind(ssh2_main_source, ...
    'isfield(ssh2_struct,''server_host_key_verifier''');
pos_verified_connect = strfind(ssh2_main_source, ...
    'ssh2_struct.server_host_key_verifier);');
pos_password_auth = strfind(ssh2_main_source, 'authenticateWithPassword');
assert(~isempty(pos_guard) && ~isempty(pos_verified_connect) && ...
    ~isempty(pos_password_auth));
assert(pos_guard(1) < pos_verified_connect(1) && ...
    pos_verified_connect(1) < pos_password_auth(1), ...
    'Connection.connect(verifier) must precede authentication.');
% The empty-verifier legacy branch stays available BEFORE authentication so
% the provider-free normal path connects exactly like the Launchpad model.
pos_legacy_connect = strfind(ssh2_main_source, ...
    'ssh2_struct.connection.connect();');
assert(~isempty(pos_legacy_connect) && ...
    pos_guard(1) < pos_legacy_connect(1) && ...
    pos_legacy_connect(1) < pos_password_auth(1), ...
    'The empty-verifier connect branch must precede authentication.');
entry_source = local_read_text(fullfile(root_dir, 'run_pseudo_CT.m'));
pos_attach = strfind(entry_source, ...
    'verified_connection.server_host_key_verifier = host_key_verifier;');
pos_open = strfind(entry_source, 'ssh2(verified_connection)');
assert(~isempty(pos_attach) && ~isempty(pos_open));
assert(pos_attach(1) < pos_open(1), ...
    'The MLSC runtime must attach the verifier before connecting.');
assert(~isempty(strfind(entry_source, ...
    'requires a non-null strict host-key verifier')), ...
    'The MLSC runtime must reject a null verifier fail-closed.');
assert(~isempty(strfind(entry_source, 'mlsc_host_key_trust(')));

%% --------------------------- provider-free normal-path seam (network-free)
% Smallest network-free source audit of the revised normal-path contract:
% the empty provider default keeps strict trust opt-in, the MLSC dispatch
% runs the Launchpad-style dialog before transport creation and account
% discovery, and a missing provider never blocks authentication or the
% sshare/Slurm flow. No connection, prompt, or Slurm command is performed.
pos_provider_default = strfind(entry_source, ...
    'p.addParamValue(''mlsc_host_key_provider'', []');
pos_strict_flag = strfind(entry_source, ...
    'strict_host_key_trust = ~isempty(host_key_provider);');
pos_conditional_guard = strfind(entry_source, ...
    'if strict_host_key_trust && isempty(host_key_verifier)');
pos_mlsc_dialog = strfind(entry_source, ...
    '''Login for: %s'', config.mlsc.host');
pos_transport_create = strfind(entry_source, ...
    'transport = local_create_mlsc_transport(config, USERNAME,');
pos_account_flow = strfind(entry_source, 'mlsc_parse_slurm_accounts(');
pos_sshare = strfind(entry_source, 'sshare -U -u $USER');
assert(~isempty(pos_provider_default) && ~isempty(pos_strict_flag) && ...
    ~isempty(pos_conditional_guard) && ~isempty(pos_mlsc_dialog) && ...
    ~isempty(pos_transport_create) && ~isempty(pos_account_flow) && ...
    ~isempty(pos_sshare));
% Strict trust (and its null-verifier rejection) is reachable only through
% the provider flag, so an absent provider can never block authentication.
assert(pos_strict_flag(1) < pos_conditional_guard(1), ...
    'The null-verifier rejection must be conditional on a supplied provider.');
% Dialog, then provider-free transport creation, then account discovery.
assert(pos_mlsc_dialog(1) < pos_transport_create(1) && ...
    pos_transport_create(1) < pos_account_flow(1), ...
    ['The MLSC normal path must run dialog, then transport, then ', ...
     'account discovery.']);
% The provider must never become a required profile field.
profile_source = [local_read_text(fullfile(root_dir, 'src', 'config', ...
    'profiles', 'mlsc.m')), local_read_text(fullfile(root_dir, 'src', ...
    'config', 'profiles', 'mlsc_mprage_only.m'))];
assert(isempty(strfind(profile_source, 'mlsc_host_key_provider')), ...
    'The host-key provider must not appear in any MLSC profile.');

%% ------------------------------------------ race-safe numeric exit status
exit_call = strfind(ssh2_main_source, 'ssh2_collect_exit_status(');
exit_close = strfind(ssh2_main_source, ...
    'ssh2_struct.command_session.close();');
assert(~isempty(exit_call) && ~isempty(exit_close));
assert(exit_call(1) < exit_close(1), ...
    'Exit status must be collected before the session is closed.');
pos_wait = strfind(ssh2_main_source, 'command_session.waitForCondition');
pos_get = strfind(ssh2_main_source, 'command_session.getExitStatus();');
assert(~isempty(pos_wait) && ~isempty(pos_get));
assert(pos_wait(1) < pos_get(1), ...
    'The bounded EXIT_STATUS/CLOSED wait must precede getExitStatus().');
assert(~isempty(strfind(ssh2_main_source, ...
    'command_success = (exit_status == 0)')), ...
    'Only numeric status 0 may map to success.');
assert(isempty(strfind(ssh2_main_source, 'command_success = 1;')), ...
    'Success must never be asserted without a numeric zero status.');
% The stdout-drain loop must not touch the success decision at all.
pos_stdout = strfind(ssh2_main_source, 'StreamGobbler(');
pos_status_section = strfind(ssh2_main_source, ...
    'COLLECT THE NUMERIC EXIT STATUS');
assert(~isempty(pos_stdout) && ~isempty(pos_status_section));
drain_region = ssh2_main_source(pos_stdout(1):pos_status_section(1));
assert(isempty(strfind(drain_region, 'command_success')), ...
    'Stdout handling must never override or imply the exit status.');
% Legacy one-/two-output ssh2_command callers keep working (verified
% functionally below via a mocked transport, never a live connection).
command_source = local_read_text(fullfile(ssh2_dir, 'ssh2_command.m'));
assert(~isempty(strfind(command_source, 'nargout > 2')));
assert(~isempty(strfind(command_source, ...
    'command_status = ssh2_struct.command_exit_status;')));

%% ---------------------------------- ssh2_command 1/2/3-output compatibility
local_check_ssh2_command_outputs(ssh2_dir);

%% --------------------------------------------- preserved credential dialog UX
% Preserve the deployed Launchpad credential UX rather than introducing a
% command-line, file-based, or stored credential path. The MLSC runtime uses
% the same enterUserName dialog shape.
login_source = local_read_text(fullfile(root_dir, 'src', 'remote', ...
    'ssh_login_pseudo_CT.m'));
assert(~isempty(strfind(login_source, 'passwordEntryDialog')));
assert(~isempty(strfind(login_source, '''enterUserName'', true')));
assert(~isempty(strfind(entry_source, ...
    'passwordEntryDialog(''enterUserName'', true')));

%% ------------------------------------------------------ operator docs gates
runbook_source = local_read_text(fullfile(root_dir, 'docs', ...
    'mlsc-ssh2-compatibility.md'));
assert(~isempty(strfind(runbook_source, 'mlsc.nmr.mgh.harvard.edu')));
assert(~isempty(strfind(runbook_source, 'passwordEntryDialog')));
assert(~isempty(strfind(runbook_source, 'pinned')));
assert(~isempty(strfind(runbook_source, 'true')));
% The runbook records the proven diagnostic and no longer claims the
% crypto/hostname compatibility is unproven. The remaining needles track
% the revised runbook vocabulary: the credential-free audit result is
% PASS_LOCAL_AUDIT with the live checks NOT_ATTEMPTED, and the old
% trusted-material blocker wording (a BLOCKED status, blocked-on-trusted
% phrasing, or ssh-keyscan host-key instructions) must not return.
assert(~isempty(strfind(runbook_source, 'mlsc-login.nmr.mgh.harvard.edu')));
assert(~isempty(strfind(runbook_source, 'PROVEN')));
assert(~isempty(strfind(runbook_source, 'hostname; whoami')));
assert(~isempty(strfind(runbook_source, 'PASS_LOCAL_AUDIT')));
assert(~isempty(strfind(runbook_source, 'NOT_ATTEMPTED')));
assert(isempty(strfind(runbook_source, 'BLOCKED')));
assert(isempty(strfind(runbook_source, 'blocked on trusted')));
assert(isempty(strfind(runbook_source, 'ssh-keyscan')));
assert(isempty(strfind(runbook_source, 'remains unproven')));
assert(isempty(strfind(runbook_source, 'not proven')));
assert(isempty(strfind(runbook_source, local_operator_needle())));
assert(isempty(regexp(runbook_source, ...
    ['true[^\n.]*\b(succeeded|passed)'], 'once')));

pipeline_source = local_read_text(fullfile(root_dir, 'docs', ...
    'pipeline-mlsc.md'));
assert(~isempty(strfind(pipeline_source, 'mlsc-login.nmr.mgh.harvard.edu')));
assert(~isempty(strfind(pipeline_source, 'PROVEN')));
assert(isempty(strfind(pipeline_source, 'remains unproven')));
assert(isempty(strfind(pipeline_source, local_operator_needle())));

test_source = local_read_text(fullfile(scripts_dir, ...
    'test_mlsc_ssh2_compatibility.m'));
assert(isempty(strfind(test_source, local_operator_needle())));
assert(isempty(strfind(harness_source, local_operator_needle())));

readme_source = local_read_text(fullfile(root_dir, 'README.md'));
assert(isempty(strfind(readme_source, local_operator_needle())));

fprintf(['=== MLSC SSH2 compatibility tests passed: normal MLSC path is ', ...
    'provider-free, strict verifier is an opt-in that fails closed, ', ...
    'numeric exit status is wired, crypto is PROVEN by the manual ', ...
    'diagnostic, the live true check is not performed by the harness, ', ...
    'no identity published ===\n']);
end

%% ------------------------------------------------------------------ helpers
function text = local_read_text(file_path)
fid = fopen(file_path, 'r');
if fid == -1
    error('test_mlsc_ssh2_compatibility:Read', ...
        'Could not read %s.', file_path);
end
text = fread(fid, inf, '*char')';
fclose(fid);
end

function needle = local_operator_needle()
% Rebuild the withheld operator-username needle without ever writing the
% literal identity into this committed file.
needle = [char([109 117]) num2str(512)];
end

function local_assert_report_invariants(report)
% Shared invariants for every gate report (default and live): crypto
% compatibility is never claimed missing, the normal workflow is never
% reported as blocked on trusted material, the secure true command is
% never claimed to have succeeded, and the operator identity is never
% published.
strings = local_report_strings(report);
for ii = 1:length(strings)
    assert(isempty(strfind(lower(strings{ii}), 'unproven')), ...
        'The gate report must no longer claim crypto/hostname compatibility ...');
    assert(isempty(strfind(strings{ii}, 'BLOCKED')), ...
        ['The report must not block the normal workflow on trusted ', ...
         'host-key material.']);
    assert(isempty(strfind(strings{ii}, local_operator_needle())), ...
        'The gate report must not publish the operator identity.');
    assert(isempty(regexp(strings{ii}, ...
        ['true[^\n]*(succeeded|returned status 0\b|gate passed)'], 'once')), ...
        'The report must never claim the secure true command succeeded.');
end
end

function strings = local_report_strings(report)
strings = {};
fields = fieldnames(report);
for ii = 1:length(fields)
    value = report.(fields{ii});
    if ischar(value)
        strings{end+1} = value; %#ok<AGROW>
    elseif iscell(value)
        for kk = 1:numel(value)
            if ischar(value{kk})
                strings{end+1} = value{kk}; %#ok<AGROW>
            end
        end
    end
end
end

function local_assert_host_key_error(fun, expected_id, label)
failed = false;
try
    feval(fun);
catch ME
    failed = strcmp(ME.identifier, expected_id);
    if ~failed
        error('test_mlsc_ssh2_compatibility:WrongError', ...
            'The %s case failed with %s instead of %s.', ...
            label, ME.identifier, expected_id);
    end
end
assert(failed, 'The %s case must fail closed.', label);
end

function local_check_ssh2_command_outputs(ssh2_dir)
% Exercise the real ssh2_command through a mocked transport: the mock
% replaces only the local 'ssh2' dispatch, so no connection, credential, or
% network access occurs. This proves 1/2/3-output compatibility and that a
% success-looking (or empty) stdout never overrides the numeric status.
mock_dir = fullfile(tempdir, 'pct_mlsc_ssh2_mock');
if ~exist(mock_dir, 'dir')
    assert(mkdir(mock_dir));
end
mock_file = fullfile(mock_dir, 'ssh2.m');
fid = fopen(mock_file, 'w');
assert(fid ~= -1, 'Could not create the mocked transport.');
fprintf(fid, 'function out = ssh2(varargin)\nout = varargin{1};\nend\n');
fclose(fid);

restore = path();
cleanup_ok = false;
try
    addpath(ssh2_dir, '-begin');
    addpath(mock_dir, '-begin');
    assert(~isempty(strfind(which('ssh2'), mock_dir)), ...
        'The mocked transport must shadow ssh2 for this check.');

    ok_result = {'ok'};
    empty_result = {''};
    base = struct('command_result', {ok_result}, ...
        'command_exit_status', 0, 'command_success', true);
    % Legacy one-output and two-output callers keep working.
    s1 = ssh2_command(base, 'true');
    assert(isstruct(s1) && isequal(s1.command_result, ok_result));
    [s2, r2] = ssh2_command(base, 'true', 0);
    assert(isstruct(s2) && isequal(r2, ok_result));
    % New third output: numeric 0 is success.
    [s3, r3, st3] = ssh2_command(base, 'true', 0);
    assert(isstruct(s3) && isequal(r3, ok_result) && st3 == 0);
    % Non-zero numeric status survives even with empty stdout.
    quiet = base; quiet.command_result = empty_result;
    quiet.command_exit_status = 7; quiet.command_success = false;
    [~, rq, stq] = ssh2_command(quiet, 'true', 0);
    assert(stq == 7 && isequal(rq, empty_result));
    % Success-looking stdout must NOT mask a non-zero or unavailable status.
    lying = base;
    lying.command_result = {'true', 'SUCCESS', 'exit 0'};
    lying.command_exit_status = 7; lying.command_success = false;
    [~, ~, stl] = ssh2_command(lying, 'true', 0);
    assert(stl == 7, 'stdout must never override the numeric status.');
    lying2 = base;
    lying2.command_exit_status = []; lying2.command_success = false;
    [~, ~, stn] = ssh2_command(lying2, 'true', 0);
    assert(isempty(stn), ...
        'An unavailable status must surface as empty (explicit failure).');
    cleanup_ok = true;
catch ME
    warning('off', 'MATLAB:rmpath:DirNotFound');
    rmpath(mock_dir);
    delete(mock_file);
    path(restore);
    warning('on', 'MATLAB:rmpath:DirNotFound');
    clear ssh2 ssh2_command;
    rethrow(ME);
end
rmpath(mock_dir);
delete(mock_file);
clear ssh2;
end
