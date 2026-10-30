#!/usr/bin/env python3
"""Manual Python -> MATLAB R2010b headless pseudoCT validate/submit harness.

Requires Python 3 + numpy + scipy on the machine that runs pseudoct-headless.
Does not call MATLAB directly, use a MATLAB GUI, or store credentials in scratch.
Runs local validation without authentication, then optionally submits exactly
one mlsc-current job after explicit operator confirmation. Never retries a
submission.

The script checks the exact v2 request fields against the checked-out MATLAB
headless API. Running with --run can authenticate and submit a live scheduler
job; do not use it without separate authorization and safe input/output review.
"""

import argparse
import getpass
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import uuid
from datetime import datetime

print("[startup] Loading NumPy and SciPy...", flush=True)
import numpy as np
from scipy.io import loadmat, savemat
print("[startup] Python dependencies loaded.", flush=True)

EXPECTED_SHA256 = "a234eafa1399fc811792dd2545b0cd99409f3a8cddf1aba423f52074fb62f55b"
EXPECTED_FIELDS = {
    "schema", "invocation_id", "action", "profile", "subjects", "umap_files",
    "output_config", "options", "resolved_job", "group_account",
    "credential_handoff", "host_key_file", "current_artifact_root",
}
RESULT_FIELDS = (
    "schema", "invocation_id", "action", "profile", "status", "error_code",
    "error_message", "authentication_status", "submission_status", "backend",
    "group_account", "job_ids", "scientific_completion", "dispatch_status",
    "diagnostics",
)


def check_source_contract(root: Path) -> None:
    path = root / "src/api/pseudo_CT_headless.m"
    if not path.is_file():
        raise RuntimeError(f"Can't inspect current request validator: {path}")
    source = path.read_text(errors="replace")
    # Matches the explicit required-fields list in the v2 request validator.
    match = re.search(r"\brequired\s*=\s*\{(.*?)\}\s*;", source, flags=re.S)
    if not match:
        raise RuntimeError("Could not locate the strict required-fields declaration. Check the current validator manually; no submissions performed.")
    actual = set(re.findall(r"'([A-Za-z][A-Za-z0-9_]*)'", match.group(1)))
    if actual != EXPECTED_FIELDS:
        raise RuntimeError(
            "The uncommitted request contract differs from this script. No credentials or jobs created.\n"
            f"Unexpected fields: {sorted(actual - EXPECTED_FIELDS)}\n"
            f"Missing fields: {sorted(EXPECTED_FIELDS - actual)}\n"
            f"Validator: {path}"
        )
    print("PASS: request field names match the checked-out strict validator.", flush=True)


def precheck(root: Path, mprage: Path) -> Path:
    print(f"[check] Inspecting CLI in {root}", flush=True)
    launcher = root / "bin/pseudoct-headless"
    if not launcher.is_file() or not os.access(launcher, os.X_OK):
        raise RuntimeError(f"Headless CLI missing or not executable: {launcher}")
    payload = root / "compiled/current/payload_build/mlsc_current_payload"
    if not payload.is_file():
        raise RuntimeError(f"Current MLSC payload missing: {payload}")
    import hashlib
    print(f"[check] Reading and SHA-256 hashing payload: {payload} ({payload.stat().st_size:,} bytes)...", flush=True)
    h = hashlib.sha256()
    with payload.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    print(f"[check] Payload SHA-256: {h.hexdigest()}", flush=True)
    if h.hexdigest() != EXPECTED_SHA256:
        raise RuntimeError(f"Unexpected payload hash: {h.hexdigest()} (expected {EXPECTED_SHA256}); aborting")
    print(f"[check] Checking MPRAGE: {mprage}", flush=True)
    if not mprage.is_file():
        raise RuntimeError(f"MPRAGE input file not found: {mprage}")
    if mprage.name.lower().endswith(("_normalized.nii", "_moved.nii")):
        raise RuntimeError("Choose the original MPRAGE, not a _normalized.nii or _moved.nii intermediate")
    # Do not impose a NIfTI-only format restriction here. The existing
    # pseudoCT pipeline accepts original DICOM .dcm inputs and calls dcm2nii
    # itself, just as when launched through the MATLAB GUI or scripting API.
    print(f"[check] Source file accepted unchanged: {mprage.name}", flush=True)
    if mprage.suffix.lower() == ".dcm":
        print("[check] Original DICOM detected; conversion is handled by pseudoCT/dcm2nii.", flush=True)
    print("NOTE: mlsc-current also requires discoverable UMAP reference data for this MPRAGE.", flush=True)
    check_source_contract(root)
    return launcher


