# Ship Asset Pipeline — Phase 2A

## Contents

New files only; no existing project files are replaced:

- `scripts/ship_model_loader.gd` — runtime GLB import using `GLTFDocument` / `GLTFState`.
- `scripts/ship_model_validator.gd` — structural and naming validation.
- `scripts/ship_anchor_registry.gd` — lookup for `ANCHOR_` nodes.
- `tests/ship_model_pipeline_test.gd` — path, validation, registry and runtime GLB tests.
- `tests/assets/ship_model_fixture.glb` — small generated fixture used by the runtime loader test.
- `docs/SHIP_ASSET_PIPELINE.md` — canonical asset contract and complete authoring/export requirements.
- `docs/BLENDER_SHIP_AUTHORING.md` — short Blender workflow reference.

## Install

Extract this ZIP into the Godot project root and merge folders. This package adds files only. No existing scripts, scenes, Resources, JSON files, project settings or environment files need to be overwritten or deleted.

Keep all existing `.gd.uid` sidecars. Godot may generate UID sidecars for the new scripts on first project scan; keep those generated files in the repository.

## Test

Run from the project root with Godot 4.7.2 Stable:

```powershell
godot --headless --path . --script res://tests/ship_model_pipeline_test.gd
```

The runtime fixture test checks that the engine can parse a real GLB, generate its scene tree, preserve named anchors and validate the interaction node. This test must be run inside Godot; ZIP and binary-format checks alone are not a substitute.

## Scope boundary

Phase 2A creates a usable loader and freezes the Blender/GLB contract, but does not change the active ship scene. Phase 2B will integrate the loader with a model mount and visible placeholder fallback. Later subphases will wire actual anchors into cameras, vanes and ground-effect probes, then add animation playback and interaction hitboxes.
