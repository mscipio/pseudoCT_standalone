# Exploration: Launchpad Denoised MPRAGE Investigation

**Change name (user-provided):** "Investigate Launchpad support for denoised NIfTI MPRAGE inputs"
**Slug:** `launchpad-denoised-mprage-investigation`
**Engram topic_key:** `sdd/launchpad-denoised-mprage-investigation/explore`
**Project:** `pseudoct_standalone`
**Date:** 2026-07-14
**Status:** Explore — diagnosis only, no source modifications proposed

---

## Current State

The Launchpad entry point (`run_pseudo_CT_launchpad.m`) and the local entry point
(`run_pseudo_CT_local.m`) share a common pre/post-processing shape but differ in
**where the intermediate `att_map.nii` is staged on local disk**. The local path
follows the actual location of the file (the `Pf(end, :)` returned by
`atlas_based_attenuation_map.m`); the launchpad path hardcodes the lookup to
`MR_PET/tmp/att_map.nii`. That asymmetry is the seed of the NIfTI bug.

### Input staging — what `convert_dicom_i_2_nii` does today

`src/io/convert_dicom_i_2_nii.m` is the only DICOM→NIfTI stage. For the
`.nii` extension it does **not** copy/move the file into `dir_final`
(temp_dir) — it returns the original input path unchanged
(`src/io/convert_dicom_i_2_nii.m:132-135`):

```matlab
if length(strfind(extd, '.nii'))
    aux = P(ii, :);
    Pnew(ii, 1:length(aux)) = aux;
end
```

For the DICOM/IMA branches (lines 80–95, 118–127) the function DOES move
the converted NIfTI to `dir_final` (which is `MR_PET/tmp/`) via
`movefile(aux, aux2)`. That is the single piece of logic that makes the
launchpad path's downstream `temp_dir`-based lookup work for DICOM and
silently fail for NIfTI.

### Launchpad path — how it consumes `seed_nii`

`run_pseudo_CT_launchpad.m:103` calls
`jobs(ii).seed_nii = convert_dicom_i_2_nii(jobs(ii).mprage_fn, 'mprage.nii', temp_dir)`
and stores the returned path. `P` (a char matrix) is then handed to
`batch_pseudo_CT_launchpad` (`run_pseudo_CT_launchpad.m:122`).

`src/launchpad/batch_pseudo_CT_launchpad.m` operates on `P(jj, :)`:

- `pathn = fileparts(P(jj, :))` — the directory of the input file
- `scp_put` uploads `fn.extn` to the cluster's `lc_path`
  (`batch_pseudo_CT_launchpad.m:70`)
- `mri_normalize` runs in the **remote** `lc_path` and creates
  `<fn>_normalized.nii` (line 74–77)
- The compiled `Pseudo_CT_launchpad` (v2.0 binary at
  `/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/`)
  runs in the same remote `lc_path` and writes its `att_map.nii` there
- `scp_get` brings the entire `lc_path` contents back to `pathn`
  (`batch_pseudo_CT_launchpad.m:124`)

`pathn` is **the directory of the input file** — not `MR_PET/tmp/`.

| Input              | `pathn`                            | `temp_dir` (looked up)        |
|--------------------|------------------------------------|-------------------------------|
| DICOM `file1.IMA`  | `<root>/MR/MEMPRAGE/`              | `<root>/MR_PET/tmp/`          |
| NIfTI in `MR/`     | `<root>/MR/`                       | `<root>/MR_PET/tmp/`          |
| NIfTI in `MR/MEMPRAGE/` | `<root>/MR/MEMPRAGE/`         | `<root>/MR_PET/tmp/`          |

For DICOM, `convert_dicom_i_2_nii` happens to place the converted NIfTI
(`mprage.nii`) inside `MR_PET/tmp/`, so `P(jj, :)` lives at
`MR_PET/tmp/mprage.nii` and `pathn` happens to equal `MR_PET/tmp/`. The
launchpad path was therefore implicitly coupled to the DICOM staging step.

For NIfTI, `convert_dicom_i_2_nii` returns the input NIfTI path unchanged.
`pathn` is whatever the input NIfTI's parent directory is — and the
`scp_get` round-trip writes `att_map.nii` to that same directory.

### Post-launchpad finalize — where the file is *looked for*

`run_pseudo_CT_launchpad.m:142`:

