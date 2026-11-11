# Historical note — Phase 2Q windshield SubViewport experiment

This document describes an experimental 3D windshield projection path. It is retained as history only.

**It is not the active HUD architecture in the current repository baseline.** The current `FlightHUD` / `FlightHUDOverlay` scripts use the screen-space `CanvasLayer` implementation, with central symbology gated by cockpit view and camera alignment. Side gauges and control indicators remain screen-fixed and visible in external view.

Do not use this historical experiment's `SubViewport`, quad or material instructions as current setup requirements. The stable screen-space implementation is described in `INSTALL_PHASE_2Q_HUD_RECENTER.md` and the current code.
