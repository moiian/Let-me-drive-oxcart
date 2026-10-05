# Prototype validation

## Native interaction branch: empty driver seat only

`experimental/native-interaction` preserves the non-native implementation on
`direction/non-native`. This first test does not enable driving controls.

1. Reload scripts and approach an oxcart with an empty driver seat. Do not use
   manual Take control or the older driver exit/animation test buttons.
2. Open `aelinore debug tool` > `Native driver-seat interaction`.
3. `Inspect empty driver point` is read-only. `Enter native driver seat` adds
   only the Player flag to the uniquely resolved driver point and requests the
   native interaction. Ambiguous mappings and occupied seats are rejected.
4. Success requires `CONFIRMED`: native DrivingSeat occupant, active interaction
   object and point must all match the player and selected driver point.
5. Use `Exit native driver seat`; the original flag is restored after native
   interaction completion. No forced player pose, position, FSM or fall reset
   is applied by this test.

Each attempt writes `reframework/data/AelinoreNativeSeat_*.log` automatically.
If entry fails, report that result; the log contains point mapping and errors.
Mocks validate the control flow, not the game's ability to accept a player at
the native driver point. In-game acceptance is still to be tested.

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
6. Test incoming damage on player, pawn, ox and cart parts. Seat-bound players
   and pawns skip damageProc; ox/cart retain 0.01 damage. Release restores actor
   damage processing. Direct scripted deaths/breaking are not covered.
7. Disable Journey and repeat takeover to verify standalone operation.

In-game reports showed controller/camera following while visible bodies stayed
behind, even standalone. The current comparison build removes recurring warp,
uses the same LateUpdateBehavior constraint timing as Journey and defers pawn
freeze one gameplay frame. Runtime confirmation is required; the simulation
does not prove engine/model synchronization or establish a root cause.

Do not publish this prototype before these runtime checks. No Nexus page or
remote repository was created or modified for the new mod.

## Player-only visual-seat experiment

- Default OFF. Enable DEBUG > Experimental player visual seat offset.
- Actor root uses the tested rear seat (-0.071, 0.920, -0.856). Player driver
  preset sliders now specify the visible skeleton seat; try (-0.071, 0.920,
  0.274), yaw 178 for the front driver bench. Pawns are unchanged.
- Player-only root/view sliders are relative to that rear origin: X -2..2,
  upward 0..2, backward 0..4 (negative local Z). No forward/downward offset.
  Bounds are enforced when loading settings and writing actor positions.
  Root sliders must leave the visible seat and pawn positions unchanged.
- Root-joint translation is applied after UpdateJointExpression and removed
  before UpdateBehavior. It preserves the current animation pose rather than
  freezing motion. Turning OFF/releasing/resetting restores the root joints.
- On control release, the player actor/camera root aligns to the visible driver
  seat before the skeleton offset is removed, keeping the body at its seat.
  Layout rebinds do not perform this release handoff; unloaded carts skip it
  while still clearing offsets, restoring FSMs and releasing ownership.
- Verify body, armor, weapons, sitting loop, camera, pause/photo mode and the
  previous return-to-origin distance. Check OFF and release restoration too.
- DEBUG reports Applied root count or Unavailable error. This experiment does
  not prove colliders or camera targets are independent of the shifted skeleton.
- Mock coverage includes non-accumulation, animated root-pose preservation,
  unchanged actor/pawn positions, paused updates, slider edits, OFF/release
  cleanup and unavailable-skeleton handling.

## Player root / physics / context synchronization experiment

- DEBUG > Synchronize player root / physics / position context defaults ON.
- Player only: existing scene-space Transform seat constraint, universal-space
  CharacterPosRotContext.setPos(via.Position), then the existing main physical
  CharacterController.warp() (zero arguments) at the same LateUpdateBehavior
  write site. No Character.warp, collision disable, capsule resizing, local
  controller offset edits or physics changes to pawns/driver/ox/cart.
- Physical warp behavior needs runtime verification; the reported controller/root
  gap is a readback, not proof that contact processing cannot move it later.
