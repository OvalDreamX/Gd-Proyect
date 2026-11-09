# AI Handoff — Space Trucker Phase 1

Use this file together with the project's master Game Design Document.

## Current verified intent

The user requested only the first interaction slice:

1. Start in a first-person walking mode next to a placeholder cube-like spaceship.
2. Walk close enough to the ship.
3. Show a prompt to pilot it.
4. Press F.
5. Play a short tweened transition and move the player to the cockpit.
6. Switch to a cockpit camera.

Do not implement flight controls, repulsorlift behavior, reactor startup, cargo, or other systems yet.

## Architecture in this slice

- Godot 4.7.2 stable, GDScript, GL Compatibility renderer.
- `PlayerController` is a `CharacterBody3D`.
- Ship root is a frozen `RigidBody3D`, retained for future flight physics.
- Ship `Area3D` reports proximity to the player.
- `PlayerController` owns its prompt UI and transition fade.
- The ship supplies a seat marker, cockpit camera, hull visual and cockpit-interior placeholder.
- During entry, the view dims, the placeholder hull is hidden, cockpit-interior geometry is revealed, and the first-person camera dollies to the cockpit camera position. A brief final fade masks teleporting the player body to the seat marker and switching the active camera. Player collision and physics processing are then disabled.

## Important current limitations

- No way to exit the cockpit yet. Restart the scene to repeat the interaction.
- The placeholder hull is hidden while in cockpit because it is a solid box.
- No ship control or physics simulation is implemented.

## Development discipline

Keep changes incremental. Test the current project before adding another subsystem. Preserve the separation between player locomotion, ship interaction and future ship flight physics. Do not replace the `RigidBody3D` ship root without a strong reason.
