import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/presentation/mappers/device_control_view_mapper.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const address = DeviceAddress(roomKey: 'teras', deviceKey: 'lampu');

  test('missing value maps to unknown and disabled controls', () {
    final result = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty(),
      address: address,
      isPending: false,
      errorMessage: null,
    );

    expect(result.phase, DeviceControlPhase.unknown);
    expect(result.value, isNull);
    expect(result.controlsEnabled, isFalse);
  });

  test('known off and on values map to distinct phases', () {
    final off = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty().set(
        address,
        const RoomDeviceValue(isOn: false),
      ),
      address: address,
      isPending: false,
      errorMessage: null,
    );
    final on = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty().set(
        address,
        const RoomDeviceValue(isOn: true),
      ),
      address: address,
      isPending: false,
      errorMessage: null,
    );

    expect(off.phase, DeviceControlPhase.off);
    expect(off.controlsEnabled, isTrue);
    expect(on.phase, DeviceControlPhase.on);
    expect(on.controlsEnabled, isTrue);
  });

  test('pending takes priority over known value and disables controls', () {
    final result = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty().set(
        address,
        const RoomDeviceValue(isOn: true),
      ),
      address: address,
      isPending: true,
      errorMessage: null,
    );

    expect(result.phase, DeviceControlPhase.pending);
    expect(result.value?.isOn, isTrue);
    expect(result.controlsEnabled, isFalse);
  });

  test('pending disables controls even when error phase wins', () {
    final result = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty().set(
        address,
        const RoomDeviceValue(isOn: true),
      ),
      address: address,
      isPending: true,
      errorMessage: 'Perintah gagal dikirim',
    );

    expect(result.phase, DeviceControlPhase.failed);
    expect(result.isPending, isTrue);
    expect(result.controlsEnabled, isFalse);
  });

  test('failed takes priority and enables only when value is known', () {
    final known = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty().set(
        address,
        const RoomDeviceValue(isOn: false),
      ),
      address: address,
      isPending: false,
      errorMessage: 'Perintah gagal dikirim',
    );
    final unknown = mapDeviceControlViewState(
      visibleDevices: RoomDeviceCollection.empty(),
      address: address,
      isPending: false,
      errorMessage: 'Perintah tidak dikonfirmasi perangkat',
    );

    expect(known.phase, DeviceControlPhase.failed);
    expect(known.value?.isOn, isFalse);
    expect(known.errorMessage, 'Perintah gagal dikirim');
    expect(known.controlsEnabled, isTrue);
    expect(unknown.phase, DeviceControlPhase.failed);
    expect(unknown.value, isNull);
    expect(unknown.controlsEnabled, isFalse);
  });
}
