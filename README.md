# pseudoCT_standalone

Atlas-based pseudoCT generation for PET/MR attenuation correction from a T1-weighted MPRAGE, using the SPM8-based method of Izquierdo-Garcia et al. (*Journal of Nuclear Medicine*, 2014;55(11):1825–1830).

For Martinos users, use the centrally deployed version and the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/) for the complete workflow. For external installation requirements and configuration, see [Installation](docs/installation.md). Method, evidence, and limitations are summarized in [Scientific notes](docs/scientific-notes.md).

## Quick start (Martinos)

Use the deployed version under `/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/`. Add the installation root to MATLAB's path:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
% Numbered installed version:
% addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-3.0.2')
run_pseudo_CT
```

Select **LOCAL - Current** for routine processing. The full instructions cover inputs, batch processing, output review, and remote profiles. MATLAB must remain open through processing and remote monitoring/finalization.

## Profiles and release

There are five recommended profiles (`local-current`, `mlsc-current`, `local-legacy`, `mlsc-legacy`, `launchpad-legacy`) and three specialized profiles (`local-mprage-only`, `mlsc-mprage-only`, `devel`). The standard workflow uses MPRAGE + UMAP; MPRAGE-only profiles are for specialized workflows. See [Installation](docs/installation.md) for profile availability and requirements.

The source version is **3.0.2**. v3.0.0 and v3.0.1 are withdrawn; v2.8.4 remains the last published archive. See [release notes](RELEASE_NOTES_v3.0.2.md) and [release history](CHANGELOG.md). Always inspect generated QC before using an attenuation map.
