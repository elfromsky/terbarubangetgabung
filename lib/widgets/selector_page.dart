import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PageSelector extends StatefulWidget {
  final void Function(String)? onMonitorDropdownChanged;
  final void Function(String)? onHistoryDropdownChanged;
  final void Function(String)? onControlDropdownChanged;

  const PageSelector({
    super.key,
    this.onMonitorDropdownChanged,
    this.onHistoryDropdownChanged,
    this.onControlDropdownChanged,
  });

  @override
  State<PageSelector> createState() => _PageSelectorState();
}

class _PageSelectorState extends State<PageSelector> {
  // --- Monitor dropdown state ---
  String _selectedMonitor = 'Listrik';
  bool _isMonitorDropdownOpen = false;

  // --- History dropdown state ---
  String _selectedHistory = 'Listrik';
  bool _isHistoryDropdownOpen = false;

  // --- Control dropdown state ---
  String _selectedControl = 'Teras';
  bool _isControlDropdownOpen = false;

  final List<String> _monitorOptions = [
    'Listrik',
    'Suhu & Kelembapan',
    'Alat Elektronik',
  ];

  final List<String> _historyOptions = ['Listrik', 'Suhu', 'Biaya & Emisi'];

  final List<String> _controlOptions = [
    'Teras',
    'Lorong',
    'Kamar 1',
    'Kamar 2',
    'Dapur',
  ];

  String _getCurrentRoute(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/history')) return '/history';
    if (location.startsWith('/control')) return '/control';
    return '/';
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = _getCurrentRoute(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // --- Tab Row: Monitor | History | Control ---
          Row(
            children: [
              Expanded(
                child: _TabButton(
                  label: 'Monitor',
                  isActive: currentRoute == '/',
                  onPressed: () {
                    _isMonitorDropdownOpen = false;
                    context.go('/');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TabButton(
                  label: 'History',
                  isActive: currentRoute == '/history',
                  onPressed: () {
                    _isHistoryDropdownOpen = false;
                    context.go('/history');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TabButton(
                  label: 'Control',
                  isActive: currentRoute == '/control',
                  onPressed: () {
                    _isControlDropdownOpen = false;
                    context.go('/control');
                  },
                ),
              ),
            ],
          ),

          // === Dropdown hanya untuk MONITOR ===
          if (currentRoute == '/') ...[
            const SizedBox(height: 10),
            _buildDropdownButton(
              selected: _selectedMonitor,
              isOpen: _isMonitorDropdownOpen,
              onTap: () => setState(
                () => _isMonitorDropdownOpen = !_isMonitorDropdownOpen,
              ),
            ),
            _buildDropdownMenu(
              isOpen: _isMonitorDropdownOpen,
              options: _monitorOptions,
              selected: _selectedMonitor,
              onSelect: (option) => setState(() {
                _selectedMonitor = option;
                _isMonitorDropdownOpen = false;
                widget.onMonitorDropdownChanged?.call(option);
              }),
              iconFor: _getMonitorIcon,
            ),
          ],

          // === Dropdown hanya untuk HISTORY ===
          if (currentRoute == '/history') ...[
            const SizedBox(height: 10),
            _buildDropdownButton(
              selected: _selectedHistory,
              isOpen: _isHistoryDropdownOpen,
              onTap: () => setState(
                () => _isHistoryDropdownOpen = !_isHistoryDropdownOpen,
              ),
            ),
            _buildDropdownMenu(
              isOpen: _isHistoryDropdownOpen,
              options: _historyOptions,
              selected: _selectedHistory,
              onSelect: (option) => setState(() {
                _selectedHistory = option;
                _isHistoryDropdownOpen = false;
                widget.onHistoryDropdownChanged?.call(option);
              }),
              iconFor: _getHistoryIcon,
            ),
          ],

          // === Dropdown hanya untuk CONTROL ===
          if (currentRoute == '/control') ...[
            const SizedBox(height: 10),
            _buildDropdownButton(
              selected: _selectedControl,
              isOpen: _isControlDropdownOpen,
              onTap: () => setState(
                () => _isControlDropdownOpen = !_isControlDropdownOpen,
              ),
            ),
            _buildDropdownMenu(
              isOpen: _isControlDropdownOpen,
              options: _controlOptions,
              selected: _selectedControl,
              onSelect: (option) => setState(() {
                _selectedControl = option;
                _isControlDropdownOpen = false;
                widget.onControlDropdownChanged?.call(option);
              }),
              iconFor: _getControlIcon,
            ),
          ],
        ],
      ),
    );
  }

  // --- Reusable dropdown trigger button ---
  Widget _buildDropdownButton({
    required String selected,
    required bool isOpen,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                selected,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Reusable animated dropdown menu ---
  Widget _buildDropdownMenu({
    required bool isOpen,
    required List<String> options,
    required String selected,
    required void Function(String) onSelect,
    required IconData Function(String) iconFor,
  }) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: isOpen
          ? Container(
              margin: const EdgeInsets.only(top: 6),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Column(
                children: options.map((option) {
                  final isSelected = selected == option;
                  return InkWell(
                    onTap: () => onSelect(option),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            iconFor(option),
                            color: isSelected ? Colors.amber : Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              option,
                              style: TextStyle(
                                color: isSelected ? Colors.amber : Colors.white,
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_rounded,
                              color: Colors.amber,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  IconData _getMonitorIcon(String option) {
    switch (option) {
      case 'Listrik':
        return Icons.electric_bolt_rounded;
      case 'Suhu & Kelembapan':
        return Icons.thermostat_rounded;
      case 'Alat Elektronik':
        return Icons.devices_rounded;
      default:
        return Icons.circle;
    }
  }

  IconData _getHistoryIcon(String option) {
    switch (option) {
      case 'Listrik':
        return Icons.electric_bolt_rounded;
      case 'Suhu':
        return Icons.thermostat_rounded;
      case 'Biaya & Emisi':
        return Icons.paid_rounded;
      default:
        return Icons.circle;
    }
  }

  IconData _getControlIcon(String option) {
    switch (option) {
      case 'Teras':
        return Icons.deck_rounded;
      case 'Lorong':
        return Icons.view_column_rounded;
      case 'Kamar 1':
        return Icons.bed_rounded;
      case 'Kamar 2':
        return Icons.bed_rounded;
      case 'Dapur':
        return Icons.kitchen_rounded;
      default:
        return Icons.meeting_room_rounded;
    }
  }
}

// --- Tab Button Widget ---
class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.red : Colors.white.withValues(alpha: 0.2),
            width: isActive ? 2.0 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? Colors.red : Colors.white,
              fontSize: 15,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
