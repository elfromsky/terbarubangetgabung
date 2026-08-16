# PRD FR-16 Resolution: Brightness on OFF

## Requirement as Written

PRD FR-16: *Ketika lampu OFF, brightness harus bernilai 0%.*

## Hardware Conflict

The ESH hardware shares one dimmer channel (CH1) between **Lampu Kamar 1** and **Lampu Kamar 2**. If an OFF lamp were forced to brightness `0`, the shared channel would be disabled, which would also extinguish the sibling lamp that may still be ON. This makes a strict 0% brightness-on-OFF rule impossible for the shared CH1 pair without breaking independent relay control.

## Decision

1. **Shared CH1 (Kamar 1 & Kamar 2):** Retain the active channel brightness for an OFF lamp when its sibling is ON. When both lamps are OFF, the channel is unused and brightness is reported as `0`. This preserves independent ON/OFF control while still honoring FR-16 for the "both OFF" state.

2. **Dedicated CH2 (Dapur Lampu):** OFF is reported as brightness `0` because no other device uses CH2.

3. **State-only devices / non-dimmable relays:** Brightness is always `0`.

## Code Changes

- `slavegabung/src/room_device_routing.cpp`
  - `applyDeviceCommand`: OFF on a dedicated channel sets brightness `0`; OFF on a shared channel with an active sibling retains the channel brightness.
  - `buildPeriodicStateForDevice`: reports `0` when the shared channel has no active relay, otherwise reports the retained brightness.

## PRD Revision Needed

Update FR-16 wording to:

> *Ketika lampu OFF, brightness bernilai 0%, kecuali untuk Lampu Kamar 1 dan Lampu Kamar 2 yang berbagi channel dimmer CH1; pada pasangan tersebut, brightness tetap mengikuti nilai channel aktif ketika salah satu lampu masih ON agar lampu yang ON tidak ikut padam.*

## Tests

- Existing Flutter BLoC tests confirm shared-bedroom brightness is kept atomic across paired commands.
- Firmware behavior for dedicated vs. shared channels must be validated with live hardware before final acceptance.
