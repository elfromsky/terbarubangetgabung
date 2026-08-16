# Shared dimmer semantics

Two logical bedroom lamps share a single physical dimmer channel on the Slave.
This document captures the arbitration behavior that already exists in the
code; it is not a proposal to change it.

## Which devices share hardware

The Slave's `kamar_1/lampu` and `kamar_2/lampu` routes share dimmer channel
**CH1**. In the firmware these are identified by:

- Master side (`firebase_command_router.cpp` `usesSharedBedroomDimmer`):
  Slave-owned, `dimmable`, `deviceKey == "lampu"`, and
  `roomKey` in `{kamar_1, kamar_2}`.
- Slave side (`room_device_routing.cpp`): both routes map to the same dimmer
  channel (channel `1`).

`kamar_1/lampu` and `kamar_2/lampu` each still have their **own** relay, so
their ON/OFF state remains independent. Only the **brightness** is shared.

## What remains independent

- Each lamp's relay ON/OFF state is independent.
- The non-shared dimmer `dapur/lampu` (channel `2`) is independent.
- All relay/switch devices are independent.

## Brightness arbitration (Master)

Because only one brightness value can drive CH1, the Master arbitrates:

- The newest accepted command (highest `issued_at`, tie-broken by
  lexicographically larger `request_id`) owns the shared brightness
  (`sharedBedroomDesiredBrightness`).
- When `kamar_1/lampu` or `kamar_2/lampu` is a shared dimmer route, its
  reported/desired brightness is that shared value, not its per-route value.
- An older command delivered late cannot overwrite the shared brightness.

## Flutter pairing behavior

When Flutter controls a bedroom lamp (either `kamar_1/lampu` or
`kamar_2/lampu`), it also emits a companion command to the **paired** lamp
(`_pairedBedroomRoomKey` maps `kamar_1 <-> kamar_2`) so that both logical
lamps' desired brightness stay consistent. The relay states are copied from
the latest known state of each lamp.

## Slave hardware behavior

On the Slave, a dimmer ON command normalizes `brightness == 0` to `1` (minimum
dimmable level). When one lamp on CH1 turns OFF while the other is still ON,
CH1 is retained at its current brightness for the still-ON lamp; when the last
CH1 user turns OFF, CH1 is driven to `0`.

## Limitations

- The shared dimmer is a physical hardware constraint, not a protocol
  abstraction. It is surfaced explicitly in this contract so that any future
  change must consciously preserve or replace this arbitration.

> Do not "fix" the shared dimmer during the monorepo migration; it is
> intentional pre-existing behavior.
