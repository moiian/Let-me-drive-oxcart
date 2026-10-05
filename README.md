# Let me drive oxcart

Independent manual-driving prototype for Dragon's Dogma 2 / REFramework.

Use the menu Take control button within 8 units of a connected oxcart.
Alternatively press **E / X (Square)** while not seated as a cart passenger and player-to-cart-front-point distance
is strictly below 2. This binding has its own next-input mapping row;
global G/RT controls are removed. While driving, E/X continues to use the
separate Sit/cycle binding and never releases via the near-take row.
The distance target is now a configurable front point, not the bottom body origin.
Front direction follows the horizontal body-to-ox line, even while stationary;
degenerate direction falls back to the body axis. Default offset is 1.5 forward,
0 sideways/up (a calibration starting value, not an automatically measured edge).
Adjust offsets in aelinore debug tool / Oxcart distance; both scripts share the
settings via OxcartFrontProbe.json and a live table. While this driving mod is
loaded, the debug distance uses its exact cart selection and distance function.
Near-take input is allowed with REFramework UI visible, unlike other driving
inputs; game pause/loading and binding capture still block it.
Passenger seating is read from CachedOxcart.isPlayerSit(), independently of
ticket payment. OJR player seat bindings also block near-take when present;
OJR remains optional. Unknown native seat state blocks the conditional key,
but the menu still allows an explicit takeover. Standing passengers use the
conditional key; driving players use their Sit/cycle binding.
Use **A/D / left stick** to steer. Use **W/S** or **RB/LB (R1/L1)**
to accelerate/decelerate one stage: **Wait → Walk → Run → Dash**.
**W/S** are keyboard acceleration fallbacks. **E / X (Square)** cycles driving
seat layouts; **Space / A (Cross)** releases the driver and passengers. These
actions have gamepad and keyboard mapping buttons in a three-column Keybind
settings panel (Action / Gamepad / Keyboard). Mouse driving is disabled. Click a binding,
release held inputs, then press the next key/button.
Cancel keeps the old binding; Unbind disables that device binding. Capture blocks
driving actions and ignores its opening click/held buttons. Restore default driving
keys resets all mappings. Modifier + 1-4/D-pad controls have been removed.
While driving, the entire native right skill bar is hidden.
Release resumes its normal drawing automatically. Text replacement was abandoned
after native crashes: the current implementation only returns false from the
ui010201 pre-draw callback while control is active. It never reads/writes skill
text, changes visibility fields or caches GUI widgets. Other HUD elements retain
their normal drawing. Driving bindings remain active while the skill bar is hidden.

After releasing control, use **Return to last release position** in the mod menu
to recover the player to that instant's location (also recorded on cart damage
release). The bookmark is captured once after body/root alignment, in universal
coordinates; no ground scans or continuous position recording. Return synchronizes
the player transform, position context and controller, and resets fall tracking.
Close a paused game menu to apply a queued return. The bookmark is session-only,
cleared on script reset/loading, and rejected for a different player instance.
It is not a verified safe-ground location: if release already occurred underground,
the bookmark may also be underground.

## aelinore debug tool

aelinore debug tool.lua works without this driving mod. In Script Generated UI,
open aelinore debug tool, enter a Character ID and press Apply NPC ID. Default
963132753 is the Nick ID supplied in the Emote Dogma screenshot; decimal and 0x
hexadecimal IDs are supported. The NPC must be loaded nearby.
It reads current action/FSM node names on layers 0-7 and playing motion names plus
Bank/Motion IDs on layers 0-3 at 4 Hz, retaining the last 12 changes. Motion names
come from this NPC's loaded motion metadata, not guessed ID mappings. Metadata
scans are incremental (24 entries/sample, up to 20000 entries per bank); resolving
a large bank can take time. Refresh motion names clears cached names after bank
changes. Invalid -1 motion IDs display as no active motion.
SitOnChairActions is a high-level request/FSM action, not necessarily a single
clip name. Reading a loop clip cannot prove which request entered it. Missing
metadata is reported explicitly. No hooks or NPC actions, FSM, position, motion
or damage are modified; Emote Dogma is a reference, not a runtime dependency.
Configuration is saved separately in reframework/data/NPCAnimationMonitor.json.
The optional distance monitor is OFF initially and independent of NPC monitoring.
Distance and NPC animation UI are in separate collapsible sections. When the
driving mod is loaded, its live front-point probe is sampled at 4 Hz; standalone
mode uses throttled nearest-body discovery and the same offset geometry.
Standalone mode prefers the cart near the game's cached ox; without one it uses
the nearest body within 50 and the body's Z-axis fallback. It uses the same body
model families as manual takeover, not distance to the ox itself.

