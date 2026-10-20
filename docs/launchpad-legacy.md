# Launchpad Legacy Profile — Availability Restoration

> Scope: this document records the restoration of the `launchpad-legacy`
> selectable profile. It is an **availability restoration only**. It makes
> **no root-cause claim** about why the Launchpad path was unavailable, and
> **no correctness claim** about Launchpad outputs beyond the dataset-specific
> states cited below. There is **no universal parity claim** here.

## What changed

- New top-level profile `src/config/profiles/launchpad_legacy.m` with
  filename-derived identity `launchpad-legacy` (Recommended group, order 80,
  recenter Yes, zero-background No, cleanup default `true`).
- Lifecycle evidence (`launchpad_evidence`) and the batch path carry the
  selected profile identity instead of a hardcoded `launchpad` string.
  Submission, polling, retrieval, failure, and cleanup behavior is unchanged.

## Authority: Oct-19 over Aether

- **Operational authority is the Oct-19 run** (PBS job 19743718, final
  `58a874d1b311…`, elapsed 02:08:30, remote scratch
  `/cluster/scratch/monday/mu512/9057920`). On any conflict between the
  Oct-19 record and older lineage narrative, Oct-19 governs.
- **Aether is historical reference only.** The "legacy v2.0 (Aether)" label in
  profile presentation text names the compiled-backend lineage; it is not
  evidence about the state of any machine, queue, or binary today.

## Three states are dataset-specific

Observed final `att_map.nii` states on the compared datasets (single-subject
comparisons; dataset-only, no correctness ranking):

| State (SHA-256 prefix) | Observed on |
|---|---|
| `43508f6f…` | CURRENT interpreted post-bone path (retained `rc` proxy set) |
| `1517efbe…` | Accepted local compiled LEGACY and MLSC compiled LEGACY |
| `58a874d1…` | Live Launchpad Oct-19 run + v260/v264 archive pair (all 40 NIfTI stages identical across the three) |

- `58a874d1` vs `1517efbe` differ in 676,298 voxels (4.03%, maxAbs ≈ 0.044)
  on the compared subject. That percentage describes one dataset pair, not a
  general error bound.
- No state above is declared "correct". Operators must still inspect the QC
  TIFF and perform the normal manual output checks.

## Archived B-level context

Prior attribution discussion (environment-vs-hardware narrowing, queue
divergence, New Segment boundary analysis) is **archived B-level context**,
not live authority. It is preserved read-only under
`scratch/experiments/launchpad_archive_comparison/` (matrix, differences,
interpretation, live report, archaeology notes) and
`scratch/experiments/thread_single/` (provenance). Do not re-litigate causal
claims from those notes; they bound what was observed, with stated gaps
(no compute-node identity, no wire capture, no staged-vs-source manifest).

## Human live-infrastructure checklist (explicitly UNVERIFIED)

No automated step submits jobs. Before any human-operated live test, a human
must confirm each item below on current infrastructure — none is inferred
from the Oct-19 record:

- [ ] `pbsubmit` exists on the submission path with the expected flags.
- [ ] `/pbs/<user>/<job>.status` status files are produced and readable.
- [ ] `jobinfo <num>` resolves the submitted job number.
- [ ] Host `172.27.25.134` is reachable over SSH with valid credentials.
- [ ] Remote trees exist and are the intended bytes (NOT assumed from equal
      path strings): runner `…/Pseudo_CT_launchpad/run_Pseudo_CT_launchpad.sh`,
      MCR root `/usr/pubsw/common/matlab/7.11/`, defaults MAT
      `…/default_pseudo_CT_package_deployed.mat`, batch templates
      `…/Pseudo_CT_launchpad/Batch_atlas`, scratch `/cluster/scratch/monday/`.
- [ ] FreeSurfer env `source /usr/local/freesurfer/nmr-stable53-env` valid.
- [ ] Explicit human authorization recorded; no production submission without it.

## References

- Oct-19 run record: `tests-datasets/pseudoCT/launchpad-20261019/` (logs,
  profile summary, retained `tmp/`, remote `9057920`).
- Static verification: `scratch/launchpad_legacy/T003_STATIC_VERIFICATION.txt`.
- Historical pipeline detail: `docs/pipeline-launchpad.md` (deprecated-path
  reference), `docs/legacy-launchpad-parity.md`, `docs/parity-assessment.md`.
