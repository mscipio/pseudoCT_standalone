# pseudoCT_standalone

Atlas-based pseudoCT generation for PET/MR attenuation correction from a T1-weighted MPRAGE, using the SPM8-based method of Izquierdo-Garcia et al. (*Journal of Nuclear Medicine*, 2014;55(11):1825–1830).

For Martinos users, use the centrally deployed version and the [PseudoCT User Guide](https://mscipio.github.io/pseudoCT_standalone/help/) for the complete workflow. For external installation requirements and configuration, see [Installation](docs/installation.md). Method, evidence, and limitations are summarized in [Scientific notes](docs/scientific-notes.md).

## Quick start (Martinos)

Use the deployed version under `/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/`. Add the installation root to MATLAB's path:

```matlab
addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-latest')
% Numbered installed version:
% addpath('/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/pseudoCT_standalone-3.1.0')
run_pseudo_CT
```

Select **PseudoCT v3 — MLSC** (the recommended default) for routine processing. **PseudoCT v3 — Local** remains available; it uses the MATLAB version you choose, and results may vary. The full instructions cover inputs, batch processing, output review, and remote profiles. MATLAB must remain open through processing and remote monitoring/finalization.

## Profiles and release

Standard Processing offers **PseudoCT v3 — MLSC** (`mlsc-current`, recommended default) and **PseudoCT v3 — Local** (`local-current`). MPRAGE-only Processing and Legacy Processing remain available as separate choices. Center Standard fails closed on missing or invalid runtime/artifact requirements; it does not silently fall back to Local or a historical profile. See [Installation](docs/installation.md) for profile labels, descriptions, availability, and requirements.

The source version metadata is **3.1.0**. The v3.0.2 published archive and its history are preserved in the [release history](CHANGELOG.md); v3.0.0 and v3.0.1 remain withdrawn. Setting source version metadata does not itself assert publication or deployment. Always inspect generated QC before using an attenuation map.
