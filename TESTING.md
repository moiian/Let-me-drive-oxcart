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
- Player requests SitOnChairActions while enabled, then freezes next behavior
  frame; no random player idle is requested even if a config enables that flag.
- Driver seat uses the requested fixed MoveFloor offset, not entry/player or
  native-driver position. Edited seats survive reacquisition and preset cycling.
- No seat constraint invokes Character warp; on_frame does not mutate actors.
- Pawn FSM remains enabled in the action-request frame and freezes next frame.
- DEBUG player-freeze toggle works on takeover, live and while paused; no pawn
  is unfrozen by the toggle. Re-enabling freeze has a deferred frame boundary.
- Unloaded body get_GameObject exception while paused clears the ownership
  lease, restores surviving actors and permits subsequent acquisition.
- Journey pawn coordinates, facing and animation nodes are inherited through
  a copied layout (no mutable shared preset table).
- Broken cart, distance departure and injected seat failure release control.
- Standalone works; an old Journey without the adapter is rejected.
- Full menu rendering against the documented UI surface and ignoring menu clicks.
- Actual Journey handoff block tested separately: clears filters/jobs, restores
  its layout only once and excludes the manual-driving interval from its clock.

Rerun the controller tests with `tests/run-tests.ps1` (Python and Lua 5.3 DLL
required; use `-LuaDll` to select another compatible DLL).

These tests simulate the APIs, not the running game. Test the installed build:

1. Load a clean game state, stand/sit on a cart, press G / RT. Confirm native
   driver is moved aside, player moves to its configured fixed seat and follows the
   cart visibly as well as through the camera; pawns use Journey's layout.
2. Accelerate through Wait/Walk/Run/Dash and decelerate back. Verify mouse,
   pad, keyboard fallback, modifier and direction control.
3. Pause/photo mode then resume; direction/speed should not change from menu input.
4. Release with F / B; confirm actors can move normally and Journey's original
   layout is usable again. Navigation recovery remains controlled by the game.
5. Reset scripts while driving; confirm no actor stays frozen.
6. Test incoming damage on player, pawn, ox and cart parts. Multiplier is 0.01,
   not immunity to physics/scripted breaking.
7. Disable Journey and repeat takeover to verify standalone operation.

In-game reports showed controller/camera following while visible bodies stayed
behind, even standalone. The current comparison build removes recurring warp,
uses the same LateUpdateBehavior constraint timing as Journey and defers pawn
freeze one gameplay frame. Runtime confirmation is required; the simulation
does not prove engine/model synchronization or establish a root cause.

Do not publish this prototype before these runtime checks. No Nexus page or
remote repository was created or modified for the new mod.