The REFramework menu edits steering sensitivity and separate driver/passenger
layouts. Cart models automatically select Normal, Rainproof or Luxury layouts.
Cycling visits layouts of the actual cart type only; inclusion is enabled and
hidden. Cart type is the first preset-menu selector, filtering Active layout
even while not driving. While driving, another cart family cannot be selected.
Missing types get an editable default.
Normal and Rainproof defaults include the supplied measured body, pawn and
root/view positions; Luxury starts with a separate layout that needs testing.
Coordinates use the cart's MoveFloor space.
Takeover uses the selected preset's FIXED player offset from MoveFloor (cart
Transform fallback). Normal driver default is X=0.029, Y=0.920, Z=0.274,
Yaw=178°; Rainproof is X=-0.051, Y=0.920, Z=0.334, Yaw=178°.
Camera offset is saved per layout and edited inside Player driver, before the
animation settings. Player random sitting idles are ON by default, with an
individual checkbox just like pawns. Random idles can replace a custom starting
pose; disable them to keep the chosen animation fixed. Sitting protection,
position synchronization and fall reset remain ON; player FSM freeze stays OFF.
The former DEBUG panel and saved debug overrides are removed from the menu.
Player entry position is not captured; later menu edits persist across takeover
and preset cycling. Old capture-based configs retain their one-time historical
seat migration; subsequent player edits and old layouts are preserved.
Each player/pawn slot supports an action name or direct Bank/Motion IDs. Pawns
can additionally use random sitting idles; the player keeps a fixed selected pose.
FSMs keep running, with external primary actions filtered to protect seated poses.
The legacy DEBUG player FSM freeze is OFF; enabling it previously caused blackouts.
Seats synchronize Transform, CharacterPosRotContext and the physical controller
in LateUpdateBehavior, with fall-reference resets, including Photo Mode positions.
No recurring full Character warp is used. Original FSM states restore on release.
Experimental player visual seat offset belongs to each layout: body coordinates
and root/view offsets are independent, with X/Y/Z offsets from -10 to +10.
Positive Y moves up, positive Z forward. Release aligns the root/view to the body.
When Journey is present, its current cart-specific pawn positions, facing and
actions seed the new layout. Editing pawn coordinates marks a layout customized
so a later takeover does not overwrite it. Both mods retain separate config files.
With Journey disabled, its saved configuration can optionally seed the first
enabled layout for the current cart type; otherwise the standalone defaults apply.
Modifier backup: **Shift / LT (L2)** plus **1 / D-pad Up** accelerates,
**2 / D-pad Left** decelerates, **3 / D-pad Right** cycles seats,
**4 / D-pad Down** releases control. There is no separate switch-preset binding.

## Compatibility

Works independently. With Oxcarts Journey Redux, use its compatibility build
from branch `compatibility/manual-driving`. A versioned, in-memory
`DD2_OxcartControl` ownership handshake suspends Journey's input, automatic
movement, seat constraints and damage rules while this mod owns the cart.
Releasing restores Journey's previous seating layout when it was active.
The original main and experimental/manual-driving branches are preserved.
Do not combine with an older Journey build: both will otherwise control actors.

## Prototype boundaries

Driver diagnostics includes Test native DrivingSeat.freeGetOff (once). Reload
scripts/save first, do not take manual control, and wait for the native driver to
board/drive. The button queues a single LateUpdate call to the cart's DrivingSeat
freeGetOff() after verifying its SitChara matches the selected NPC and the method
is zero-argument Void. Existing visual offsets, frozen FSMs or battle/Wait overrides
reject the test. It injects no teleport, animation request, FSM or battle changes.
Binding/position/motion and optional player/driver coordinate-restorer snapshots
are sampled at 4 Hz for 20 seconds and automatically saved in
reframework/data/AelinoreDriverDebug_*.log. This is an experimental native exit
test, not an automatic takeover behavior change.

The debug tool's Driver combat / FSM section samples actual selected FSM enabled
state, ActionManager FSM enabled state, and driver/player Human battle state at
4 Hz. Freeze driver FSM can be toggled independently; unfreezing restores the
original state. Force-true switches intercept only the selected cart's
isDriverBattleMode/isAnyoneBattleMode Boolean checks, displaying the last natural
result versus the effective return. Overrides skip the getter and return true from
its original function entry; failed/unready entries retry at most once per second,
and changed entries are re-resolved. They do not force a Human combat transition.
Clear or debug-script reset removes overrides and restores held FSM states.
The one-shot physical teleport button moves the selected NPC root 500 units behind
the cart and synchronizes context/controller/fall tracking, without continuous
pinning or FSM changes. Position readback remains available after that NPC leaves
the normal nearby-driver range while the same cart is selected.

On takeover, an unseated native driver within 12 units is physically teleported
50 units behind the cart, with Transform/context/controller sync and fall reset.
A boarding/seated/driving driver is displaced visually to 1000 units above the
cart body's position: only independent skeleton root joints are translated.
Native root, physics, registration and actions remain untouched in this branch.
The same cart's isAnyoneBattleMode is forced true to stop native navigation.
Wait is requested for one second while incoming primary Walk/Run/Dash requests
are suppressed for that ox only. Other actors and non-locomotion requests pass.
FSM freezing is an optional debug switch, default OFF; the production scheme no
longer depends on it. Its original enabled state is preserved when manually frozen.
Phase detection uses current actions, ox-ride motions and AI SitWalk/SitWhip;
SitWait alone does not prove seating. An unreadable phase uses visual displacement.
Neither branch returns the driver on release. Visual offsets remain active after
release with the last visual offset and per-cart battle override. No automatic
restoration option is added. Script reset restores skeletons and original FSM
states and clears battle/Wait rules; unloaded NPCs/carts are
discarded. Missing/distant drivers or unavailable skeletons are skipped.
This does NOT replace the game's registered driver ID and
does NOT guarantee that its navigation will resume. No travel ticket or route
data is changed. The mod intercepts only the four locomotion requests, not death
or break actions. Player/cart changes, destruction and script reset release control.

Seat-bound player/pawns skip damageProc; cart-related incoming damage is multiplied
by **0.01** only during manual control. This is not immunity to statuses or scripted
destruction. Outgoing damage is unchanged. Cart attachment parts still need
in-game verification of receiver objects.

Runtime code is newly organized around driving ownership; no original mod is
bundled or required. Game APIs and prior tested steering behavior inform this
implementation. Keep the old project's credits unchanged.

Configuration: `reframework/data/LetMeDriveOxcart.json`.

Development references: local game-generated `il2cpp_dump.json` for HID,
driver and action signatures; official REFramework
[callbacks](https://cursey.github.io/reframework-book/api/re.html) and
[menu API](https://cursey.github.io/reframework-book/api/imgui.html).
