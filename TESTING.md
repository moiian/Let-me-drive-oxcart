# Prototype validation

Automated Lua 5.3 checks passed on 2026-10-04:

- Complete new controller and Journey compatibility script syntax.
- Mocked runtime: control claim/release and exactly one Journey handoff.
- Four movement stages and clamping at both ends.
- External locomotion requests blocked while owned; internal requests allowed.
- Mouse left/right edges; held mouse does not repeat; RB accelerates.
- Keyboard smoothing, analog steering sign, release heading hold.
- Pause suppresses movement input.
- Damage 100 becomes 1 for the player; unrelated receiver unchanged.
- Driver/player/pawn original FSM enabled states restored.
- Broken cart, distance departure and injected seat failure release control.
- Standalone works; an old Journey without the adapter is rejected.
- Full menu rendering against the documented UI surface and ignoring menu clicks.
- Actual Journey handoff block tested separately: clears filters/jobs, restores
  its layout only once and excludes the manual-driving interval from its clock.

Rerun the controller tests with `tests/run-tests.ps1` (Python and Lua 5.3 DLL
required; use `-LuaDll` to select another compatible DLL).

These tests simulate the APIs, not the running game. Test the installed build:

1. Stand by a cart, press G / RT. Confirm native driver is moved aside,
   player takes the driving seat, pawns use the new layout.
2. Accelerate through Wait/Walk/Run/Dash and decelerate back. Verify mouse,
   pad, keyboard fallback, modifier and direction control.
3. Pause/photo mode then resume; direction/speed should not change from menu input.
4. Release with F / B; confirm actors can move normally and Journey's original
   layout is usable again. Navigation recovery remains controlled by the game.
5. Reset scripts while driving; confirm no actor stays frozen.
6. Test incoming damage on player, pawn, ox and cart parts. Multiplier is 0.01,
   not immunity to physics/scripted breaking.
7. Disable Journey and repeat takeover to verify standalone operation.

Do not publish this prototype before these runtime checks. No Nexus page or
remote repository was created or modified for the new mod.