- Split mode follows the rear gameplay root, not the front display skeleton.
  Release-to-body handoff synchronizes the player at the visible seat before
  restoring the display joints. Unloaded actors/cart still use existing cleanup.
- First reproduce the previous front-seat return with visual split OFF and sync
  ON, using the lightweight recorder. Check for return-to-origin, camera shaking,
  position context following universal root, and controller Y gap. Mark any bug.
- Sync OFF is the previous transform-only baseline. Changing the switch does
  not modify FSM or visual split choices. Do not change other parameters during
  the A/B run. Test split ON/release/photo mode after the direct-seat run.
- Lua/mock tests cover coordinate spaces, player-only scope, toggle, rear root,
  release handoff, inactive behavior and missing-controller failure cleanup.
  In-game behavior remains unverified until the user reproduces these scenes.

## Player-only fall reference reset experiment

- DEBUG > Reset player fall tracking while driving defaults ON and is saved
  independently of FSM freeze, visual split and root/physics/context sync.
- After each controlled player seat write, call FallInfo.resetBaseHeight with
  the player's universal via.Position and FallInfo.resetFallHeight(). No
  contact/ground flag edits, collision disable or animation request is added.
- Resets apply only while control is active, including photo-mode position
  constraints. They stop before release-to-display alignment, on release,
  unloaded session or existing controller cleanup. Pawns are not affected.
- Reproduce at the front driver seat with FSM freeze OFF, position sync ON,
  visual split OFF. Drive through the city and the previous downhill road.
  Use lightweight recording; mark blackouts and note persistent falling pose.
- Falling animation may persist because this experiment does not spoof ground
  detection or lock animation. Compare blackout incidence and FallHeight first.
- Trace records reset_fall, fall_reset_status and base_fall_position_raw.
- Mocks cover player-only scope, universal position, independent switches,
  split-root targeting, no FSM modification and stopping on release. Engine
  effectiveness is not yet confirmed by these tests.

## Player sitting-pose request lock

- New default: Protect player sitting pose (keep FSM running) ON; Freeze player
  FSM OFF. One-time player_pose_lock_rule migration overrides the previous saved
  freeze=ON. Legacy freeze remains a debug option, not the normal test mode.
- Reuses the existing requestActionCore hook: for the seat-bound player only,
  external layer-0 requests other than SitOnChairActions are skipped. Own script
  requests bypass the filter. Other actors and higher layers keep their behavior.
- No per-frame sitting-action reissue, animation-layer freeze, FSM disable,
  collision disable or global action block is added. Damage protection and
  player position/fall synchronization remain unchanged.
- DEBUG and trace include block count and last blocked action name. This covers
  the requestActionCore entry point only; direct motion/state changes may bypass
  it and require evidence from an in-game test.
- Test attacks on the front driver seat, movement/jump/skill input, sitting loop,
  the previous downhill route, then release control and verify normal actions.
  Freeze player FSM must remain OFF. Keep the lightweight recorder enabled;
  mark any sit interruption or blackout and report the last blocked action.
- Mocks verify filtered damage/fall/locomotion requests, allowed sitting and
  secondary layers, unchanged pawn requests, live FSM, OFF and release behavior.

## Seated pawn extension (current behavior supersedes player-only notes above)

- The existing position-sync, pose-lock and fall-reset switches now apply to
  the player AND the three seat-bound pawns. Internal setting keys retain their
  old names for config compatibility; DEBUG labels explicitly name both scopes.
- Pawn FSMs always run during seat control, ignoring old preset freezeFsm flags.
  The optional legacy Freeze player FSM switch remains player-only. Original
  pawn FSM enabled states are captured and restored on release/rebind/cleanup.
- Pawn slot coordinates, custom/direct motion presets and random idle timing
  are unchanged. Random actions requested by this mod bypass the primary-action
  hook; the currently selected named sitting node is allowed through as well.
  Other external primary actions are blocked only for seat-bound player/pawns.
