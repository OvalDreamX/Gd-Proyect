# Ship Modding — Phase 1: Definition Format

This phase establishes the versioned JSON format and strict parser. It does **not** yet spawn ships from JSON, load external GLBs, or replace the existing prototype scene. Those are later phases.

## Folder layout

A future installed mod will use one folder per ship:

```text
user://mods/ships/<ship-folder>/
    ship.json
    model.glb
```

Built-in ship definitions live under `res://data/ships/<ship-folder>/`. The `model` field is a relative `.glb` path within that folder. Do not use absolute paths or `..` path segments.

## Units and coordinate convention

- Distances: metres.
- Mass: kilograms.
- Forces: newtons where explicitly represented.
- Angles: degrees unless a field says otherwise.
- Model axes: ship nose `-Z`, up `+Y`, right `+X`.
- One GLB unit: one metre.
- GLB root origin: ship rigid-body reference origin.

## Schema version 1

Required top-level fields:

- `schema_version`: currently `1`.
- `id`: unique lowercase identifier; letters, numbers, `.`, `_`, and `-` only.
- `display_name`: non-empty player-facing name.
- `model`: relative `.glb` path.
- `physics`: dry mass, dry centre of mass, hull dimensions and payload rating.
- `cargo`: cargo hold bounds and distribution envelope.
- `propulsion.vanes`: non-empty array of unique vane IDs, GLB anchor names, groups and authority TWR.

Optional sections are retained as dictionaries for later phases: `identity`, `handling`, `aerodynamics`, `ground_effect`, and `cameras`.

## Validation

`ShipDefinitionLoader` parses and validates JSON before constructing a `ShipDefinition`. It rejects unsupported schema versions, malformed identity/model paths, non-finite or invalid physical values, inverted cargo bounds, missing vane fields and duplicate vane IDs. Model-anchor existence checks occur in the GLB-loading phase.

## Reference definition

`data/ships/prototype_freighter/ship.json` records the current prototype's dry mass, payload rating, hull dimensions, cargo envelope and seven existing vane ratings/groups. Its model path is intentionally reserved for the next phase; there is no GLB in this package.

## Test

Run from the project root:

```sh
godot --headless --path . --script res://tests/ship_definition_loader_test.gd
```

## Planned follow-up phases

1. Convert the current prototype model into the documented GLB hierarchy with cockpit, vane and ground-probe anchors.
2. Build runtime GLB loading and anchor validation.
3. Build the generic ship scene/factory and instantiate the prototype from this definition.
4. Move the existing hard-coded propulsion control sets, cargo settings, handling and aerodynamic parameters into the definition.
5. Add `user://mods/ships` discovery, duplicate-ID policy, safe error reporting and an in-game/open-folder workflow.
6. Integrate ground effect using per-ship probe anchors and configuration.