```matlab
pseudo_CT_write_mu_map_dicom(fullfile(jobs(jj).temp_dir, 'att_map.nii'),
                             jobs(jj).save_dir, jobs(jj).umap_fn,
                             jobs(jj).temp_dir, 0);
```

`jobs(jj).temp_dir` is always `MR_PET/tmp/`. The hardcoded path is the
only place the launchpad finalize stage looks for `att_map.nii`.

`src/io/pseudo_CT_write_mu_map_dicom.m:8-9` is the emitter of the
"Pseudo-CT processing finished without creating:" error:

```matlab
if exist(att_map_file, 'file') ~= 2
    error('pseudo_CT_write_mu_map_dicom:MissingAttenuationMap', ...
          'Pseudo-CT processing finished without creating:\n%s', att_map_file);
end
```

So the error message is a literal "I asked MATLAB to find
`<temp_dir>/att_map.nii` and the file isn't there" — not a launchpad
job failure. The job's exit status (`ss_tot(jj) == 0`) is satisfied; the
PBS queue is happy; the compiled binary is happy; the `scp_get` even
succeeded. The att_map.nii just lives in the wrong local folder.

`pseudo_CT_promote_final_outputs`
(`src/io/pseudo_CT_promote_final_outputs.m:18-58`) compounds the problem
by looking for the same `temp_dir`-relative files
(`temp_dir/mprage.nii`, `temp_dir/<seed>_normalized.nii`,
`temp_dir/att_map.nii`) and failing the required-file check on
`att_map.nii` for the NIfTI case.

### Local path — why it does not have this bug

`run_pseudo_CT_local.m:207-225`:

```matlab
P = convert_dicom_i_2_nii(job.mprage_fn, 'mprage.nii', temp_dir);
[Pf] = atlas_based_attenuation_map(P, dir_batch_templates, ssh_log, job.correct_aliasing, defaults);
...
[temp_working_dir, ~, ~] = fileparts(deblank(Pf(end, :)));
pseudo_CT_write_mu_map_dicom(fullfile(temp_working_dir, 'att_map.nii'), save_dir, job.umap_fn, temp_dir, FWHM);
```

`temp_working_dir` is the directory of the actually-produced att_map.nii
(whatever directory the compiled-or-local `atlas_based_attenuation_map`
wrote to), not a hardcoded `MR_PET/tmp/`. So the local pipeline works
for NIfTI inputs in `MR/` (att_map lands in `MR/att_map.nii`) and for
DICOM inputs (att_map lands in `MR_PET/tmp/att_map.nii` because
`convert_dicom_i_2_nii` placed the seed there).

### UMAP auto-discovery (sanity check)

`src/ui/pseudo_CT_auto_discover_ute_umap.m` and
`src/ui/pseudo_CT_discover_ute_umap.m` only inspect the MR/ parent
folder (line 18 of the latter: `ss = strfind(patha, strcat(filesep, 'MR', filesep))`).
For a denoised NIfTI at `…/MR/MEMPRAGE_BC_denoised.nii` the function
walks up to `…/MR/`, lists sibling directories, and looks for any
matching `umap|ute|mu_map|mumap` folder containing a `*0001*` file. This
is independent of the input extension and behaves the same way for DICOM
and NIfTI. UMAP discovery is **not** the failure mechanism here.

### Compiled binary behavior (v2.0 launchpad)

`/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/Pseudo_CT_launchpad`
is an ELF MCR 7.11 binary, no source available. Its shell wrapper
`run_Pseudo_CT_launchpad.sh` is a vanilla MCR launcher (no
input-path manipulation). The compiled binary inherits the v2.0
`atlas_based_attenuation_map.m` behavior: it writes its outputs
(`mprage*_normalized.nii`, `mmprage*.nii`, `rc*…`, `att_map.nii`, etc.)
in the **current working directory of the process**, which the
launchpad shim sets to the remote `lc_path`. That is why
`scp_get(comm_result.', pathn)` reliably brings back an `att_map.nii`
next to `<fn>_normalized.nii` on the remote — and why the att_map.nii
lands wherever the input NIfTI lived locally after the round trip.

---

## Key Findings

1. **`convert_dicom_i_2_nii` is asymmetric by extension** —
   `src/io/convert_dicom_i_2_nii.m:132-135` returns the input path
   unchanged for `.nii` inputs and never stages the file into
   `dir_final`. DICOM/IMA branches (lines 80–95, 118–127) actively
   `movefile` the converted NIfTI into `dir_final`. This is the
   single decision that breaks the launchpad path for NIfTI.