- Driver/ox/cart transforms, FSM handling and old Oxcarts Journey Redux files
  are not changed by this extension. Existing seat damage immunity remains.
- DEBUG shows pawn blocked requests, current pose and synchronization readback.
- Test all three pawns at the troublesome front/high seats: downhill travel,
  random book/cross-leg/lean changes, attacks, stop, preset cycle and release.
  Enable Record pawns (height issue) for the next diagnostic run. Confirm normal
  following/actions return after release and unloaded/damaged cart cleanup.
- Mocks pass player/pawn scene-universal sync, physical alignment, live FSM,
  random pose requests, shared OFF switches, original FSM restoration and
  destruction cleanup. Actual pawn engine behavior still needs game testing.

## Per-layout player visual offset (supersedes restricted root ranges)

- Experimental player visual seat offset now lives in Driving seat presets.
  Each layout owns its enabled flag and root/view X/Y/Z offsets; both menu and
  E/controller preset cycling select these values. Adding a layout copies them
  independently. Visible player body coordinates remain in Player driver.
- All root offsets accept -10 to +10. Positive Y is up, positive Z is forward;
  zero retains the existing root origin (-0.071, 0.920, -0.856). Forward and
  downward movement are allowed. Release still aligns the root to the body.
- Old global settings seed each legacy layout without changing the signed Z
  values. New layout-specific values take precedence; saves use only the new
  layout-owned representation. Invalid/non-finite offsets are sanitized.
- Mocks cover copied-layout independence, menu/hotkey switching, enabled/OFF
  transitions, forward/downward movement, clamps, legacy conversion and release.
  Wide offsets and preset transitions still need in-game validation.

## Cart families, actions, bindings and native HUD

- Active body model gm80_042_00 selects Normal, other gm80_042 variants select
  Rainy, gm80_052 variants select Wealthy. Unknown models fall back to Normal.
  Each preset has a family and cycling flag. Takeover and cycling select only
  enabled layouts of the current family; an empty family gets a default.
- Older layouts are retained as Normal; one-time cart_family_rule migration adds
  measured Normal/Rainy defaults from the supplied screenshots, plus an editable
  Wealthy starting layout. Existing saved edits are not overwritten. Family
  selections persist; each layout still owns its visual offsets and body slots.
- Player and pawn action names and Bank/Motion IDs are editable. Player animation
  remains fixed, pawn random idles remain optional; live changes re-arrange seats
  on the next unpaused gameplay update. FSM/sync/fall protection remains intact.
- Four actions have separate reflected keyboard/mouse/gamepad dropdowns, including
  None and a restore-defaults button. Defaults E/X Sit, F/A Stand, W/mouse-left/LB
  Accelerate, S/mouse-right/RB Decelerate. Takeover G/RT, A/D steering and modifier
  backups are unchanged. Rebinding is not a next-key capture operation.
- Only ui010201 text labels in X/A/LB/RB are replaced, with original strings
  captured per widget and restored on release/reset/destruction. Missing/unloaded
  UI is ignored; no layout, color or left Pawn Command UI writes are made.
- Mocks cover three families, disabled/cross-family filtering, custom player/pawn
  actions, motion IDs, input remapping/hold edges/defaults, HUD write/restoration
  and unloading. Verify actual native labels, all three real cart types and motion
  selection in game; Lua mocks cannot confirm animation availability.

## Input capture and preset/HUD corrections (current behavior)

- Binding dropdowns are replaced by next-input capture buttons for keyboard,
  mouse and gamepad. The first HID poll seeds held keys, including the opening
  click; only a later rising edge captures. Zero/None/All never participates.
  Cancel retains the binding; Unbind explicitly sets None. Driving inputs stay
  suppressed while capturing and until held mapped inputs are released afterward.
- Default RB accelerates and LB decelerates, including the corresponding HUD
  labels. A one-time shoulder_binding_rule migrates only the exact previous
  default reversed pair. Other saved mappings remain intact.
- Preset changes reuse current seat records and original FSM-state snapshots.
  They no longer send a priority-0 Wait before priority-1 sitting in the same
  frame; removed party members and actual release still receive normal cleanup.
