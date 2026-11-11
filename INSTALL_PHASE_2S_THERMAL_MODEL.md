# Phase 2S — Vane Thermal Simulation, Green Zone & Quadratic Degradation

## Install
1. Close the running game/editor.
2. Extract the `Space_Trucker_Phase_2S_Thermal_Model.zip` overwrite ZIP into your Godot project root (the folder containing `project.godot`).
3. Allow the files to overwrite their matching paths:
   - `scripts/vane_controller.gd`
   - `scripts/repulsorlift_system.gd`
   - `scripts/atmospheric_flight_model.gd`
   - `scripts/flight_hud.gd`
   - `tests/vane_thermal_model_test.gd`
4. Open the project in Godot 4.7.2.

---

## What Changed in Phase 2S

### 1. Load-Dependent Green Zone Operating Envelope (Turbine / Jet Engine Model)
- Repulsorlift vanes now have individual temperatures modeled in degrees Celsius (°C).
- For each vane's commanded throttle load, there is a dynamically computed **Green Zone**:
  - Minimum safe temperature: $T_{\text{min}} = 60.0^\circ\text{C} \times (\text{load})^{0.7}$
  - Maximum continuous temperature: $T_{\text{max}} = 180.0^\circ\text{C} - (\text{load} \times 20.0^\circ\text{C})$
- **Inside the Green Zone:** Wear is at minimal nominal baseline ($0.000002/\text{s}$, virtually zero degradation).
- **Outside the Green Zone:** Wear rate follows a **quadratic curve** based on the distance $(\Delta T)^2$ from the green zone boundary scaled by demanded power:
  $$\text{Wear Rate} = \text{Base Wear} + k_{\text{wear}} \cdot (\Delta T)^2 \cdot (\text{load}^2)$$

### 2. Cold Planet Start & Thermal Shock
- Planetary ambient temperature defaults to **-10.0°C** on the cold test range (`AtmosphericFlightModel.ambient_temperature_celsius = -10.0`).
- **Warmup Requirement:** When first starting the repulsorlift field on a cold planet, vanes require **10–20 seconds** of gentle idle/low-throttle operation to warm up to the nominal 60.0°C threshold.
- **Cold Authority Clamping:** Cold vanes below 60.0°C cannot produce 100% force (clamped between 70% and 100% based on warmup progress).
- **Cold Strain Damage:** Demanding 90–100% power immediately on startup while cold generates severe thermal shock ($\Delta T \approx 70^\circ\text{C}$), visibly degrading vane integrity within seconds!

### 3. Maximum Continuous Rating & Overheat Overdrive
- Sustained flight above 90% power generates heat faster than ship radiators can dissipate (+22°C/s heat vs cooling).
- Holding 100% power for more than 25–35 seconds pushes vane temperatures past 180°C into `OVERHEAT` and eventually `CRITICAL` (>230°C).
- Hot vanes in overdrive provide a temporary 5% thrust bonus, but suffer severe quadratic degradation and trigger **sputtering** (intermittent thrust drop) and structural failure when integrity reaches zero.

### 4. Real-Time Telemetry & F3 Diagnostic Panel
- Pressing **F3** now displays the live **`[ VANE THERMAL & GREEN ZONE (PHASE 2S) ]`** table:
  - Ambient planetary temperature
  - Each vane's temperature (°C), status (`COLD_STRAIN`, `GREEN_ZONE`, `OVERHEAT`, `CRITICAL`)
  - Target Green Zone bounds `[min - max]` for its active load
  - Real-time commanded load percentage
  - Real-time wear rate (%/s)
  - Sputter warnings

---

## Verification & Tests

Run the new headless regression test suite from PowerShell in the project root:
```powershell
& $godot --headless --path . --script res://tests/vane_thermal_model_test.gd
& $godot --headless --path . --script res://tests/vane_force_model_test.gd
& $godot --headless --path . --script res://tests/flight_path_marker_test.gd
```

### Manual In-Game Flight Test (F5)
1. Launch the game with **F5**, approach the ship, and press **F** to board.
2. Press **F3** to open the diagnostics panel and scroll to `[ VANE THERMAL & GREEN ZONE (PHASE 2S) ]`.
3. Notice all vanes start at `-10.0°C` with status `COLD_STRAIN`.
4. Press **F** to spool up the repulsorlift field:
   - **Test Cold Shock:** Immediately slam throttle to 100% (`W`). Watch the front and rear bottom vanes enter high quadratic wear ($\approx -0.38\%/\text{s}$) and their integrity drop in real time!
   - **Test Gentle Warmup:** Press `F` to reset/restart, set throttle to 30-40%. Watch vanes smoothly warm up to 60°C within 12-16 seconds, transition into `GREEN_ZONE`, and drop wear to nominal zero!