2. **The launchpad path's `att_map.nii` lookup is hardcoded to
   `temp_dir`** — `run_pseudo_CT_launchpad.m:142` passes
   `fullfile(jobs(jj).temp_dir, 'att_map.nii')` to
   `pseudo_CT_write_mu_map_dicom`. The local equivalent
   (`run_pseudo_CT_local.m:223-225`) uses the actual returned path
   `Pf(end, :)` instead. The launchpad path's `scp_get` brings
   `att_map.nii` back to `pathn` = the input file's parent
   directory (`batch_pseudo_CT_launchpad.m:89, 124`), which is
   different from `temp_dir` whenever the input is a NIfTI.

3. **The user-visible "finished without creating" error is emitted
   purely client-side** — `src/io/pseudo_CT_write_mu_map_dicom.m:8-9`
   checks `exist(att_map_file, 'file')` and errors with the
   `Pseudo-CT processing finished without creating:\n<path>` message.
   The PBS job's exit code (`ss_tot(jj)`) is `0`; the launchpad
   backend is reporting success. The att_map.nii really is on local
   disk — just in the wrong folder (the input NIfTI's parent, e.g.
   `MR/`).

4. **`pseudo_CT_promote_final_outputs` compounds the failure for
   cleanup/normalization artifacts** —
   `src/io/pseudo_CT_promote_final_outputs.m:24, 29, 78, 92-101`
   look for `temp_dir/<seed_basename>.nii` and
   `temp_dir/<seed_basename>_normalized.nii` (or
   `…_moved_normalized.nii`) in `temp_dir` (i.e. `MR_PET/tmp/`).
   For NIfTI inputs, both the seed and the FreeSurfer-normalized
   output live in the input NIfTI's parent directory, not in
   `MR_PET/tmp/`. Promotion's required-file check on `att_map.nii`
   also fails. Net result: even the side effects of promotion
   (the `MR_PET/att_map.nii` copy and the `MPRAGE_spm*.nii`
   promotion) never happen for NIfTI inputs.

5. **The compiled v2.0 Launchpad binary and the legacy `piano_mMR`
   pipeline were both implicitly coupled to the same
   "DICOM-stage-to-MR_PET/tmp" assumption** — this is consistent
   with the code version being baked into the binary as `2.0` in
   `atlas_based_attenuation_map.m:90`'s fallback string and the
   "Standalone copy of the piano_mMR Launchpad submission helper"
   comments in `src/launchpad/check_launchpad_command_status.m:2`
   and `src/launchpad/run_launchpad_cmd_return.m:2`. The NIfTI
   support in `piano_mMR` / Tom's version was almost certainly
   a per-input copy step into `MR_PET/tmp/mprage.nii` before
   submission — that copy is missing from the standalone extraction.

6. **DICOM launchpad path works coincidentally** — the
   `convert_dicom_i_2_nii` move-to-`dir_final` step places the
   seed NIfTI in `MR_PET/tmp/`, so `P(jj, :)`'s parent is
   `MR_PET/tmp/`, so `pathn == temp_dir`, so the
   `scp_get(...,'.',pathn)` round-trip and the
   `temp_dir/att_map.nii` lookup both end up targeting the same
   folder. The DICOM pipeline "works" because of a hidden
   invariant, not because the launchpad path is robust.

7. **NIfTI inputs where the file lives one level deeper (e.g.
   `MR/MEMPRAGE/MEMPRAGE_BC_denoised.nii`) make the failure
   louder** — `pathn` becomes `MR/MEMPRAGE/` and the att_map.nii
   lands in the user's series folder, sometimes alongside their
   raw DICOM `*.IMA` files. `pseudo_CT_cleanup_intermediates`
   (`src/io/pseudo_CT_cleanup_intermediates.m:5`) is NOT called
   on the launchpad path's `temp_dir` (it is called on
   `pathn` at `batch_pseudo_CT_launchpad.m:168`, with a hard
   `clean_folder=0` from the entry script at
   `run_pseudo_CT_launchpad.m:122` — so even the
   pseudo-cleanup step is dormant).

8. **`pseudo_CT_promote_final_outputs` and
   `pseudo_CT_cleanup_intermediates` are wired to the same
   `pathn` vs `temp_dir` confusion as the
   `pseudo_CT_write_mu_map_dicom` call** — i.e. the bug is
   structural in the launchpad path's resolve-target logic, not
   a one-line typo in a single call.

