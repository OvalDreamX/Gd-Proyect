# Phase 2T — Cargo Manifest, Center of Mass & FCC Asymmetry Compensation

## Install
1. Close the running game/editor.
2. Extract the `Space_Trucker_Phase_2T_Cargo_System.zip` overwrite ZIP into your Godot project root (the folder containing `project.godot`).
3. Allow the files to overwrite their matching paths:
   - `scripts/cargo_system.gd`
   - `scripts/ship_interactable.gd`
   - `scripts/ship_flight_controller.gd`
   - `scripts/flight_hud.gd`
   - `scenes/ship.tscn`
   - `tests/cargo_system_test.gd`
4. Open the project in Godot 4.7.2.

---

## What Changed in Phase 2T

### 1. Independent Cargo Subsystem (`scripts/cargo_system.gd`)
- Dedicated `CargoSystem` node attached directly to `PrototypeFreighter`.
- Manages payload mass from **0.0 kg to 25,000.0 kg** (gross rating up to **55,000.0 kg**).
- Computes combined ship Center of Mass (COM) in local ship coordinates:
  $$\vec{R}_{\text{COM}} = \frac{M_{\text{cargo}} \cdot \vec{R}_{\text{cargo}}}{M_{\text{dry}} + M_{\text{cargo}}}$$
- Dynamically sets Godot's `RigidBody3D`:
  - `_ship.mass = total_mass`
  - `_ship.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM`
  - `_ship.center_of_mass = combined_com`
- **Single RigidBody3D Law Preserved:** Vanes remain fixed mathematical actuators at physical mount positions; they are never displaced or jointed.

### 2. Interactive In-Game Cargo Manifest Panel (**F4 Key**)
- Pressing **F4** anywhere in flight or on the ground opens the **Cargo Manifest & FCC Compliance Panel**.
- **Mouse Release:** Toggling F4 releases the cursor (`Input.MOUSE_MODE_VISIBLE`) and freezes flight control inputs so the pilot can safely click sliders and buttons. Pressing **F4** again or **Escape** closes the panel and re-captures the mouse for flight.
- **Quick Preset Buttons:**
  - `[EMPTY (30t)]`: 0 kg payload, COM at origin, hover throttle ~49.6%.
  - `[HALF (42.5t)]`: 12,500 kg payload centered, hover throttle ~70.5%.
  - `[MAX GROSS (55t)]`: 25,000 kg payload centered, hover throttle ~90.9%.
  - `[PORT HEAVY (-1.2m)]`: 20,000 kg offset 3m to port ($X = -3.0\text{m}$). Shifts ship COM to $X = -1.2\text{m}$. Generates **~588 kN·m** roll moment!
  - `[STBD HEAVY (+1.2m)]`: 20,000 kg offset 3m to starboard ($X = +3.0\text{m}$). Shifts ship COM to $X = +1.2\text{m}$.
  - `[NOSE HEAVY (-1.6m)]`: 20,000 kg offset 4m forward ($Z = -4.0\text{m}$). Shifts ship COM to $Z = -1.6\text{m}$. Generates **~784 kN·m** pitch moment!
  - `[AFT HEAVY (+1.6m)]`: 20,000 kg offset 4m aft ($Z = +4.0\text{m}$). Shifts ship COM to $Z = +1.6\text{m}$.
- **Interactive Sliders:**
  - Payload Mass: 0 to 25,000 kg (step 250 kg)
  - Port / Starboard (X): -4.0 m to +4.0 m
  - Deck Vertical (Y): -1.0 m to +1.0 m
  - Fore / Aft (Z): -6.0 m to +6.0 m
- **Real-Time Physics Readout:**
  - Active Preset & Payload Mass
  - Total Gross Mass & % of 55t Gross Rating
  - Combined Center of Mass Vector $(X, Y, Z)$
  - Theoretical 1g Hover Throttle %
  - FCC Trim Compensation Analysis

### 3. Flight Control Computer (FCC) Asymmetric Load Compensation
- When the COM shifts off-center (e.g. port heavy), gravity acting at the shifted COM creates a continuous roll/pitch torque around the ship's geometric center.
- The FCC stability augmentation loop senses the induced angular rate error and trims the opposing vanes (e.g., lowering starboard vane thrust or raising port vane thrust) to maintain steady level hover!
- When you open the **F3 Diagnostics Panel**, the `[ CARGO & CENTER OF MASS (PHASE 2T) ]` section shows whether the ship is balanced or if active FCC trim compensation is engaged.

---

## Verification & Tests

Run the new headless regression test suite:
```powershell
& $godot --headless --path . --script res://tests/cargo_system_test.gd
& $godot --headless --path . --script res://tests/vane_thermal_model_test.gd
& $godot --headless --path . --script res://tests/vane_force_model_test.gd
```

### In-Game Test Procedure (F5)
1. Launch game (**F5**), board ship (**F**), start repulsorlift (**R**).
2. Let vanes warm up gently to 60°C.
3. Press **F4** to open the Cargo Manifest. Notice your mouse cursor appears.
4. Click **[PORT HEAVY (-1.2m)]**. Observe the COM shift to $(-1.20, 0.00, 0.00)\text{m}$.
5. Press **F4** or click **Resume Flight**.
6. Take off with **W**. Observe how the FCC trims the vanes to hold the freighter level despite the massive 20-ton asymmetric load!
7. Press **F3** to inspect individual vane force differences compensating for the off-center load.
