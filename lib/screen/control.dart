import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:esh/widgets/appbar.dart';
import 'package:esh/widgets/selector_page.dart';
import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/bloc/monitoring/monitoring_state.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/presentation/mappers/device_control_view_mapper.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';
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

  Widget _buildRoomControlCard(
    RoomDeviceConfig roomConfig,
    List<DeviceConfig> devices,
    RoomDeviceCollection deviceData,
    Set<DeviceAddress> pendingDevices,
    Map<DeviceAddress, String> commandErrors,
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
                final address = DeviceAddress(
                  roomKey: roomConfig.roomKey,
                  deviceKey: device.deviceKey,
                );
                final viewState = mapDeviceControlViewState(
                  visibleDevices: deviceData,
                  address: address,
                  isPending: pendingDevices.contains(address),
                  errorMessage: commandErrors[address],
                );
                return _buildStatusItem(
                  device.displayName,
                  device.supportsBrightness,
                  viewState,
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
              ...devices.map((device) {
                final address = DeviceAddress(
                  roomKey: roomConfig.roomKey,
                  deviceKey: device.deviceKey,
                );
                final viewState = mapDeviceControlViewState(
                  visibleDevices: deviceData,
                  address: address,
                  isPending: pendingDevices.contains(address),
                  errorMessage: commandErrors[address],
                );
                return _ControlActionWidget(
                  roomName: roomConfig.displayName,
                  roomKey: roomConfig.roomKey,
                  name: device.displayName,
                  deviceKey: device.deviceKey,
                  supportsBrightness: device.supportsBrightness,
                  viewState: viewState,
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusItem(
    String name,
    bool supportsBrightness,
    DeviceControlViewState viewState,
  ) {
    final label = _statusLabel(viewState);
    final color = _statusColor(viewState.phase);
    final brightness = viewState.value?.brightness;

    return Semantics(
      container: true,
      label: '$name, $label',
      value: label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Row(
          children: [
            Icon(_statusIcon(viewState.phase), color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            if (supportsBrightness && brightness != null) ...[
              Text(
                '$brightness%',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color, width: 1),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(DeviceControlViewState state) {
    if (state.phase == DeviceControlPhase.unknown) {
      return 'Status belum tersedia';
    }
    if (state.phase == DeviceControlPhase.pending) {
      return 'Menunggu konfirmasi';
    }
    if (state.phase == DeviceControlPhase.failed) {
      return state.errorMessage ?? 'Perintah gagal';
    }
    return state.phase == DeviceControlPhase.on ? 'Nyala' : 'Mati';
  }

  Color _statusColor(DeviceControlPhase phase) {
    if (phase == DeviceControlPhase.on) return Colors.green;
    if (phase == DeviceControlPhase.off) return Colors.red;
    if (phase == DeviceControlPhase.pending) return Colors.amber;
    if (phase == DeviceControlPhase.failed) return Colors.redAccent;
    return Colors.grey;
  }

  IconData _statusIcon(DeviceControlPhase phase) {
    if (phase == DeviceControlPhase.on) return Icons.power;
    if (phase == DeviceControlPhase.off) return Icons.power_off;
    if (phase == DeviceControlPhase.pending) return Icons.sync;
    if (phase == DeviceControlPhase.failed) return Icons.error_outline;
    return Icons.help_outline;
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
  final DeviceControlViewState viewState;

  const _ControlActionWidget({
    required this.roomName,
    required this.roomKey,
    required this.name,
    required this.deviceKey,
    required this.supportsBrightness,
    required this.viewState,
  });

  @override
  State<_ControlActionWidget> createState() => _ControlActionWidgetState();
}

class _ControlActionWidgetState extends State<_ControlActionWidget> {
  double _localBrightness = 0.0;
  bool _isEditing = false;
  bool _isOn = false;

  void _syncFromViewState() {
    final value = widget.viewState.value;
    _localBrightness = value?.brightness?.toDouble() ?? 0;
    _isOn = value?.isOn ?? false;
  }

  @override
  void initState() {
    super.initState();
    _syncFromViewState();
  }

  @override
  void didUpdateWidget(covariant _ControlActionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing &&
        !widget.viewState.isPending &&
        widget.viewState.phase != DeviceControlPhase.pending) {
      _syncFromViewState();
    }
  }

  bool get _canInteract => widget.viewState.controlsEnabled;

  void _sendControlCommand(bool turnOn, double brightnessVal) {
    if (!_canInteract) return;

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
              if (widget.viewState.phase == DeviceControlPhase.pending)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (widget.viewState.errorMessage != null) ...[
            const SizedBox(height: 4),
            Semantics(
              liveRegion: true,
              child: Text(
                widget.viewState.errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
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
                onPressed: _canInteract
                    ? () {
                        setState(() {
                          _isOn = true;
                          if (_localBrightness == 0) {
                            _localBrightness = 100;
                          }
                        });
                      }
                    : null,
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
                onPressed: _canInteract
                    ? () {
                        setState(() {
                          _isOn = false;
                          _localBrightness = 0;
                        });
                      }
                    : null,
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
                onChangeStart: _canInteract && _isOn
                    ? (value) {
                        setState(() => _isEditing = true);
                      }
                    : null,
                onChanged: _canInteract && _isOn
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
              onPressed: _canInteract
                  ? () {
                      _sendControlCommand(_isOn, _localBrightness);
                    }
                  : null,
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
            onPressed: _canInteract ? () => _confirmToggle(true) : null,
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
            onPressed: _canInteract ? () => _confirmToggle(false) : null,
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