def private_credential_mat(username: str, password: str) -> Path:
    """Replicate MATLAB's private /dev/shm single-use credential.mat layout."""
    shm = Path("/dev/shm")
    if not shm.is_dir():
        raise RuntimeError("/dev/shm is unavailable")
    # Deliberately choose the naming pattern produced by pseudo_CT_credentials('store').
    directory = shm / ("pseudo_CT_credentials_" + secrets.token_hex(16))
    directory.mkdir(mode=0o700)
    path = directory / "credentials.mat"
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as f:
            savemat(f, {"credential": {"username": username, "password": password}},
                    format="5", do_compression=False, oned_as="row")
        os.chmod(path, 0o600)
        ds, fs = directory.stat(), path.stat()
        if (stat.S_IMODE(ds.st_mode) != 0o700 or stat.S_IMODE(fs.st_mode) != 0o600
                or ds.st_uid != os.getuid() or fs.st_uid != os.getuid()):
            raise RuntimeError("Credential ownership/permissions are unsafe")
        return path
    except BaseException:
        cleanup_credential(path)
        raise


def cleanup_credential(path: Path) -> None:
    """Best effort cleanup if the consumer didn't remove the single-use secret."""
    if not path:
        return
    try:
        if path.is_file() and not path.is_symlink():
            with path.open("r+b", buffering=0) as f:
                f.write(b"\x00" * path.stat().st_size)
            path.unlink()
        if path.parent.is_dir() and not path.parent.is_symlink():
            path.parent.rmdir()
    except OSError:
        print("WARNING: inspect and remove a leftover private credential handoff", file=sys.stderr)


def empty_numeric():
    return np.empty((0, 0), dtype=np.float64)


def make_request(action: str, invocation_id: str, *, mprage: Path,
                 resolved_job=None, account: str = "",
                 credential_handoff: str = "") -> dict:
    validating = action == "validate"
    subjects = (np.array([[str(mprage)]], dtype=object) if validating
                else np.empty((0, 0), dtype=object))
    return {
        "schema": "pseudoCT.headless-request/v2",
        "invocation_id": invocation_id,
        "action": action,
        "profile": "mlsc-current",
        "subjects": subjects,
        "umap_files": np.empty((0, 0), dtype=object),
        "output_config": ({"layout": "profile-default"} if validating else {}),
        "options": ({"correct_aliasing": empty_numeric(),
                     "recenter_before_normalization": empty_numeric()}
                    if validating else {}),
        "resolved_job": (empty_numeric() if validating else resolved_job),
        "group_account": account if not validating else "",
        "credential_handoff": credential_handoff if not validating else "",
        "host_key_file": "",
        "current_artifact_root": "",
    }


def mat_python(value):
    """Convert MAT structs, char arrays, cells, and scalars for status inspection."""
    if hasattr(value, "_fieldnames"):
        return {name: mat_python(getattr(value, name)) for name in value._fieldnames}
    if isinstance(value, np.ndarray):
        if value.size == 0:
            return []
        if value.ndim == 0:
            return mat_python(value.item())
        return [mat_python(x) for x in value.flat]
    if isinstance(value, np.generic):
        return value.item()
    return value