- HUD text no longer requires Character/GameObject get_Valid on GUI text widgets.
  Message access/writes are guarded instead. Refresh moved from on_frame to
  LateUpdateBehavior, matching the working native-HUD update phase in Journey.
  No transform writes or new native hooks were added to rendering callbacks.
- Tests cover idle/held-key capture, mouse opening-click rejection, gamepad
  capture, gameplay suppression, cancel/unbind/defaults, shoulder migration,
  no Wait on preset changes, GUI widgets without get_Valid, and unload cleanup.
  In-game HUD and preset sitting behavior still need user verification.

## Three-column bindings, localized HUD and independent NPC monitor

- Binding UI is Action / Gamepad / Keyboard with same_line column offsets,
  retaining next-input capture. Mouse mapping controls are removed; L/R always
  accelerate/decelerate, ignoring legacy saved mouse fields. Keyboard None does
  not disable fixed mouse controls. Restore defaults removes obsolete fields.
- HUD paths can resolve to Text itself or a wrapping panel. Nil/empty Message
  is accepted, preserving MessageId for localized label restoration. DEBUG now
  reports each missing path or unreadable text instead of silent 0/4 results.
  In-game effect remains unverified until the next user test.
- NPC Animation Monitor.lua is standalone, read-only and hook-free. Character ID
  963132753 is prefilled; Apply accepts decimal or hex IDs, retries unloaded NPCs
  at 1 Hz, samples action names and Bank/Motion IDs at 4 Hz, and keeps 12 changes.
- run-npc-monitor-tests.ps1 covers parsing, lookup, sampling cap, action/motion
  changes, unavailable/reloaded NPCs, disabled sampling and bounded history.
  Driving mocks additionally cover direct Text paths, localized Message=nil,
  GUID restoration and fixed mouse controls with remapped keyboard/gamepad.

## Native HUD crash isolation

- User reproduced native crashes in a fresh process with an unchanged action-name
  preset; NPC Animation Monitor and Position Diagnostics were disabled. This does
  not establish that a driver-only animation caused the later fresh-process crash.
- Latest normal feedback preceded expanded native HUD Message/MessageId writes.
  NATIVE_HOTBAR_ENABLED is hardcoded OFF for a single-variable isolation build:
  update AND restore skip native GUI access. Driving, actor pose, coordinates,
  preset switching and input mappings are unchanged. No user config is rewritten
  outside the mod's usual saves; motion settings must remain in normal-action mode.
- Takeover phase names are logged with log.info, not a recorder or native hook.
  Tests assert that the disabled HUD path cannot call any native SDK accessor;
  dormant HUD mock coverage explicitly enables it only inside the test process.
- Test the same untouched sitting preset, take control, then drive for 1-2 minutes.
  If stable, HUD access is implicated but not yet proven as the exact bad call;
  if still crashing, use the latest log/dump and last takeover phase to narrow it.

## Write-only HUD experiment (current build)

- User confirmed the HUD-disabled isolation build stable, including direct-motion
  experiments. This implicates HUD access but does not identify the crashing call.
- NATIVE_HOTBAR_ENABLED defaults ON for the approved next test. Each unpaused
  LateUpdateBehavior resolves ui010201/root, the existing four paths, then their
  child objects and calls only set_Message. No get_Message/get_MessageId,
  set_MessageId, original-value snapshots or persistent widget/root cache remain.
  No play-state/color changes or alternate-widget selection are added.
- Release/destruction/reset perform no native HUD restoration. The game must
  refresh its skill text; whether occupied skill slots restore naturally is an
  explicit test question. The DEBUG write-only checkbox can disable further writes.
- Mocks make original-text/GUID getters throw, replace a widget with its old
  object invalid, and check that writes still succeed without a cache. Missing
  child paths are reported. Inactive/disabled/update and release/reset accesses
  are checked separately; simulation cannot validate native crash safety.
