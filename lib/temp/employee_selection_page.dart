import 'package:flutter/material.dart';

import 'attendance_employee.dart';
import 'attendance_history_client.dart';
import 'attendance_page.dart';
import 'attendance_profile.dart';
import 'attendance_profile_client.dart';
import 'attendance_store.dart';
import 'attendance_sync_service.dart';

class EmployeeSelectionPage extends StatefulWidget {
  const EmployeeSelectionPage({
    super.key,
    required this.profileClient,
    required this.store,
    required this.syncService,
    this.historyClient,
    this.employees = attendanceEmployees,
    this.faceVerifier,
    this.clock,
    this.initialEmployeeId,
    this.autoContinue = false,
    this.onEmployeeConfirmed,
  });

  final AttendanceProfileClient profileClient;
  final AttendanceHistoryClient? historyClient;
  final AttendanceStore store;
  final AttendanceSyncService syncService;
  final List<AttendanceEmployee> employees;
  final AttendanceFaceVerifier? faceVerifier;
  final AttendanceClock? clock;
  final String? initialEmployeeId;
  final bool autoContinue;
  final Future<void> Function(AttendanceEmployee employee)? onEmployeeConfirmed;

  @override
  State<EmployeeSelectionPage> createState() => _EmployeeSelectionPageState();
}

class _EmployeeSelectionPageState extends State<EmployeeSelectionPage> {
  int? _selectedIndex;
  bool _loading = false;
  bool _autoStarting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialEmployeeId = widget.initialEmployeeId;
    if (initialEmployeeId == null) return;
    final index = widget.employees.indexWhere(
      (employee) => employee.apiEmployeeId == initialEmployeeId,
    );
    if (index < 0) return;
    _selectedIndex = index;
    if (widget.autoContinue) {
      _autoStarting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _continue();
      });
    }
  }

  Future<void> _continue() async {
    final selectedIndex = _selectedIndex;
    if (_loading || selectedIndex == null) return;
    final employee = widget.employees[selectedIndex];
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final metadata = await widget.profileClient.fetchProfile(employee);
      final bytes = await widget.profileClient.downloadImage(
        metadata.imageFile,
      );
      validateAttendanceImageBytes(bytes);
      if (!mounted || selectedIndex != _selectedIndex) return;
      await widget.onEmployeeConfirmed?.call(employee);
      if (!mounted || selectedIndex != _selectedIndex) return;
      final profile = AttendanceProfile(
        displayName: metadata.displayName,
        companyId: metadata.companyId,
        imageFile: metadata.imageFile,
        imageBytes: bytes,
      );
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => AttendancePage(
            employee: employee,
            profile: profile,
            store: widget.store,
            syncService: widget.syncService,
            historyClient: widget.historyClient,
            faceVerifier: widget.faceVerifier,
            clock: widget.clock,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _autoStarting = false;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _autoStarting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_autoStarting) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: attendancePrimary),
                SizedBox(height: 16),
                Text(
                  'Loading attendance…',
                  style: TextStyle(
                    color: attendancePrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: attendancePrimary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Select Employee',
                style: TextStyle(
                  color: attendancePrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose your name to continue to attendance.',
                style: TextStyle(color: attendancePending, fontSize: 14),
              ),
              const SizedBox(height: 26),
              for (var index = 0; index < widget.employees.length; index++) ...[
                _EmployeeChoice(
                  key: Key(
                    'employeeSelector_'
                    '${widget.employees[index].apiEmployeeId}',
                  ),
                  employee: widget.employees[index],
                  selected: _selectedIndex == index,
                  enabled: !_loading,
                  onTap: () {
                    setState(() {
                      _selectedIndex = index;
                      _error = null;
                    });
                  },
                ),
                if (index != widget.employees.length - 1)
                  const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                Container(
                  key: const Key('profileLoadError'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEEF1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE9A9B4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFB43F55)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFF913145),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('continueToAttendanceButton'),
                onPressed: _selectedIndex == null || _loading
                    ? null
                    : _continue,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: attendancePrimary,
                  disabledBackgroundColor: attendanceBorder,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: _loading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          key: Key('profileLoadingIndicator'),
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_error == null ? 'Continue' : 'Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeChoice extends StatelessWidget {
  const _EmployeeChoice({
    super.key,
    required this.employee,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AttendanceEmployee employee;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? attendancePrimary.withValues(alpha: 0.08)
          : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? attendancePrimary : attendanceBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: selected
                    ? attendancePrimary
                    : attendancePrimary.withValues(alpha: 0.1),
                child: Text(
                  _initials(employee.displayName),
                  style: TextStyle(
                    color: selected ? Colors.white : attendancePrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.displayName,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Employee ID: ${employee.apiEmployeeId}',
                      style: TextStyle(
                        color: attendancePrimary.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? attendancePrimary : attendancePending,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
