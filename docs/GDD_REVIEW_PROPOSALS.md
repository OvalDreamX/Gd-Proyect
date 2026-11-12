# GDD review — proposed amendments for owner approval

**Status: REVIEW ONLY.** The canonical `docs/GAME_DESIGN_DOCUMENT_v0_1.md` has not been edited. These proposals are based on the 11 November 2026 repository baseline at commit `2c396eea61f5e949aa25d13b8732e92a20f8e6fa` and should be discussed/approved before any GDD changes are made.

The GDD is a concept/design document, not an implementation log. The intent is not to rewrite the whole document around the current code. The proposed changes would distinguish: (a) confirmed game-design intent, (b) prototype behavior currently implemented, and (c) details that remain open or provisional.

## Proposed changes

### 1. Document status and authority

**Location:** Header, “How to read this document”, and Section 23.

The title/version/date can remain as the original v0.1 concept baseline. Add a short revision note that the document is still the core design authority, while implementation progress is recorded in `IMPLEMENTATION_HISTORY.md`, testing in `TESTING.md`, and Phase 3 environment/travel requirements in `GDD_ANNEX_v0_3.md`.

This avoids turning the GDD into a chronological changelog or duplicating the detailed Phase 3 annex.

### 2. Environment and hyperspace scope

**Location:** Sections 5, 6 and 20.

The GDD's broad hybrid-world architecture remains valid. Phase 3 now has a more specific implementation specification: one compact planet/starport, a separate local-space station environment and a fixed outbound/return hyperspace route. The Phase 3 annex explicitly overrides the GDD only for Phase 3 environment/travel details.

Proposed clarification: make the GDD's general environment description explicitly conceptual, and direct implementers to the Phase 3 annex for the current vertical-slice scope. Do not copy the annex's full implementation detail into the GDD.

### 3. Cockpit and walkaround: prototype versus final experience

**Location:** Sections 7 and 17.3.

The current prototype already has ship interaction, cockpit entry, screen-space flight instruments, diagnostics and operational overlays. The GDD's statements about future physicalized cockpit systems and walkaround inspection remain long-term direction, not current implementation.

Proposed clarification:
- A functional flight HUD exists, but it is not the final cockpit layout or a commitment to physical windshield-mounted symbology.
- The earlier 3D windshield/SubViewport experiment is not the active HUD architecture.
- Physical switches, detailed walkable interiors and system repair interactions remain future work.
- Phase 3 does not require a walkable station interior or a comprehensive cockpit redesign.

The exact final cockpit presentation (screen-space, physical windshield or hybrid) should remain TBD until a rendered prototype is evaluated.

### 4. Startup sequence and power systems

**Location:** Section 8.

The GDD's battery → APU → power stabilization → reactor → repulsorlift generator → vanes sequence is still the intended richer startup concept. The current prototype's F key only operates a simplified field OFF/STARTING/ONLINE state; battery, APU, reactor and a full power-allocation model do not exist yet.

Proposed clarification: label the current F-key behavior as a flight-prototype abstraction of the later startup sequence, not a completed implementation of those systems.

### 5. Repulsorlift force application and cargo COM

**Location:** Section 9.5 and Section 12.2.

Phase 2U corrected the main-field force application point. The main-field resultant acts at the fixed hull reference datum (rigid-body origin), not artificially through a moving centre of mass. A displaced cargo COM therefore creates a real lever-arm moment under the main-field force. Gravity itself is not a torque source merely because the COM moves; gravity acts through the combined COM.

Proposed addition: state this explicitly in the mathematical abstraction and cargo-handling explanation. It is important because the earlier Phase 2T documentation incorrectly described the effect as a gravity-generated moment.

### 6. Prototype freighter rating

**Location:** Sections 9.6 and 12.3.

The current code uses fixed force ratings based on 55,000 kg design gross mass: 30,000 kg dry mass plus 25,000 kg rated payload. The bottom set is 1.10 gross TWR (about 593.5 kN at 9.81 m/s² reference gravity); the rear/main vane is 1.50 gross TWR.

Proposed clarification: keep these as prototype ratings/placeholders unless the owner has decided they are final balance values. Explain that current loaded mass changes acceleration and lift margin but does not increase rated thrust.

### 7. FCC description

**Location:** Section 10.3 and related acceptance criteria in Section 19.

The current assisted FCC is a bounded PI angular-rate controller with anti-windup. Prototype defaults are proportional gain 0.8, integral gain 0.12, per-axis integral-trim cap 0.25 and overall assisted output cap 0.8. The FCC is not an attitude-hold or auto-level system. It may retain limited counter-command against persistent disturbance torque, but saturation and residual rotation are expected when the moment exceeds available vane authority.

The existing partial vane redistribution also has prototype limits: up to 50% of the damaged-output deficit may be redistributed, only into healthy spare capacity, with healthy vanes capped at 1.20× nominal. Maneuver control remains available when the field is online at zero main-vector output, with a capped reserve increase up to 20%.

