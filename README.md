# Let me drive oxcart

Independent manual-driving prototype for Dragon's Dogma 2 / REFramework.

Approach within 8 units of an oxcart and press **G / RT (R2)** to take control.
Use **A/D / left stick** to steer. Click **left/right mouse** or **RB/LB (R1/L1)**
to accelerate/decelerate one stage: **Wait → Walk → Run → Dash**.
**W/S** are keyboard acceleration fallbacks. **E / X (Square)** cycles driving
seat layouts; **F / B (Circle)** releases the driver and passengers.

The REFramework menu edits steering sensitivity and separate driver/passenger
layouts. Coordinates use the cart's MoveFloor space; initial positions are
starting values and require in-game adjustment for different cart models.
On first takeover with a driver present, the player's initial seat position is
captured from the native driver's current position. Subsequent edits are preserved.
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

The native driver's FSM is paused and the driver is moved beside the cart.
On release the driver's original cart-relative position and original FSM enabled
state are restored. This does NOT replace the game's registered driver ID and
does NOT guarantee that its navigation will resume. No travel ticket or route
data is changed. The mod intercepts only the four locomotion requests, not death
or break actions. Player/cart changes, destruction and script reset release control.

Incoming damage to the current player, party and cart is multiplied by **0.01**
only during manual control. This is not immunity to statuses, physics or scripted
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