- Keep the same stable mod loading set and normal sitting preset. Test take,
  drive, release and take again; observe whether occupied labels change, flicker,
  restore naturally or cause a crash. Preserve the previous stable backup.

## Write-only outcome and restored HUD-disabled state

- User verified occupied skill slots accept labels without overwriting, and names
  restore naturally on release. One cycle was stable; rapid toggling and a separate
  idle-after-single-take test both crashed. Reads/cache/restoration cannot alone
  explain the failure, since they were absent in this experiment.
- Log/dump timestamp 2026-10-05 06:17:39: repeated Exception thrown in
  REMethodDefinition::invoke for via.gui.Text.set_Message, followed by c0000005.
  This directly implicates the setter access path; it does not identify whether
  the receiver type, its lifetime, update phase or another cause made it unsafe.
  FootLockCtrl symbols in the stack alone do not establish an animation bug.
- Preserve that log and minidump under crash-evidence before the next launch.
  Set NATIVE_HOTBAR_ENABLED OFF and remove the runtime enable checkbox. The pure
  write function remains dormant for future inspection, with no SDK GUI calls
  on the disabled path. Driving, slots, actions and settings are unchanged.

## Typed draw-phase HUD experiment

- User confirmed the HUD-disabled build did not crash. That is isolation evidence,
  not completion of the skill-label feature.
- Installed _NickCore UI utility resolves PNL_txt/mtx_00 explicitly rather than
  assuming the first child of PNL_txt is the text. This is a concrete alternative
  path, not proof that the previous receiver was wrong.
- Resolve each explicit node from the GUI component passed to
  on_pre_gui_draw_element, after filtering its GameObject name to ui010201.
  Require get_type_definition():is_a('via.gui.Text') before reading/writing.
  Only set_Message when the current label differs. No LateUpdate HUD writes,
  cached widgets, native release/reset restoration, colors or play-state changes.
- A caught call error latches hotbar_fault until reload; pcall cannot guarantee
  protection from a fatal native crash. Missing/wrong-type nodes are reported.
- Runtime tests cover unchanged-label no-op, wrong-type/missing nodes, widget
  replacement, inactive/no-gameplay writes and error latch. They do not prove
  native stability. Test normal take/drive/release first, then idle and repeated
  ownership changes. If no text appears, report the DEBUG Skill bar status.

### Draw component versus GUIBase correction

- User screenshot reported ui010201/root not available. The callback was reached,
  but incorrectly assumed its REComponent supplied GUIBase.Root.
- Resolve app.GUIBase via getComponent(System.Type) on the callback's owning
  ui010201 GameObject. No scene search or cross-frame GUI component cache.
- Regression fixture now supplies a draw element without Root and a separate
  GUIBase containing Root. Native type checks and draw-phase-only writes remain.

## Current behavior: hide the skill bar, no text replacement

- User reported immediate crash in the GUIBase-corrected text test and requested
  abandoning label changes. All native text, Root and GUIBase access is removed.
- on_pre_gui_draw_element returns false only for GameObject ui010201 while
  state.active. No persistent UI property mutation or object cache. Once release,
  script reset, invalid session or cart destruction clears active, drawing resumes
  without accessing the previous GUI component. Exceptions allow native drawing.
- Regression covers inactive drawing, suppression on takeover, unrelated HUD,
  missing/invalid draw element, repeated ownership changes, reset and broken cart.
- In-game acceptance: restart after the crash; take/drive/release, verify the
  right skill bar disappears and returns, with other HUD and input unchanged.
  Native draw-suppression behavior still requires this runtime check.

## Release-position recovery button

- Record universal position once after release_seats(true), including automatic
  damage release, only for the current valid controlled player. Inactive releases
  do not overwrite the bookmark. No persistent JSON storage or ground queries.
- Button queues recovery for LateUpdateBehavior, after paused menu handling.
  Require inactive driving and the same actor address; set_UniversalPosition,
  PosRotContext.setPos, CharacterController.warp(), resetBaseHeight/resetFallHeight
  and Wait synchronize the released player. No pawn teleportation.
