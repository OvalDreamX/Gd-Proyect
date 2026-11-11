# Project Context & Technical Guidelines: "Space Trucker" Moddable Ship Pipeline

## 1. Project Overview
- **Engine**: Godot 4.7.2 Stable (GDScript only, no .NET).
- **Genre/Aesthetic**: First-person space trucking simulator with a PS1/90s retro demake aesthetic.
- **Core Goal**: Create a highly moddable ship system where modders can add new ships, cockpits, and animations **without ever opening the Godot Editor**. 
- **Architecture Principle**: Data-driven runtime loading. The game must parse `.json` configuration files and dynamically load `.glb` (glTF Binary) models at runtime using Godot's `GLTFDocument` API.

## 2. Mod Directory Structure
All mods must follow this strict directory structure to be recognized by the `ModManager`:
```text
res://mods/
  └── [ship_id]/                 # e.g., freighter_mk1
      ├── mod.json               # Core configuration, mappings, and stats
      ├── models/
      │   └── ship.glb           # The entire ship model (meshes, armature, animations)
      └── textures/              # Optional: Texture overrides or specific UI elements
          └── hull_diffuse.png