# Position Diagnostics v2

## v2.1: driver-seat versus safe-seat comparison

Only the recorder changes; the driving script and player synchronization stay
unchanged. Record two independent runs with matching route/settings:

1. Reload scripts. Keep player position sync ON, visual split OFF and Record
   pawns OFF. Use the previous front driver seat. Label `front-seat`, Start,
   follow the same route, Mark event immediately after EACH blackout, then Stop.
2. Change only the player's seat to the proven safe rear position. Label
   `safe-seat`, Start, follow the same route through both former blackout
   locations, then Stop. Do not change freeze/speed/sync choices between runs.

New read-only data: controller ground/wall/ceiling/jump and contact counts,
floor object identity, controller local offset/height/radius, Character ground,
LandingProcessor ground retention/object-ground/slope states and previous
ground position, last terrain ground object/normal/position, FallingStuckStopper
activation/TimerStuck/FrameDetectStuck/base position, FallInfo heights, and
FallPreventerPositionRecorder unsafe flag/safe position. Raw positions retain
unconfirmed coordinate-space labels. Component availability is explicit;
missing fields do not mean false/zero. No collision/ground/stuck setters are
called. The 2 Hz sample rate can still miss sub-frame recovery notifications;
manual event marks identify visible blackouts without adding native hooks.

The v1 recorder interfered with runtime: native hooks, multiple engine-phase snapshots, synchronous ~20 MB exports every 15 seconds, and scene discovery after release. Its non-reproducing runs cannot establish the teleport cause.

v2 installs no SDK hooks or pose observer, samples once every 0.5 seconds after UpdateJointExpression, and exports only AFTER recording stops. The controller bridge no longer searches the scene after release. Collection is read-only, but runtime overhead still needs an A/B check.

## First test: teleport

1. Reload ALL REFramework scripts (or restart the game). Stopping v1 does not remove its registered hooks.
2. Set Scene label to `teleport-driver-seat`, leave Record pawns unchecked, click Start recording before Take control.
3. Disable player visual/root separation, reproduce with the same front driver seat. Click Mark event when teleport/camera shaking occurs.
4. Click Stop and export shortly after the event; also note if FPS changes at release or Stop. Export happens after Stop and may briefly stall then.
5. If teleport still disappears with recording enabled, stop using that run as normal evidence; report the A/B result before repeating a full trip.

## Second test: height

Check Record pawns (height issue) BEFORE starting, label `height`, reproduce flying/height instability, Mark event, Stop and export. This adds the three pawn snapshots; player-only mode is cheaper.

Outputs: `reframework/data/LMD_PositionTrace_<timestamp>_<clock>_<sequence>.json`. One unique file per run, max 10 minutes / 1200 samples. No automatic chunks, no overwriting old v1 logs. Failed export retains data and exposes Retry export; stop/reload exports remaining data when possible. Do not exit the game before export succeeds.

Data includes player/cart/camera scene and universal positions, root skeleton joints, position context, terrain/controller fields and on-cart restorer fields. `*_raw` means coordinate space has NOT been confirmed; do not compare raw fields as if all were universal. Missing values do not imply false/zero. Empty skeleton selection retries every 2 seconds.

The synchronization test also records position_sync, position_sync_status and controller message/error (including release reasons). Cart body is already a Transform. Skeleton selection treats an invalid parent object as no parent, matching the working display-seat implementation; camera lookup falls back through its GameObject. These corrections remain read-only.

At 2 Hz, brief sub-frame corrections can be missed. No diagnostic setter, native hooks, warp calls or controller changes are added. The new recorder must pass runtime reproduction parity before its traces are used to infer a cause.