- Reset/loading clears the bookmark. Tests cover one-shot capture, return target,
  physics/context/fall synchronization, different-player/active-driving rejection,
  queue execution and reset cleanup. Scene/universal round-trip uses tolerance.
- Runtime test: release in a known position, move away, press Return and verify
  body/camera return together. Separately test recovery from inside terrain; mocks
  do not establish whether the native engine accepts such a destination.

## NPC playing motion names

- Reference inspected: Emote Dogma.lua resource listing uses getMotionCount,
  getMotionInfoByIndex(System.UInt32, System.UInt32, via.motion.MotionInfo),
  MotionInfo.get_MotionID and get_MotionName. Core set_node requests FSM names;
  super_set_node changes Bank/Motion directly. These are distinct naming levels.
- Standalone monitor now resolves sampled motion IDs using the same documented-in-
  source metadata access pattern. No dependency, hooks, motion-bank loading or
  actor writes. At most 24 metadata entries/sample, round-robin across unresolved
  sampled banks; scalar name cache clears on target change/unload/reset/refresh.
- Tests cover name resolution, progressive scan budget, cache reuse, -1 sentinel,
  missing metadata, explicit refresh, 4 Hz cap, ID validation and history bounds.
  Mock clip names are fixtures, not claims about actual DD2 resource names.
- Runtime acceptance: reload the monitor, observe Nick, allow name resolution,
  capture the named loop while sitting/driving. The actual game may not expose
  names for every bank; report Resolving/Metadata unavailable rather than infer
  SitOnChairActions or claim a clip can be played by another actor.

### Metadata unavailable investigation

- User explicitly requested SitOnChairActions on Nick and observed Bank 0/Motion
  3521, no readable current FSM action, and Motion metadata unavailable. This
  does not prove Motion 3521 is driver-only or has a particular clip name.
- Keep the getter for known layer reads; prefer Character.<Motion>k__BackingField
  for metadata, as Emote Dogma does. Fallback to getter metadata if necessary;
  try explicit getMotionCount(System.UInt32) if shorthand fails. Preserve count
  and info errors in the UI, with source/type, instead of silently hiding them.
- Tests cover distinct getter/backing objects, explicit count calls and failed
  count error display. Name resolution in the actual game is still unconfirmed.

## Debug tool rename and near-cart takeover binding

- Rename NPC Animation Monitor.lua/title to aelinore debug tool.lua/title;
  retain the original ID config and NPC feature. Optional distance monitor works
  independently at 4 Hz, discovers body at 1 Hz, clears invalid references, and
  performs no actor writes. Uses full 3D root/body distance, not visual skeleton.
- near_take binding defaults keyboard E/gamepad RLeft (X). Same next-input UI,
  persistence and restore defaults as existing actions. Inactive rising edge only,
  strict body distance < 2; existing G/RT/menu pathway unchanged. Initial takeover
  consumes simultaneous seat/speed/release edges. Active X/E retains Sit/cycle.
- Tests cover exact 2 rejection, 1.99 entry, E/X, holding edge, remap, independent
  distance toggle, disabled scans and discovery throttling. Runtime verification
  is still required. Remove old autorun filename during deployment to avoid duplicates.

## Shared front detection and UI input correction

- Prior UI-open guard discarded near_take together with other input. Preserve
  only inactive near_take when REFramework is visible; do not bypass game pause
  or key capture. Active near_take cannot reacquire/release. Tests cover UI-open
  entry and active repeat behavior.
- Front direction is normalized horizontal ox position minus body position,
  not motion velocity. Static vehicles work; use body Z for degenerate separation.
  Apply shared configurable forward/side/up offsets. Default forward 1.5 is a
  tuning starting point, not proven geometry bounds. Test ox at +X while body Z
  remains +Z, and strict <2 distance to the resulting point.
- Debug bridge reports the exact driving cart/point distance when available;
  independent mode retains 1 Hz discovery. Separate collapsible Oxcart distance
  and NPC animation sections, with adjustable offsets saved in OxcartFrontProbe.json.

