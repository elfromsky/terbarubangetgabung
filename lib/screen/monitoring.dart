import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/bloc/monitoring/monitoring_state.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data.dart';
import 'package:esh/features/monitoring/domain/entities/mcb_data_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_collection.dart';
import 'package:esh/features/monitoring/domain/entities/room_device_state.dart';
import 'package:esh/features/monitoring/domain/entities/sensor_data.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';
import 'package:esh/features/monitoring/presentation/mappers/device_control_view_mapper.dart';
import 'package:esh/features/monitoring/presentation/models/device_control_view_state.dart';
import 'package:esh/models/device_config.dart';
import 'package:esh/widgets/appbar.dart';
import 'package:esh/widgets/selector_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class MonitoringPage extends StatelessWidget {
  final EstimateEnergyCostUseCase estimateEnergyCost;
  final EstimateEmissionUseCase estimateEmission;

  const MonitoringPage({
    super.key,
    required this.estimateEnergyCost,
    required this.estimateEmission,
  });

  @override
  Widget build(BuildContext context) {
    return MonitoringView(
      estimateEnergyCost: estimateEnergyCost,
      estimateEmission: estimateEmission,
    );
  }
}

class MonitoringView extends StatefulWidget {
  final EstimateEnergyCostUseCase estimateEnergyCost;
  final EstimateEmissionUseCase estimateEmission;

  const MonitoringView({
    super.key,
    required this.estimateEnergyCost,
    required this.estimateEmission,
  });

  @override
  State<MonitoringView> createState() => _MonitoringViewState();
}