Proposed clarification: describe bounded PI rate control and identify these figures as prototype defaults, not locked design commitments. Keep final tuning and maneuvering-envelope behavior open where appropriate.

### 8. Cargo: update “not implemented” wording

**Location:** Section 12.3.

The statement that cargo is not yet implemented is now false. Phase 2T/2U implements an abstract manifest containing one payload mass and one hold position. It updates the real rigid-body mass and custom COM, and the F4 panel exposes mass/offset controls and presets. It is not an itemized inventory, physical crate simulation, cargo-volume system, loading animation or contract/economy loop.

Suggested replacement text:

> **PROTOTYPE IMPLEMENTATION —** The current freighter has an abstract cargo manifest with a payload mass and a single hold position. The system updates the ship's rigid-body mass and combined centre of mass. This validates the physical handling consequences of loading, but does not yet implement individual cargo items, slots, inventory, cargo volume, loading interactions, cargo damage, contracts or trading. Those remain later gameplay systems.

### 9. Thermal model: implemented prototype versus final operating rules

**Location:** Sections 13.2–13.3.

The GDD currently describes the thermal model only as proposed/TBD. A game-tuned model now exists. Its current implementation uses a load-dependent green zone (60°C × load^0.7 to 180°C − 20°C × load), online heat input of 3°C/s + 22°C/s × load², cooling coefficient 0.05/s toward ambient, baseline wear 0.000002 integrity/s and quadratic out-of-zone wear coefficient 0.000008. Cold authority is clamped below 60°C; above 180°C and up to 230°C there is a temporary 5% authority bonus; critical temperature or severe degradation can produce sputtering.

Phase 2U ensures thermal progression continues while the field is offline or the body is frozen, with zero load/no operating wear and cooling toward ambient. Loads are estimates from main-vector allocation plus per-vane maneuver contributions, not a complete heat-transfer or energy model.

Proposed clarification: add a clearly labelled “current prototype model” subsection, state that these are provisional game-tuning values, and retain active cooling/radiator management as future work. Remove the outdated 25–35 second full-load overheat expectation; the current coefficients heat substantially faster.

### 10. Godot architecture status

**Location:** Sections 18.1–18.5.

The project is now pinned to Godot 4.7.2 Stable, GDScript and GL Compatibility. The one-RigidBody3D architecture and physics-tick force application are implemented, not merely proposed. The current script responsibilities are more concrete than the illustrative tree in Section 18.3.

Proposed updates:
- Change the one-RigidBody3D strategy from PROPOSED to the project's confirmed/established implementation constraint.
- State the pinned engine/renderer explicitly.
- Align the logical architecture with the actual systems: ShipFlightController, FlightControlComputer, RepulsorliftSystem, VaneController, AtmosphericFlightModel, FlightSensorSuite, CargoSystem and presentation-only HUD.
- Retain data-driven second-ship configuration as a proposal until a second ship validates the design.

### 11. Initial prototype plan and roadmap

**Location:** Sections 19 and 20.

The original cube-and-pad prototype plan has been worked through and expanded across Phases 2A–2U. The initial acceptance criteria remain useful as design goals, but the section currently reads like an upcoming plan. The new implementation history and testing guide are better places for progress and validation status.

Proposed clarification: label Section 19 as the original prototype requirements/acceptance baseline and point to the implementation history/testing guide for current implementation and evidence. Reconcile the roadmap table with the Phase 3 annex: the annex is the current detailed Phase 3 plan and includes the fixed hyperspace round trip in its vertical slice.

### 12. Open questions and handoff brief

**Location:** Sections 21 and 23.

Some questions now have prototype answers but are not necessarily final design decisions. For example: mouse deadzone/curve, FCC gains and output caps, vane Resources/positions, prototype masses, local-up altitude, sensor validity, FPM velocity basis and HUD recenter behavior.

Proposed cleanup:
- Split “implemented prototype default” from “final design still TBD”.
- Keep genuine open questions such as planetary local north, terrain/radar altitude, final cockpit presentation, active cooling, final thermal balance, second-ship data design and final maneuvering envelope.
- Replace the old handoff summary (which describes the cube/early prototype) with a pointer to the current AI handoff and implementation-history documents.

## Approval checklist

Before changing the canonical GDD, confirm:

- Whether 30 t / 25 t / 55 t and the 1.10 / 1.50 TWR ratings remain provisional or are now approved design values.
- Whether the current thermal thresholds/equations should be documented as the prototype baseline only or elevated to confirmed design rules.
- Whether the current screen-space HUD is only a prototype choice or the preferred final cockpit direction.
- Whether the Phase 3 annex remains the authoritative next phase and the broader roadmap in GDD Section 20 should be revised to match it.
- Whether the proposed modding/runtime ship pipeline should remain a deferred idea or be removed from future planning altogether.

No edits to the canonical GDD are included in this documentation cleanup package.
