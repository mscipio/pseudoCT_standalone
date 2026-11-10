PseudoCT help page (pseudoCT 3.2.0, unpublished prerelease source)
====================================================================

This folder is a dependency-free static website. It documents the repository
source; it is not a release, deployment or certification statement.

Deployment layout
-----------------
Deploy:
  - index.html
  - style.css

The deployable help bundle is index.html and style.css only. It matches HELP_FILES in
scripts/release_application.py. assets/ is never deployed.

No server-side code, JavaScript, build step, or external CSS framework is required.

index.html links only to:
  - anchors inside index.html, and
  - repository documents on GitHub, in the form
    https://github.com/mscipio/pseudoCT_standalone/blob/main/<path>

The Markdown documents (docs/*.md, README.md, CHANGELOG.md) are NOT deployed beside
this page. Relative links to them would not resolve, so the page does not use any.
The GitHub links resolve only once the referenced revision is on the main branch.
They were not fetched when this page was checked; see the checks in the audit
report.

Screenshots (assets/)
---------------------
assets/ holds 15 PNG files. None of them is referenced by index.html, and the
assets/ folder is not needed for the page. Do not copy assets/ to the deployment.
If it is copied anyway, exclude every file listed below.

All 15 are excluded pending review: the 11 obsolete or privacy-risk screenshots and the
4 held images below.

This list is a deployer instruction only. It does NOT delete anything. Removing
files from the repository or from the assets/ bundle requires explicit user
approval.

Excluded: obsolete or privacy-risk
  - successful-processing-log-deidentified.png   PRIVACY RISK. Visible text includes a
        workstation username and workspace path from a 2.7.3-era run. The
        "deidentified" in the file name is not accurate.
  - batch-picker-deidentified.png                Obsolete. Shows the retired
        "local-current" key and a retired batch-call syntax.
  - getting-started.png                          Obsolete. Shows Aether / Launchpad /
        "[Bay8]" legacy profile entries.
  - load-images-empty.png                        Obsolete. Shows OK/Cancel controls and
        placeholder text; the current window uses Run and Close.
  - load-images-populated-deidentified.png       Obsolete. Shows OK/Cancel controls.
  - nifti-folder-structure.png                   Obsolete. Log file name uses the retired
        "local-current" key; current run logs are named pseudoct-run-<UTC>-<uuid>.log.
  - successful-output-folder.png                 Obsolete. Log file name uses the retired
        "local-current" key.
  - profile-selector.png                         Obsolete. Shows a "Legacy Processing"
        group that the current selector does not have.
  - profile-selector-all-groups.png              Obsolete. Shows Aether v2 legacy
        profiles.
  - profile-summary-local-current.png            Obsolete. Shows the retired
        "local-current" key and a R2026a profile summary.
  - software-location.png                        Obsolete. Lists installed 2.7.0 and
        2.7.1 folders.

Hold: not linked; provenance not confirmed. Do not publish until a maintainer confirms
the image is current and shows no identifiers.
  - dicom-folder-structure.png                   Subject folder layout (MR/MPRAGE,
        MR/UMAP) with counts. Appears consistent with the current layout; no names visible.
  - mprage-file-picker-deidentified.png          File-picker title matches the current
        frontend; example paths are generic (/data/study/sub-001/...).
  - dicom-qc-good.png                            Viewer of a volume named
        Head_MRAC_DIXON_in_UMAP. Not a pseudoCT QC image; no run or version visible.
  - fusion-qc-good.png                           Six-view MR/pseudoCT fusion image. No run,
        version or identifiers visible; provenance unknown.

De-identification
-----------------
The file names containing "deidentified" are NOT a de-identification guarantee. The
processing-log screenshot above shows a workstation username and workspace path. The
other screenshots were checked only visually for the items named in the list. No
screenshot has been checked for every possible identifier.