## Compact release menu and player random sitting

- Remove Shift/LT + 1-4/D-pad command logic. Preserve direct mapped actions,
  G/RT takeover, fixed mouse and near-take. Remove top three tutorial lines,
  Driver stood up message, keybind footer tutorials and DEBUG panel. Mouse
  Left/Right are fixed fourth-column labels on Accelerate/Decelerate rows.
- Ignore stored debug toggles: pose lock, sync and fall reset default ON; player
  FSM freeze OFF. Existing regression toggles remain available inside mocks,
  not the user menu. All persisted layouts are included in cycling on load.
- First preset selector Cart type browses families while inactive; active driver
  stays on actual cart family. Active layout always lists matching-family layouts.
  This selector filters presets, rather than reassigning a preset's family.
- Camera offset controls move into Player driver above animation settings.
  Player randomIdle defaults true for new layouts and unspecified old layouts;
  explicit saved false remains false. Player timer resets on arrange, uses the
  same random action set as pawns, and pose lock tracks the chosen idle action.
- Regressions verify compact UI, inactive/active filtering, idle playback/disable,
  live FSM and action protection, Shift+1 removal and migration defaults. In-game
  random-animation compatibility and menu layout still need runtime confirmation.

## Conditional takeover passenger guard; no global G/RT

- Remove hardcoded G/RTrigBottom from input polling. Menu toggle remains the
  explicit entry path. Conditional near_take uses strict front distance <2,
  inactive driving and confirmed false native seat occupancy.
- Read cart.ox.EnemyCtrl.Ch2.<CachedOxcart>k__BackingField.isPlayerSit(). Optional
  OJR_SeatBindings entry with char==player blocks custom OJR seating too; no
  OJR import or changes. Native nil/error is unknown: refuse the key, keep menu.
- Tests cover native seated/standing, OJR custom binding, unavailable controller,
  G/RT no-op while inactive/active, and explicit menu takeover while seated.

## One-shot driver teleport behind the cart

- Replace hold/Wait/side-seat/continuous FSM disabling and release-time driver
  restoration with a single registered-driver relocation on acquire. Require
  valid non-player driver within 12 of body. Missing/distant drivers are skipped.
- Target X/Z is body minus normalized horizontal body-to-ox direction *50;
  preserve driver Y. Set Transform, synchronize universal context/controller,
  reset fall references if available. Never touch driver FSM or action requests.
- No ground/surface query or guarantee about terrain at that target. Driver AI
  remains live. Optional driver relocation failure does not stop player takeover.
- Tests cover stationary sideways orientation, physics sync, zero FSM/action
  mutation, no repeated distant teleport, absent driver and player exclusion.
  In-game driver relocation/AI behavior remains to be verified.

- Driver ID fallback pool: 963132753 (Nick), 2619751808 (ch300680, supplied
  screenshot). Prefer nearby registered driver; otherwise query these IDs and
  select the closest loaded candidate within 12. Tests check new-ID resolution,
  distance rejection and registered-driver preference.
# Driver binding diagnostics and camera distance

Explicit exit-animation trials: user supplied Motion 3513 (`ch00_000_rol_ox_ride02_end_right`) and 3514 (`ch00_000_rol_ox_ride03_end`). Driver diagnostics has two separate test buttons targeting Bank 0 (based on the native driver bank observed in traces; name/ID matching is user-supplied, not independently resolved). Do not take manual control. A button queues one `changeMotion` call for the next unpaused LateUpdate, with no FSM freeze, registration clear, Wait request or teleport. It automatically records 20 seconds and exports a LOG. Test 3513 first on a seated driver; if ineffective reload the save before trying 3514, so the animation trials do not contaminate each other. Observe whether the NPC truly lands/walks freely or just changes its displayed pose. Existing native action/seat event capture remains enabled while a recording runs. Formal takeover behavior is unchanged.