class _MonitoringViewState extends State<MonitoringView> {
  EstimateEnergyCostUseCase get estimateEnergyCost => widget.estimateEnergyCost;
  EstimateEmissionUseCase get estimateEmission => widget.estimateEmission;
  String _selectedCategory = 'Listrik';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: _mainBg(),
        child: Column(
          children: [
            Appbar(),
            PageSelector(
              onMonitorDropdownChanged: (value) {
                setState(() => _selectedCategory = value);
              },
            ),
            SizedBox(height: 10),
            Expanded(
              child: BlocBuilder<MonitoringBloc, MonitoringState>(
                builder: (context, state) {
                  if (state is MonitoringLoading) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }

                  if (state is MonitoringError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error: ${state.message}',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              context.read<MonitoringBloc>().add(
                                StartMonitoring(),
                              );
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (state is MonitoringLoaded) {
                    final totalEstimatedCost = estimateEnergyCost(
                      energyKwh: state.mcbData.totalEnergy,
                    );
                    final totalEstimatedEmissions = estimateEmission(
                      energyKwh: state.mcbData.totalEnergy,
                    );
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildConnectionStatus(state.isConnected),
                          const SizedBox(height: 16),

                          if (_selectedCategory == 'Listrik') ...[
                            _buildMcbGauges(context, state.mcbData),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: _cardStyle(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Data Sistem',
                                    style: _textStyle(bold: true, size: 18),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: _buildMetricCard(
                                          'Est. Cost',
                                          'Rp ${totalEstimatedCost.toStringAsFixed(0)}',
                                          '',
                                          Colors.amber,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _buildMetricCard(
                                          'Est. Emission',
                                          '${totalEstimatedEmissions.toStringAsFixed(2)} kg CO₂',
                                          '',
                                          Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ] else if (_selectedCategory ==
                              'Suhu & Kelembapan') ...[
                            _buildSensorSection(state.mcbData.sensorData),
                          ] else ...[
                            _buildElektronikSection(
                              state.deviceData,
                              state.pendingDevices,
                              state.commandErrors,
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return const Center(
                    child: Text(
                      'Initializing...',
                      style: TextStyle(color: Colors.white),
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

  Widget _buildMetricCard(
    String title,
    String value,
    String unit,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        children: [
          Text(title, style: _textStyle(bold: true, size: 12)),
          const SizedBox(height: 8),
          Text(
            value,
            style: _textStyle(bold: true, size: 14).copyWith(color: color),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(unit, style: _textStyle(size: 10).copyWith(color: color)),
          ],
        ],
      ),
    );
  }

  Widget _buildSensorSection(SensorData sensor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardStyle(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sensor DHT', style: _textStyle(bold: true, size: 18)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sensor.connected ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  sensor.connected ? 'Online' : 'Offline',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildGaugeCard(
                      'Suhu',
                      sensor.temperature,
                      '°C',
                      maxValue: 50,
                      color: _getTempColor(sensor.temperature),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildGaugeCard(
                      'Kelembapan',
                      sensor.humidity,
                      '%',
                      maxValue: 100,
                      color: _getHumidColor(sensor.humidity),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Indeks Panas',
                      '${sensor.heatIndex.toStringAsFixed(1)} °C',
                      '',
                      Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard(
                      'Kenyamanan',
                      sensor.comfortLevel,
                      '',
                      _getComfortColor(sensor.comfortLevel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getTempColor(double temp) {
    if (temp < 18) return Colors.blue;
    if (temp > 30) return Colors.red;
    return Colors.green;
  }

  Color _getHumidColor(double hum) {
    if (hum < 30) return Colors.orange;
    if (hum > 70) return Colors.cyan;
    return Colors.green;
  }

  Color _getComfortColor(String level) {
    switch (level) {
      case 'Nyaman':
        return Colors.green;
      case 'Panas':
        return Colors.red;
      case 'Dingin':
        return Colors.blue;
      case 'Kering':
        return Colors.orange;
      case 'Lembap':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }

  Widget _buildElektronikSection(
    RoomDeviceCollection deviceData,
    Set<DeviceAddress> pendingDevices,
    Map<DeviceAddress, String> commandErrors,
  ) {
    return Column(
      children: roomDeviceConfigs.map((roomConfig) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildRoomElectronicCard(
            roomConfig,
            deviceData,
            pendingDevices,
            commandErrors,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRoomElectronicCard(
    RoomDeviceConfig roomConfig,
    RoomDeviceCollection deviceData,
    Set<DeviceAddress> pendingDevices,
    Map<DeviceAddress, String> commandErrors,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardStyle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.meeting_room_rounded,
                color: Colors.amber,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                roomConfig.displayName,
                style: _textStyle(bold: true, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...roomConfig.devices.map((device) {
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
            return DeviceStatusCard(
              name: device.displayName,
              supportsBrightness: device.supportsBrightness,
              viewState: viewState,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus(bool isConnected) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConnected ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isConnected ? Icons.cloud_done : Icons.cloud_off,
            color: isConnected ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isConnected ? 'Connected to ESH System' : 'System Disconnected',
            style: TextStyle(
              color: isConnected ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMcbGauges(BuildContext context, McbDataCollection mcbData) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SizedBox(
                width: 350,
                child: _buildMcbSection(context, 'MCB 1', mcbData.mcb1, 0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMcbSection(
    BuildContext context,
    String title,
    McbData mcbData,
    int mcbIndex,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardStyle(),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _textStyle(bold: true, size: 18)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(mcbData),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getStatusText(mcbData),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildGaugeCard(
                  'Voltage',
                  mcbData.voltage,
                  'V',
                  maxValue: 250,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildGaugeCard(
                  'Current',
                  mcbData.current,
                  'A',
                  maxValue: 20,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildGaugeCard(
                  'Power',
                  mcbData.power,
                  'W',
                  maxValue: 500,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildGaugeCard(
                  'Energy',
                  mcbData.energy,
                  'kWh',
                  maxValue: 1000,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(McbData mcbData) {
    if (!mcbData.connected) return Colors.grey;
    return Colors.green;
  }

  String _getStatusText(McbData mcbData) {
    if (!mcbData.connected) return 'Offline';
    return 'Online';
  }

  Widget _buildGaugeCard(
    String title,
    double value,
    String unit, {
    double maxValue = 100,
    Color color = Colors.cyan,
  }) {
    double percentage = (value / maxValue * 100).clamp(0, 100);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardStyle(),
      child: Column(
        children: [
          Text(title, style: _textStyle(bold: true, size: 12)),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: SfRadialGauge(
              axes: [
                RadialAxis(
                  minimum: 0,
                  maximum: 100,
                  showLabels: false,
                  showTicks: false,
                  axisLineStyle: AxisLineStyle(
                    thickness: 0.2,
                    cornerStyle: CornerStyle.bothCurve,
                    color: Colors.white.withValues(alpha: 0.3),
                    thicknessUnit: GaugeSizeUnit.factor,
                  ),
                  ranges: [
                    GaugeRange(
                      startValue: 0,
                      endValue: percentage,
                      color: color,
                      startWidth: 8,
                      endWidth: 8,
                    ),
                  ],
                  annotations: [
                    GaugeAnnotation(
                      widget: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            value.toStringAsFixed(1),
                            style: _textStyle(bold: true, size: 14),
                          ),
                          Text(unit, style: _textStyle(size: 10)),
                        ],
                      ),
                      angle: 90,
                      positionFactor: 0.5,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _textStyle({bool bold = false, double size = 14}) {
    return TextStyle(
      color: Colors.white,
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
  }

  BoxDecoration _cardStyle() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
    );
  }

  BoxDecoration _mainBg() {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.fromARGB(255, 30, 31, 26),
          Color.fromARGB(255, 249, 176, 4),
        ],
      ),
    );
  }
}

class DeviceStatusCard extends StatelessWidget {
  final String name;
  final bool supportsBrightness;
  final DeviceControlViewState viewState;

  const DeviceStatusCard({
    super.key,
    required this.name,
    required this.viewState,
    this.supportsBrightness = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(viewState);
    final color = _statusColor(viewState.phase);
    final icon = _statusIcon(viewState.phase);
    final brightness = viewState.value?.brightness;

    return Semantics(
      container: true,
      label: '$name, $label',
      value: label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (viewState.phase == DeviceControlPhase.pending)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (viewState.phase == DeviceControlPhase.pending)
                      const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
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
    if (state.phase == DeviceControlPhase.pending) return 'Menunggu konfirmasi';
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
}
