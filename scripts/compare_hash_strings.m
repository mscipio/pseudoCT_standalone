function [status_str, detail_str] = compare_hash_strings(h1, h2)
% Investigation tool — investigation-cleanup-release.
%COMPARE_HASH_STRINGS Judge equivalence of two pre-computed hash strings.
%   [STATUS, DETAIL] = COMPARE_HASH_STRINGS(H1, H2) compares two hash
%   strings H1 and H2, returning 'IDENTICAL' or 'DIVERGENT' in STATUS
%   and a human-readable reason in DETAIL.
%
%   Sentinel values 'READ_ERROR' and 'MD5_UNAVAILABLE' indicate a failed
%   hash computation.  Two identical sentinel values are NEVER reported
%   as IDENTICAL — both sides failed and we cannot judge equivalence.
%   This is the safety-critical guard against silent false-IDENITICAL
%   reports when the underlying hash machinery is unavailable.
%
%   This function is CALLABLE FROM OUTSIDE diff_entrypoint_runs.m —
%   it has no file-I/O, Java, or toolbox dependencies.  This makes the
%   sentinel guard directly testable in smoke / unit tests.
%
%   Minimum supported MATLAB: R2010b.

% ---- Sentinel check ----
sentinel_values = {'READ_ERROR', 'MD5_UNAVAILABLE'};
h1_fail = any(strcmp(h1, sentinel_values));
h2_fail = any(strcmp(h2, sentinel_values));

if h1_fail || h2_fail
    status_str = 'DIVERGENT';
    if h1_fail && h2_fail
        detail_str = sprintf( ...
            'MD5 failure on both sides: local=%s, launchpad=%s', ...
            h1, h2);
    elseif h1_fail
        detail_str = sprintf( ...
            'MD5 failure on local (%s), launchpad MD5=%s', ...
            h1, h2);
    else
        detail_str = sprintf( ...
            'MD5 failure on launchpad (%s), local MD5=%s', ...
            h2, h1);
    end
    return;
end

% ---- Normal comparison ----
if strcmp(h1, h2)
    status_str = 'IDENTICAL';
    detail_str = sprintf('MD5 match: %s', h1);
else
    status_str = 'DIVERGENT';
    detail_str = sprintf('MD5 mismatch: %s vs %s', h1, h2);
end
return