The native exit trace showed 2 -> 1 driver action states, but state 1 persisted through seated waiting, exit motion 3503 and normal walking. Neither state 1 nor clearing the driver registration is proven to be the unbind command. New read-only event capture logs selected-driver `requestActionCore` names/priorities/layers and calls to the selected cart AI's `forceSitDown` / `InterractSeatForce` (raw argument only; not interpreted as a verified Boolean). DriverActionReq/Now enum type/static members are exported when reflection allows. Repeat the natural driving -> exit -> walking baseline without taking manual control to identify an actual exit request. These hooks do not skip or modify native calls.

Camera settings are now stored independently in each seating layout's `camera` table. FOV/distance controls are under `Player driver`, immediately above `Camera offset`; the global Driving camera section was removed. Layout copies preserve independent camera values. Old global camera values seed layouts that lack this table; explicit per-layout values take precedence. Switching layouts applies the active values, while selecting a disabled override restores the captured game baseline. Release/pause/photo/reset restoration remains unchanged. Verify two layouts with different FOV/distance values, a layout with overrides OFF, and release after cycling. Driver behavior is unchanged by this update.

Native flow comparison: reload a save, approach a cart with its driver still off the seat, and click `Start native driver recording` in Driver diagnostics. Use the three `Mark:` buttons for not seated / seated / cart driving. Do not take manual control during this baseline run. Stop after driving a short distance. Read-only capture samples at 4 Hz for up to 10 minutes and includes native AI driver action requests/current action, force-seat flags, scalar decision fields, root/controller/context positions and layer-0 motion IDs. No pose/FSM/registration/position writes are performed by the recorder. UI shows only the latest 24 samples; all bounded samples are exported. Stop, timeout, unload and script reset automatically save JSON-formatted `reframework/data/AelinoreDriverDebug_<timestamp>_<sequence>.log`. Five-second takeover recording also saves automatically. The speculative AI reset change remains uninstalled; the previous clrDriver/Wait behavior is unchanged.

After the first `clrDriver + Wait` test still pulled the driver back, diagnostics were expanded to record the actual force-seat flag, current driver ID/reference and nested `OxcartAI` / `OxcartNPC` method/field metadata. The reader invokes only the specifically named zero-argument status getters, never candidate exit methods. After five seconds click `Save driver report` to export scalar data to `reframework/data/AelinoreDriverDebug.json`; no managed objects are serialized. Driver binding references are discarded when recording ends.

Enable `aelinore debug tool > Driver diagnostics > Record driver on takeover (5 seconds)` before taking control while the native driver is seated. Capture the result, before/immediate/follow-up position rows, and `Candidate native methods` list. The diagnostic reader itself does not invoke candidate exit/seat methods; the controller now attempts the guarded driver-exit sequence described below. Candidate metadata includes parameter count and return type.

`Let me drive oxcart > Driving camera > Override camera distance` adjusts native `app.CameraManager._DistanceOffset` (0–10; game-option units, not metres). Default value 1, override OFF until enabled. User confirmed this distance implementation works in game. `Override FOV` is an independent optional control (20–120 degrees, default OFF); high values can produce the user-observed black circular border. Release, disabling an option, pausing/photo mode, and script reset restore its captured baseline. A manager/camera replacement suspends that override until the next takeover. Verify the combined options and restoration in game.

Driver exit test build: when the selected nearby NPC matches the cart's registered driver and reflected `clrDriver` has zero parameters, call `clrDriver()`, request `Wait` once, then teleport two behavior-frame counters later. Driver FSM remains running. No force-seat/quest flag changes or repeated position pinning. Incompatible interfaces are skipped and reported by Driver diagnostics. Clearing the driver registration is intentional and is not reversed on release. Record the same seated-driver scenario again: successful native unbinding must be confirmed by the absence of position pullback after the delayed teleport, not merely by a successful call.

API discovery reference: [xyzkljl1 CameraDistance source](https://github.com/xyzkljl1/MyDD2Mod/blob/master/CameraDistance/reframework/autorun/CameraDistance.lua). Only the native field identity was used; this mod's scoped snapshot/restore implementation is independent.
