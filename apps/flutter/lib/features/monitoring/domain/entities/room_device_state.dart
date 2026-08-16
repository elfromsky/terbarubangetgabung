class DeviceAddress {
  final String roomKey;
  final String deviceKey;

  const DeviceAddress({required this.roomKey, required this.deviceKey});

  @override
  bool operator ==(Object other) {
    return other is DeviceAddress &&
        other.roomKey == roomKey &&
        other.deviceKey == deviceKey;
  }

  @override
  int get hashCode => Object.hash(roomKey, deviceKey);
}

class RoomDeviceValue {
  final bool isOn;
  final int? brightness;

  const RoomDeviceValue({required this.isOn, this.brightness});

  bool get isDimmable => brightness != null;

  @override
  bool operator ==(Object other) {
    return other is RoomDeviceValue &&
        other.isOn == isOn &&
        other.brightness == brightness;
  }

  @override
  int get hashCode => Object.hash(isOn, brightness);
}