---

## Affected Areas

- `run_pseudo_CT_launchpad.m:82-86` — derives `processing_dir` /
  `temp_dir` / `save_dir` from the input file's `pathr`, but stores
  them on the job struct instead of using them as `scp_get`
  destination.
- `run_pseudo_CT_launchpad.m:103` — calls
  `convert_dicom_i_2_nii(..., temp_dir)` but does not enforce that
  the returned `seed_nii` actually lives under `temp_dir` (it can
  be the original NIfTI path).
- `run_pseudo_CT_launchpad.m:122` — calls
  `batch_pseudo_CT_launchpad(P, ...)` with `P(jj, :)` = the
  un-staged NIfTI path.
- `run_pseudo_CT_launchpad.m:142` — hardcodes
  `fullfile(jobs(jj).temp_dir, 'att_map.nii')` for the
  post-launchpad finalize.
- `run_pseudo_CT_launchpad.m:164` — calls
  `pseudo_CT_promote_final_outputs(jobs(jj).temp_dir, ...)` with
  the same hardcoded `temp_dir`.
- `src/launchpad/batch_pseudo_CT_launchpad.m:65-83` — uploads and
  compiles the launchpad command for the input file at
  `pathn = fileparts(P(jj, :))`.
- `src/launchpad/batch_pseudo_CT_launchpad.m:88-124` — `scp_get`
  brings outputs back to `pathn`, not `temp_dir`.
- `src/launchpad/batch_pseudo_CT_launchpad.m:160-170` —
  `pseudo_CT_cleanup_intermediates(pathn)` is gated on
  `clean_folder` which is hardcoded to `0` by the entry script.
- `src/io/convert_dicom_i_2_nii.m:132-135` — the `.nii` branch
  skips the `dir_final` copy step that all other branches
  perform.
- `src/io/pseudo_CT_promote_final_outputs.m:18-32, 78, 92-101` —
  hardcodes `temp_dir` lookups for `att_map.nii`,
  `mprage.nii`, `*_normalized.nii`, `*_moved_normalized.nii`.
- `src/io/pseudo_CT_write_mu_map_dicom.m:8-9` — emits the
  user-visible "finished without creating" error when the
  hardcoded `att_map_file` is not present.
- `src/core/atlas_based_attenuation_map.m:646-654` — writes the
  `att_map.nii` next to the input image (so the launchpad path's
  assumption that it will be in `MR_PET/tmp/` is also true only
  for DICOM inputs after `convert_dicom_i_2_nii` staging).
- `src/ui/pseudo_CT_discover_ute_umap.m:18-77` — UMAP
  auto-discovery. Not the failure mechanism for the user's
  reported bug, but the search root (`MR/`) is the same that
  ends up as the `scp_get` destination for NIfTI inputs, so a
  UMAP file with the same basename as the NIfTI could be
  collided with during the round trip. Worth flagging as a
  side-effect risk, not a root cause.

---

## Failure Mechanism

End-to-end trace for a NIfTI MPRAGE input
`/path/to/subj/MR/MEMPRAGE_BC_denoised.nii` (denoised or otherwise) run
through `run_pseudo_CT_launchpad(...)`:

1. `launchpad_collect_jobs` builds
   `jobs(1).mprage_fn = '/path/to/subj/MR/MEMPRAGE_BC_denoised.nii'`
   (`run_pseudo_CT_launchpad.m:235-258`).
2. `pathr = '/path/to/subj/MR/'`.
   `pseudo_CT_resolve_output_dirs(pathr)` walks up from
   `/path/to/subj/MR/`, finds the `MR` directory at the input
   level, and resolves:
   - `processing_dir = '/path/to/subj/MR_PET'`
   - `temp_dir       = '/path/to/subj/MR_PET/tmp'`
   - `save_dir       = '/path/to/subj/MR/pseudo_muMAP'`
   (`src/io/pseudo_CT_resolve_output_dirs.m:5-29`).
3. The three directories are created if absent
   (`run_pseudo_CT_launchpad.m:88-98`).
4. `jobs(ii).seed_nii = convert_dicom_i_2_nii(...)` is called
   with `dir_final = temp_dir`. The `.nii` branch
   (`src/io/convert_dicom_i_2_nii.m:132-135`) **does not stage
   the file**: it returns the original input path. The
   `temp_dir/mprage.nii` that the launchpad path implicitly
   assumes does not exist.
