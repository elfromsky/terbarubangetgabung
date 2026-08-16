class DeviceConfig {
  final String displayName;
  final String deviceKey;
  final bool supportsBrightness;

  const DeviceConfig({
    required this.displayName,
    required this.deviceKey,
    this.supportsBrightness = false,
  });
}

class RoomDeviceConfig {
  final String displayName;
  final String roomKey;
  final List<DeviceConfig> devices;

  const RoomDeviceConfig({
    required this.displayName,
    required this.roomKey,
    required this.devices,
  });
}

const List<RoomDeviceConfig> roomDeviceConfigs = [
  RoomDeviceConfig(
    displayName: 'Teras',
    roomKey: 'teras',
    devices: [
      DeviceConfig(displayName: 'Lampu', deviceKey: 'lampu'),
      DeviceConfig(displayName: 'Sanyo', deviceKey: 'sanyo'),
    ],
  ),
  RoomDeviceConfig(
    displayName: 'Lorong',
    roomKey: 'lorong',
    devices: [
      DeviceConfig(displayName: 'Stop Kontak', deviceKey: 'stop_kontak'),
      DeviceConfig(displayName: 'Blower', deviceKey: 'blower'),
    ],
  ),
  RoomDeviceConfig(
    displayName: 'Kamar 1',
    roomKey: 'kamar_1',
    devices: [
      DeviceConfig(
        displayName: 'Lampu',
        deviceKey: 'lampu',
        supportsBrightness: true,
      ),
      DeviceConfig(displayName: 'Stop Kontak', deviceKey: 'stop_kontak'),
    ],
  ),
  RoomDeviceConfig(
    displayName: 'Kamar 2',
    roomKey: 'kamar_2',
    devices: [
      DeviceConfig(
        displayName: 'Lampu',
        deviceKey: 'lampu',
        supportsBrightness: true,
      ),
      DeviceConfig(displayName: 'Stop Kontak', deviceKey: 'stop_kontak'),
    ],
  ),
  RoomDeviceConfig(
    displayName: 'Dapur',
    roomKey: 'dapur',
    devices: [
      DeviceConfig(
        displayName: 'Lampu',
        deviceKey: 'lampu',
        supportsBrightness: true,
      ),
      DeviceConfig(displayName: 'Blower', deviceKey: 'blower'),
    ],
  ),
];

RoomDeviceConfig? findRoomConfig(String roomKey) {
  final key = roomKey.toLowerCase().replaceAll(' ', '_');
  for (final rc in roomDeviceConfigs) {
    if (rc.roomKey == key) return rc;
  }
  return null;
}

DeviceConfig? findDeviceConfig(String roomKey, String deviceKey) {
  final rc = findRoomConfig(roomKey);
  if (rc == null) return null;
  final dk = deviceKey.toLowerCase().replaceAll(' ', '_');
  for (final d in rc.devices) {
    if (d.deviceKey == dk) return d;
  }
  return null;
}

bool supportsBrightness(String roomName, String deviceName) {
  final dc = findDeviceConfig(roomName, deviceName);
  return dc?.supportsBrightness ?? false;
}

String normalizeKey(String name) {
  return name.toLowerCase().replaceAll(' ', '_');
}