def invoke(root: Path, launcher: Path, run_dir: Path, request: dict):
    action = request["action"]
    request_path = run_dir / (action + "_request.mat")
    result_path = run_dir / (action + "_result.mat")
    log_path = run_dir / (action + "_cli.log")
    savemat(str(request_path), {"request": request}, format="5", do_compression=False,
            oned_as="row")
    request_path.chmod(0o600)
    print(f"\nExecuting {action} through bin/pseudoct-headless ...", flush=True)
    print(f"Request: {request_path}\nLog: {log_path}", flush=True)
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        proc = subprocess.Popen([str(launcher), str(request_path), str(result_path)],
                                cwd=str(root), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True,
                                errors="replace", bufsize=1)
        assert proc.stdout is not None
        for line in proc.stdout:
            print(line, end="", flush=True)
            log.write(line)
        code = proc.wait()
    log_path.chmod(0o600)
    print(f"CLI exit code: {code}", flush=True)
    if not result_path.is_file():
        raise RuntimeError("CLI did not write a result MAT. Inspect log AND scheduler before any retry.")
    loaded = loadmat(str(result_path), struct_as_record=False, squeeze_me=True)
    if "result" not in loaded:
        raise RuntimeError("Result MAT does not contain the 'result' struct")
    result = mat_python(loaded["result"])
    if not isinstance(result, dict):
        raise RuntimeError("Result MAT is not a struct")
    if result.get("schema") != "pseudoCT.headless-result/v2":
        raise RuntimeError("Incorrect result schema")
    if result.get("invocation_id") != request["invocation_id"]:
        raise RuntimeError("Result invocation ID mismatch; stop")
    if result.get("profile") != "mlsc-current" or result.get("action") != action:
        raise RuntimeError("Result profile/action mismatch; stop")
    print("\n--- Non-secret result summary ---")
    for field in RESULT_FIELDS:
        if field in result:
            print(f"{field}: {result[field]}")
    if code != 0:
        raise RuntimeError("CLI returned nonzero; inspect result and backend evidence; DO NOT retry")
    raw_loaded = loadmat(str(result_path), struct_as_record=True, squeeze_me=False)
    raw_result = raw_loaded["result"][0, 0]
    resolved_job = raw_result["resolved_job"]
    return result, resolved_job


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path, help="Uncommitted pseudoCT_standalone worktree")
    parser.add_argument("--mprage", required=True, type=Path, help="Original MPRAGE DICOM (.dcm) or supported NIfTI input from known-good dataset")
    parser.add_argument("--account", default="", help="Optional exact MLSC group account; blank uses the first discovered account")
    parser.add_argument("--run", action="store_true", help="Offer one scientific submission after local validation")
    args = parser.parse_args()
    print(f"[startup] ROOT argument: {args.root}", flush=True)
    print(f"[startup] MPRAGE argument: {args.mprage}", flush=True)
    print("[check] Resolving input paths...", flush=True)
    root = args.root.expanduser().resolve()
    mprage = args.mprage.expanduser().resolve()
    print("[check] Paths resolved; beginning checks...", flush=True)
    launcher = precheck(root, mprage)
    run_dir = root / "scratch" / datetime.now().strftime("%Y-%m-%d") / (datetime.now().strftime("%H%M%S") + "-manual-python-headless")
    run_dir.mkdir(mode=0o700, parents=True, exist_ok=False)
    run_dir.chmod(0o700)
    print(f"Evidence directory: {run_dir}", flush=True)
    print("NOTE: pseudoCT scientific output destinations are profile/input-dependent, NOT this scratch folder.")
    invocation_id = str(uuid.uuid4())
    validate_request = make_request("validate", invocation_id, mprage=mprage)
    validation, resolved_job = invoke(root, launcher, run_dir, validate_request)
    if (validation.get("status") != "ready"
            or validation.get("authentication_status") != "not_attempted"
            or validation.get("submission_status") != "not_attempted"):
        raise RuntimeError("Local validation did not report ready/no-auth/no-submit")
    if not args.run:
        print("Validation complete; --run was not passed, so no authentication or submission occurred.")
        return 0
    if not isinstance(validation.get("resolved_job"), dict) or not validation["resolved_job"]:
        raise RuntimeError("Validation did not return a resolved job; no submission is permitted")
    if not isinstance(resolved_job, np.ndarray) or resolved_job.size != 1:
        raise RuntimeError("Could not preserve the MATLAB resolved-job struct; no submission is permitted")

    account = args.account
    if not account:
        account = input("Optional exact MLSC group account (blank uses first discovered account): ").strip()
    print("\nProposed LIVE submission:")
    print("Profile: mlsc-current")
    print("MPRAGE:", mprage)
    print("MLSC group account:", account if account else "first discovered account")
    print("Aliasing/recentering: profile defaults")
    print("WARNING: mlsc-current requires a valid UMAP; this validation resolved it locally.")
    print("WARNING: inspect pseudoCT output destinations for potential overwrite before continuing.")
    if input("Type SUBMIT to authenticate and launch ONE Slurm scientific job: ").strip() != "SUBMIT":
        print("Cancelled without authentication or scientific submission.")
        return 0

    username = input("MLSC SSH username: ").strip()
    if not username:
        raise RuntimeError("Empty username")
    password = getpass.getpass("MLSC SSH password (not echoed): ")
    if not password:
        raise RuntimeError("Empty password")
    cred_path = None
    try:
        cred_path = private_credential_mat(username, password)
    finally:
        password = ""
    try:
        submit_request = make_request("submit", invocation_id, mprage=mprage,
                                      resolved_job=resolved_job, account=account,
                                      credential_handoff=str(cred_path))
        submitted, _ = invoke(root, launcher, run_dir, submit_request)
        print("\nSubmit call returned. Evaluate acknowledged job ID, lifecycle, scientific outcome, QC and reference comparisons before acceptance.")
        return 0 if submitted.get("status") == "submitted" else 1
    finally:
        cleanup_credential(cred_path)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, EOFError):
        print("\nInterrupted. Check the scheduler before considering a retry.", file=sys.stderr)
        sys.exit(130)
    except Exception as exc:
        print(f"\nSTOP: {exc}", file=sys.stderr)
        sys.exit(1)
