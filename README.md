# Space Trucker — Phase 1 Prototype

**Target engine:** Godot 4.7.2 stable (GDScript, standard edition; no .NET required)

This is the first playable interaction slice. It deliberately does **not** include flight physics, ship systems, walking inside the ship, or a way to leave the cockpit yet.

## What is implemented

- A first-person player spawns on a simple test range beside a blocky freighter.
- WASD movement, mouse look, Space to jump, and Escape to release the mouse.
- A spherical proximity area detects the player near the ship.
- A `PILOT SHIP [F]` prompt appears while in range.
- Pressing F starts a short tweened transition: the view dims, the placeholder hull is hidden, the cockpit interior is revealed, and the first-person camera dollies toward the cockpit.
- A brief final fade masks the player-body teleport to the seat anchor and the handoff to the cockpit camera. Player movement and collision are disabled afterward.
- The cockpit view contains a very simple dashboard and window-frame placeholder.

## Run it

1. Extract the ZIP file.
2. Open Godot 4.7.2 stable.
3. In the Project Manager, choose **Import**.
4. Select the `project.godot` file inside this folder.
5. Open the project and press **F6** only if you want to run the current scene; otherwise press **F6** is unnecessary — press **F6** to run the project main scene? Use **F6** for current scene and **F5** for project. The intended shortcut is **F6**? See note below.

**Run:** press **F6** to run the current scene only when `test_range.tscn` is open, or **F5** to run the project's configured main scene.

## Controls

| Input | Action |
|---|---|
| W / A / S / D | Walk |
| Mouse | Look around |
| Space | Jump |
| F | Pilot ship when prompt is visible |
| Escape | Release mouse capture; click to capture again |

## Current limitations (intentional)

- Once seated, the cockpit camera is active but the ship cannot move yet.
- There is no exit/disembark input in this slice; restart the scene to test again.
- The ship is frozen in place. Its root is already a `RigidBody3D` so the later flight model can build on it.
- The hull disappears during the cockpit handoff because this first placeholder hull is a solid box, not a modeled walkable interior.
- The player capsule is hidden by design; this is a first-person prototype.

## Scene and script structure

```text
res://
  project.godot
  scenes/
    test_range.tscn
    player.tscn
    ship.tscn
  scripts/
    player_controller.gd
    ship_interactable.gd
```

### Responsibilities

- `player_controller.gd`: first-person movement, look, prompt UI, interaction, and cockpit-entry transition.
- `ship_interactable.gd`: proximity detection and request routing to the pilot seat.
- `ship.tscn`: placeholder rigid-body freighter, proximity area, seat anchor, cockpit camera and basic cockpit geometry.
- `test_range.tscn`: ground, landing pad, lighting, player spawn and ship instance.

## Next intended milestone

After this interaction slice is confirmed working on the user's machine, add a clean way to leave the cockpit / return to walking mode, then begin the actual ship flight prototype. Do not add the flight model to this project phase without an explicit request.

## Troubleshooting

- If the mouse is visible, click the game window to capture it.
- If the prompt does not appear, walk toward the freighter until inside its interaction radius.
- If Godot reports parse errors, record the exact version and copy the first error with its file and line number; fix the first parse error before chasing later errors.