5. `P(jj, :) = '/path/to/subj/MR/MEMPRAGE_BC_denoised.nii'` is
   built and passed to `batch_pseudo_CT_launchpad`.
6. Inside `batch_pseudo_CT_launchpad.m:65-83`:
   - `pathn = '/path/to/subj/MR/'`
   - `fn, extn = 'MEMPRAGE_BC_denoised', '.nii'`
   - `scp_put` uploads `MEMPRAGE_BC_denoised.nii` to the
     cluster `lc_path`.
   - `mri_normalize` runs in the remote `lc_path`, producing
     `MEMPRAGE_BC_denoised_normalized.nii` in that folder.
   - The compiled `Pseudo_CT_launchpad` runs in the same
     `lc_path`, writing
     `MEMPRAGE_BC_denoised_moved.nii`, `rc*`, `u_rc1*`, and
     `att_map.nii` next to the normalized seed.
7. `batch_pseudo_CT_launchpad.m:88-124`:
   - `pathn = '/path/to/subj/MR/'` (re-derived from `P(jj, :)`).
   - `scp_get(ssh2_conn, comm_result.', pathn)` brings every
     remote artifact, including `att_map.nii`, back into
     **`/path/to/subj/MR/`**, not `MR_PET/tmp/`.
   - The local check at line 129
     (`exist(fullfile(pathn, 'att_map.nii'), 'file') ~= 2`)
     passes — the file IS there at `/path/to/subj/MR/att_map.nii`.
     No `[launchpad-debug] att_map.nii missing` message is
     printed.
8. Control returns to `run_pseudo_CT_launchpad.m:142`:
   ```matlab
   pseudo_CT_write_mu_map_dicom(
       fullfile(jobs(jj).temp_dir, 'att_map.nii'),
       jobs(jj).save_dir, jobs(jj).umap_fn,
       jobs(jj).temp_dir, 0);
   ```
   The first argument is
   `'/path/to/subj/MR_PET/tmp/att_map.nii'`. That file does not
   exist. The att_map.nii is sitting in
   `/path/to/subj/MR/att_map.nii`.
9. `src/io/pseudo_CT_write_mu_map_dicom.m:8-9` raises
   `pseudo_CT_write_mu_map_dicom:MissingAttenuationMap` with the
   message
   `"Pseudo-CT processing finished without creating:\n/path/to/subj/MR_PET/tmp/att_map.nii"`.
10. The launchpad entry script's catch block
    (`run_pseudo_CT_launchpad.m:143-162`) prints a
    `[launchpad-debug]` diagnostic listing the contents of
    `jobs(jj).temp_dir` (`MR_PET/tmp/`), which is **empty or
    near-empty** because nothing was ever written there. The
    debug printout reinforces the user's impression that the
    pipeline "stalled" — the empty `temp_dir` makes it look
    like no work happened, when in fact the work happened
    and the result is one folder up.
11. `pseudo_CT_promote_final_outputs` is then never called for
    this subject (the catch block's `continue` skips it at
    `run_pseudo_CT_launchpad.m:161`). The
    `processing_dir/MR_PET/att_map.nii`, `…/MPRAGE_spm.nii`,
    `…/MPRAGE_spm_normalized.nii`, and
    `…/Pseudo_CT_AC_Version.txt` copies all fail silently.
12. The DICOM pseudo-muMAP is not produced because
    `mMR_nii2mu_dicom_blur_david` was never invoked. The
    `MR/pseudo_muMAP/` folder exists but stays empty.

This explains every observed symptom:

- `pseudo_muMAP/` is created but empty — DICOM write was never
  reached.
- `att_map.nii` is not in `MR_PET/tmp/` — it was never placed
  there.
- The user sees the `att_map.nii` "look pretty good" — it is
  actually present, just in the input NIfTI's parent directory
  (`MR/att_map.nii`).
- The launchpad log ends with the "finished without creating"
  error — emitted by `pseudo_CT_write_mu_map_dicom.m:9`.
- `piano_mMR` and Tom's version work — both almost certainly
  copy/rename the NIfTI into `MR_PET/tmp/mprage.nii` before
  submission so the launchpad path's hardcoded `temp_dir`
  lookup remains valid. That copy step is missing from the
  standalone extraction.

---

## Risks

