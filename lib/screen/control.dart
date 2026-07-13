import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:esh/widgets/appbar.dart';
import 'package:esh/widgets/selector_page.dart';
import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/bloc/monitoring/monitoring_state.dart';
import 'package:esh/models/device_config.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  String _selectedRoom = roomDeviceConfigs.first.displayName;

  RoomDeviceConfig? get _roomConfig {
    for (final rc in roomDeviceConfigs) {
      if (rc.displayName == _selectedRoom) return rc;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final roomConfig = _roomConfig;
    final devices = roomConfig?.devices ?? [];

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.fromARGB(255, 30, 31, 26),
              Color.fromARGB(255, 249, 176, 4),
            ],
          ),
        ),
        child: Column(
          children: [
            const Appbar(),
            PageSelector(
              onControlDropdownChanged: (value) {
                setState(() => _selectedRoom = value);
              },
            ),
            Expanded(
              child: BlocBuilder<MonitoringBloc, MonitoringState>(
                builder: (context, state) {
                  if (state is MonitoringLoading ||
                      state is MonitoringInitial) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  if (state is MonitoringError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(
                            state.message,
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => context.read<MonitoringBloc>().add(
                              StartMonitoring(),
                            ),
                            child: const Text('Coba lagi'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (state is! MonitoringLoaded) {
                    return const SizedBox.shrink();
                  }
                  if (state.deviceData['rooms'] is! Map) {
                    return const Center(
                      child: Text(
                        'Menunggu status perangkat...',
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        if (!state.isConnected)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            color: Colors.red.withValues(alpha: 0.2),
                            child: const Text(
                              'Firebase terputus. Status dapat tidak terbaru.',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        if (roomConfig != null)
                          _buildRoomControlCard(
                            roomConfig,
                            devices,
                            state.deviceData,
                            state.pendingDevices,
                            state.commandErrors,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  dynamic _getDeviceNode(
    Map<String, dynamic> dbData,
    String roomKey,
    String deviceKey,
  ) {
    return dbData['rooms']?[roomKey]?[deviceKey];
  }

  bool _getDeviceState(
    Map<String, dynamic> dbData,
    String roomKey,
    String deviceKey,
  ) {
    final node = _getDeviceNode(dbData, roomKey, deviceKey);
    if (node is bool) return node;
    if (node is Map) return node['state'] == true;
    return false;
  }

  int _getDeviceBrightness(
    Map<String, dynamic> dbData,
    String roomKey,
    String deviceKey,
  ) {
    final node = _getDeviceNode(dbData, roomKey, deviceKey);
    if (node is Map && node['brightness'] is num) {
      return (node['brightness'] as num).toInt().clamp(0, 100);
    }
    return 0;
  }

  Widget _buildRoomControlCard(
    RoomDeviceConfig roomConfig,
    List<DeviceConfig> devices,
    Map<String, dynamic> dbData,
    Set<String> pendingDevices,
    Map<String, String> commandErrors,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardStyle(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Status Hardware ${roomConfig.displayName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...devices.map((device) {
                final isOn = _getDeviceState(
                  dbData,
                  roomConfig.roomKey,
                  device.deviceKey,
                );
                final brightness = _getDeviceBrightness(
                  dbData,
                  roomConfig.roomKey,
                  device.deviceKey,
                );
                return _buildStatusItem(
                  device.displayName,
                  device.supportsBrightness,
                  isOn,
                  brightness,
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardStyle(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: Colors.amber, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Panel Kontrol ${roomConfig.displayName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...devices.map(
                (device) => _ControlActionWidget(
                  roomName: roomConfig.displayName,
                  roomKey: roomConfig.roomKey,
                  name: device.displayName,
                  deviceKey: device.deviceKey,
                  supportsBrightness: device.supportsBrightness,
                  firebaseBrightness: _getDeviceBrightness(
                    dbData,
                    roomConfig.roomKey,
                    device.deviceKey,
                  ),
                  firebaseState: _getDeviceState(
                    dbData,
                    roomConfig.roomKey,
                    device.deviceKey,
                  ),
                  isPending: pendingDevices.contains(
                    '${roomConfig.roomKey}/${device.deviceKey}',
                  ),
                  commandError:
                      commandErrors['${roomConfig.roomKey}/${device.deviceKey}'],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusItem(
    String name,
    bool supportsBrightness,
    bool isOn,
    int brightness,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  supportsBrightness
                      ? Icons.lightbulb_outline
                      : Icons.power_rounded,
                  color: isOn ? Colors.amber : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              if (supportsBrightness) ...[
                Text(
                  isOn ? '$brightness%' : '-',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(width: 12),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isOn
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOn ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Text(
                  isOn ? 'Nyala' : 'Mati',
                  style: TextStyle(
                    color: isOn ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardStyle() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
    );
  }
}

class _ControlActionWidget extends StatefulWidget {
  final String roomName;
  final String roomKey;
  final String name;
  final String deviceKey;
  final bool supportsBrightness;
  final int firebaseBrightness;
  final bool firebaseState;
  final bool isPending;
  final String? commandError;

  const _ControlActionWidget({
    required this.roomName,
    required this.roomKey,
    required this.name,
    required this.deviceKey,
    required this.supportsBrightness,
    required this.firebaseBrightness,
    required this.firebaseState,
    required this.isPending,
    required this.commandError,
  });

  @override
  State<_ControlActionWidget> createState() => _ControlActionWidgetState();
}

class _ControlActionWidgetState extends State<_ControlActionWidget> {
  double _localBrightness = 0.0;
  bool _isEditing = false;
  bool _isOn = false;

  @override
  void initState() {
    super.initState();
    _localBrightness = widget.firebaseBrightness.toDouble();
    _isOn = widget.firebaseState;
    if (_localBrightness == 0 && _isOn) {
      _localBrightness = 100;
    }
  }

  @override
  void didUpdateWidget(covariant _ControlActionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && !widget.isPending) {
      _localBrightness = widget.firebaseBrightness.toDouble();
      _isOn = widget.firebaseState;
      if (_localBrightness == 0 && _isOn) {
        _localBrightness = 100;
      }
    }
  }

  void _sendControlCommand(bool turnOn, double brightnessVal) {
    if (widget.isPending) return;

    context.read<MonitoringBloc>().add(
      ControlRoomDevice(
        roomName: widget.roomName,
        roomKey: widget.roomKey,
        deviceName: widget.name,
        deviceKey: widget.deviceKey,
        isOn: turnOn,
        brightness: brightnessVal,
        supportsBrightness: widget.supportsBrightness,
      ),
    );
    setState(() {
      _isEditing = false;
      _isOn = turnOn;
    });
  }

  void _confirmToggle(bool isTurningOn) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Konfirmasi'),
          content: Text(
            'Anda yakin ingin ${isTurningOn ? 'menyalakan' : 'mematikan'} ${widget.name}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _sendControlCommand(isTurningOn, isTurningOn ? 100 : 0);
              },
              child: const Text('Ya'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (widget.isPending)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (widget.commandError != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.commandError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),

          if (widget.supportsBrightness)
            _buildBrightnessControl()
          else
            _buildSimpleToggle(),
        ],
      ),
    );
  }

  Widget _buildBrightnessControl() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.isPending
                    ? null
                    : () {
                        setState(() {
                          _isOn = true;
                          if (_localBrightness == 0) {
                            _localBrightness = 100;
                          }
                        });
                      },
                icon: Icon(
                  Icons.power,
                  color: _isOn ? Colors.white : Colors.white54,
                  size: 16,
                ),
                label: Text(
                  'Nyala',
                  style: TextStyle(
                    color: _isOn ? Colors.white : Colors.white54,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isOn
                      ? Colors.green
                      : Colors.grey.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.isPending
                    ? null
                    : () {
                        setState(() {
                          _isOn = false;
                          _localBrightness = 0;
                        });
                      },
                icon: Icon(
                  Icons.power_off,
                  color: !_isOn ? Colors.white : Colors.white54,
                  size: 16,
                ),
                label: Text(
                  'Mati',
                  style: TextStyle(
                    color: !_isOn ? Colors.white : Colors.white54,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: !_isOn
                      ? Colors.red
                      : Colors.grey.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.brightness_low,
              color: _isOn ? Colors.white54 : Colors.white24,
              size: 16,
            ),
            Expanded(
              child: Slider(
                value: _localBrightness,
                min: 0,
                max: 100,
                divisions: 100,
                label: _localBrightness.toInt().toString(),
                activeColor: _isOn ? Colors.amber : Colors.grey,
                inactiveColor: Colors.white24,
                onChangeStart: _isOn
                    ? (value) {
                        setState(() => _isEditing = true);
                      }
                    : null,
                onChanged: _isOn
                    ? (value) {
                        setState(() {
                          _localBrightness = value;
                        });
                      }
                    : null,
              ),
            ),
            Icon(
              Icons.brightness_high,
              color: _isOn ? Colors.amber : Colors.grey,
              size: 16,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 32,
              child: Text(
                '${_localBrightness.toInt()}%',
                style: TextStyle(
                  color: _isOn ? Colors.amber : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: widget.isPending
                  ? null
                  : () {
                      _sendControlCommand(_isOn, _localBrightness);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 36),
              ),
              child: const Text(
                'Send',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSimpleToggle() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.isPending ? null : () => _confirmToggle(true),
            icon: const Icon(Icons.power, color: Colors.white, size: 16),
            label: const Text(
              'Nyalakan',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.isPending ? null : () => _confirmToggle(false),
            icon: const Icon(Icons.power_off, color: Colors.white, size: 16),
            label: const Text('Matikan', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