- **Hardcoded lookup, multiple call sites** — the bug is
  structural: the same `temp_dir` assumption is shared by
  `pseudo_CT_write_mu_map_dicom`,
  `pseudo_CT_promote_final_outputs`, and the launchpad entry
  script. A single point fix (e.g. only adjusting the entry
  script) is not enough; the downstream callers also need to
  know where the att_map.nii actually lives.

- **Silent partial success** — the launchpad job reports
  exit 0, the `att_map.nii` is on disk, the `[launchpad-debug]
  att_map.nii missing` warning at
  `batch_pseudo_CT_launchpad.m:130` does **not** fire (because
  `pathn` is where the file actually is). Users see a confusing
  "no att_map" error with no hint of the real location.

- **Cleanup behavior masks the artifact** — for a NIfTI in
  `MR/`, the att_map.nii lands in `MR/` next to (or among) the
  user's raw series files. The launchpad entry script's
  `pseudo_CT_cleanup_intermediates` call uses `pathn`
  (`batch_pseudo_CT_launchpad.m:168`) but is gated on
  `clean_folder=0` (set at
  `run_pseudo_CT_launchpad.m:122`), so cleanup is dormant by
  default. The att_map.nii survives in `MR/` indefinitely for
  failed subjects.

- **NIfTI collision risk with UMAP/UTE files** — for a NIfTI
  whose basename collides with a `*0001.IMA` UMAP/UTE slice
  (e.g. `MEMPRAGE_BC_denoised_0001.IMA` next to it), the
  `scp_get ... '.' pathn` round trip could clobber existing
  files. Worth checking on real data, not just theoretical.

- **DICOM-on-launchpad only works by accident** — the
  current DICOM path is a fragile coincidence of
  `convert_dicom_i_2_nii`'s move-to-`dir_final` step
  (`src/io/convert_dicom_i_2_nii.m:92-95`) lining up with
  `batch_pseudo_CT_launchpad`'s `pathn` derivation. Any future
  change to the staging step (e.g. skipping the move for
  already-existing files) would silently break the DICOM
  launchpad path too.

- **`batch_pseudo_CT_launchpad.m` already has
  `keep_tmp` support** (lines 7, 27-28, 147-155) but the
  current entry script does NOT pass it (`'keep_tmp'`,
  `keep_tmp_val` removed at
  `run_pseudo_CT_launchpad.m:117-122` versus the prior
  `dist/pseudoCT_v2.6.1` reference implementation in the diff).
  If the operator sets `PSEUDOCT_KEEP_TMP=1` it is silently
  ignored for the launchpad path. Not a cause of the NIfTI
  bug, but worth re-enabling to make the path easier to
  debug when this kind of issue recurs.

- **Compiled v2.0 binary is opaque** — no source access to
  the cluster binary means we cannot verify its
  file-location behavior except by inference from the
  round-trip evidence. Any fix that depends on the binary
  behaving differently (e.g. writing `att_map.nii` to a
  specific path) is not feasible.

---

## Ready for Proposal

**Yes** — the failure mechanism is fully traced, the affected
call sites are identified, and the root cause is a single
class of mistake (the `.nii` branch of `convert_dicom_i_2_nii`
not staging into `dir_final`, plus the launchpad path's
hardcoded `temp_dir` lookups).

A future proposal should:

1. Decide **where** the att_map.nii should live for NIfTI
   inputs: in `MR_PET/tmp/` (matching the DICOM path) or in
   the input NIfTI's parent directory (matching the local
   pipeline's `Pf(end, :)` behavior).
2. Either stage the NIfTI into `temp_dir` during the
   `.nii` branch of `convert_dicom_i_2_nii` (preserves the
   launchpad path's existing assumptions) **or** make
   `pseudo_CT_write_mu_map_dicom` /
   `pseudo_CT_promote_final_outputs` discover the actual
   att_map.nii location from the launchpad round-trip
   evidence (mirrors the local pipeline's
   `Pf(end, :)` approach).
3. Add a regression test (TDD-style, modeled on
   `scripts/test_auto_discover_messages.m`) that simulates
   a NIfTI launchpad round-trip and asserts that
   `pseudo_CT_write_mu_map_dicom` finds the att_map.nii
   in the right place.
4. Re-enable `keep_tmp` passthrough in the launchpad entry
   script so the operator can preserve `MR_PET/tmp/` for
   forensic analysis on failure.
