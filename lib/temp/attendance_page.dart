import 'dart:async';

import 'package:flutter/material.dart';

import 'attendance_api_client.dart';
import 'attendance_employee.dart';
import 'attendance_history_client.dart';
import 'attendance_profile.dart';
import 'attendance_store.dart';
import 'attendance_sync_service.dart';
import 'face_verification_page.dart';
import 'utils/d_snack_bar.dart';

typedef AttendanceFaceVerifier = Future<bool> Function(BuildContext context);
typedef AttendanceClock = DateTime Function();

const attendancePrimary = Color(0xFF004D71);
const attendanceBorder = Color(0xFFD6E6F0);
const attendancePending = Color(0xFF9E9B9B);

class _AttendanceRefreshResult {
  const _AttendanceRefreshResult({this.historyError, this.retryError});

  final String? historyError;
  final String? retryError;

  bool get hasError => historyError != null || retryError != null;

  String get errorMessage =>
      <String?>[historyError, retryError].whereType<String>().join(' ');
}

class AttendancePage extends StatefulWidget {
  const AttendancePage({
    super.key,
    required this.employee,
    required this.profile,
    required this.store,
    required this.syncService,
    this.historyClient,
    this.faceVerifier,
    this.clock,
  });

  final AttendanceEmployee employee;
  final AttendanceProfile profile;
  final AttendanceStore store;
  final AttendanceSyncService syncService;
  final AttendanceHistoryClient? historyClient;
  final AttendanceFaceVerifier? faceVerifier;
  final AttendanceClock? clock;

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  late DateTime _now;
  Timer? _clockTimer;
  StreamSubscription<StoredAttendancePunch>? _syncSubscription;
  List<StoredAttendancePunch> _punches = const [];
  bool _loadingHistory = true;
  bool _isPunching = false;
  bool _isRefreshing = false;
  bool _isHomeSelected = false;
  int _loadGeneration = 0;
  int _historySyncCount = 1;
  final Map<String, Future<_AttendanceRefreshResult>> _activeHistorySyncs =
      <String, Future<_AttendanceRefreshResult>>{};

  DateTime get _currentTime => (widget.clock ?? DateTime.now)();
  bool get _isHistorySyncing => _historySyncCount > 0;

  @override
  void initState() {
    super.initState();
    _now = _currentTime;
    unawaited(_initializeAttendance());
    _syncSubscription = widget.syncService.changes.listen((punch) {
      if (!mounted ||
          punch.employeeId != widget.employee.apiEmployeeId ||
          attendanceDateKey(punch.punchedAt) != attendanceDateKey(_now)) {
        return;
      }
      unawaited(_loadHistory(showLoading: false));
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _currentTime;
      final changedDay = attendanceDateKey(next) != attendanceDateKey(_now);
      if (!mounted) return;
      setState(() => _now = next);
      if (changedDay) {
        unawaited(_handleDayRollover());
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    unawaited(_syncSubscription?.cancel());
    super.dispose();
  }

  Future<void> _initializeAttendance() async {
    final day = _now;
    try {
      await _loadHistory();
      final result = await _synchronizeCurrentDay(
        day: day,
        retryAllPending: true,
      );
      if (mounted && result.hasError) {
        _showError(result.errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _historySyncCount--;
          if (_historySyncCount < 0) _historySyncCount = 0;
        });
      }
    }
  }

  Future<void> _handleDayRollover() async {
    await _withHistorySyncIndicator(() async {
      await _loadHistory();
      final result = await _synchronizeCurrentDay(
        day: _now,
        retryAllPending: false,
      );
      if (mounted && result.hasError) {
        _showError(result.errorMessage);
      }
    });
  }

  Future<T> _withHistorySyncIndicator<T>(Future<T> Function() operation) async {
    if (mounted) setState(() => _historySyncCount++);
    try {
      return await operation();
    } finally {
      if (mounted) {
        setState(() {
          _historySyncCount--;
          if (_historySyncCount < 0) _historySyncCount = 0;
        });
      }
    }
  }

  Future<_AttendanceRefreshResult> _synchronizeCurrentDay({
    required DateTime day,
    required bool retryAllPending,
  }) {
    final key = '${widget.employee.apiEmployeeId}-${attendanceDateKey(day)}';
    final active = _activeHistorySyncs[key];
    if (active != null) return active;

    late final Future<_AttendanceRefreshResult> operation;
    operation =
        _performCurrentDaySynchronization(
          day: day,
          retryAllPending: retryAllPending,
        ).whenComplete(() {
          if (identical(_activeHistorySyncs[key], operation)) {
            _activeHistorySyncs.remove(key);
          }
        });
    _activeHistorySyncs[key] = operation;
    return operation;
  }

  Future<_AttendanceRefreshResult> _performCurrentDaySynchronization({
    required DateTime day,
    required bool retryAllPending,
  }) async {
    String? historyError;
    String? retryError;
    final historyClient = widget.historyClient;
    if (historyClient != null) {
      try {
        final history = await historyClient.fetchToday(
          employeeId: widget.employee.apiEmployeeId,
          macId: widget.employee.deviceMac,
          date: day,
        );
        await widget.syncService.reconcileServerHistory(
          employee: widget.employee,
          day: day,
          checkInTimes: history.checkInTimes,
        );
      } catch (error) {
        historyError =
            'Could not load server attendance: $error '
            'Showing saved data.';
      }
    }

    try {
      if (retryAllPending) {
        await widget.syncService.syncAllPending();
      } else {
        await widget.syncService.syncPendingForEmployee(
          widget.employee.apiEmployeeId,
        );
      }
    } catch (error) {
      retryError = 'Could not retry pending punches: $error';
    }

    if (mounted && attendanceDateKey(day) == attendanceDateKey(_now)) {
      await _loadHistory(showLoading: false);
    }
    return _AttendanceRefreshResult(
      historyError: historyError,
      retryError: retryError,
    );
  }

  Future<void> _loadHistory({bool showLoading = true}) async {
    final generation = ++_loadGeneration;
    final day = _now;
    if (showLoading && mounted) {
      setState(() => _loadingHistory = true);
    }
    try {
      final punches = await widget.store.loadPunches(
        employeeId: widget.employee.apiEmployeeId,
        deviceMac: widget.employee.deviceMac,
        day: day,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          attendanceDateKey(day) != attendanceDateKey(_now)) {
        return;
      }
      setState(() {
        _punches = punches;
        _loadingHistory = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadingHistory = false);
      _showError('Could not load attendance history: $error');
    }
  }

  Future<bool> _verifyFace() {
    final override = widget.faceVerifier;
    if (override != null) return override(context);
    return Navigator.of(context)
        .push<bool>(
          MaterialPageRoute<bool>(builder: (_) => const FaceVerificationPage()),
        )
        .then((result) => result ?? false);
  }

  Future<void> _punchAttendance() async {
    if (_isPunching || _isRefreshing || _isHistorySyncing) return;
    setState(() => _isPunching = true);
    try {
      final verified = await _verifyFace();
      if (!verified) {
        if (mounted) {
          _showInformation(
            'Face verification was cancelled. No punch was saved.',
          );
        }
        return;
      }

      AttendanceSubmissionOutcome outcome;
      try {
        outcome = await widget.syncService.recordAndSubmit(
          employee: widget.employee,
          punchedAt: _currentTime,
        );
      } catch (error) {
        if (mounted) {
          _showError('The punch could not be saved locally: $error');
        }
        return;
      }
      await _loadHistory(showLoading: false);
      if (!mounted) return;
      if (outcome.isSynced) {
        _showSuccess(
          'You punched successfully.',
          name: widget.profile.displayName,
        );
      } else {
        final detail =
            outcome.apiResult.errorMessage ??
            'server returned HTTP '
                '${outcome.apiResult.statusCode ?? 'unknown'}';
        _showInformation(
          'Punch saved as pending. It will retry automatically. $detail',
        );
      }
    } finally {
      if (mounted) setState(() => _isPunching = false);
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing || _isPunching || _isHistorySyncing) return;
    setState(() => _isRefreshing = true);
    try {
      final result = await _withHistorySyncIndicator(
        () => _synchronizeCurrentDay(day: _now, retryAllPending: false),
      );
      if (!mounted) return;
      if (result.hasError) {
        _showError(result.errorMessage);
        return;
      }
      final pendingCount = _punches.where((punch) => punch.isPending).length;
      _showInformation(
        pendingCount == 0
            ? 'Attendance refreshed.'
            : '$pendingCount punch${pendingCount == 1 ? '' : 'es'} still '
                  'waiting for the server.',
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _showSuccess(String title, {String? name}) {
    if (!mounted) return;
    DSnackBar.successSnackBar(title: title, name: name, context: context);
  }

  void _showInformation(String title) {
    if (!mounted) return;
    DSnackBar.informationSnackBar(title: title, context: context);
  }

  void _showError(String title) {
    if (!mounted) return;
    DSnackBar.errorSnackBar(title: title, context: context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: RefreshIndicator(
            color: attendancePrimary,
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _ProfileRow(profile: widget.profile),
                  const SizedBox(height: 32),
                  _WorkTypePanel(
                    isHomeSelected: _isHomeSelected,
                    onChanged: (value) {
                      setState(() => _isHomeSelected = value);
                    },
                  ),
                  const SizedBox(height: 50),
                  _Clock(now: _now),
                  const SizedBox(height: 50),
                  OutlinedButton.icon(
                    key: const Key('faceAttendanceButton'),
                    onPressed: _isPunching || _isRefreshing || _isHistorySyncing
                        ? null
                        : _punchAttendance,
                    icon: _isPunching
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: attendancePrimary,
                            ),
                          )
                        : const Icon(Icons.face_retouching_natural_outlined),
                    label: Text(
                      _isPunching ? 'Processing…' : 'Face Attendance',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: attendancePrimary,
                      side: const BorderSide(color: attendanceBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40),
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    key: const Key('refreshAttendanceHistoryButton'),
                    onPressed: _isRefreshing || _isPunching || _isHistorySyncing
                        ? null
                        : _refresh,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: attendancePrimary,
                      side: const BorderSide(color: attendanceBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isRefreshing)
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: attendancePrimary,
                            ),
                          )
                        else
                          const Icon(Icons.refresh_rounded, size: 20),
                        const SizedBox(width: 8),
                        const Text('Refresh'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  _AttendanceHistory(
                    day: _now,
                    punches: _punches,
                    loading: _loadingHistory,
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.profile});

  final AttendanceProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          key: const Key('attendanceProfilePhoto'),
          radius: 32,
          backgroundColor: attendanceBorder,
          backgroundImage: MemoryImage(profile.imageBytes),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.displayName,
                key: const Key('selectedEmployeeName'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ID: ${profile.companyId}',
                key: const Key('selectedEmployeeCompanyId'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: attendancePrimary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkTypePanel extends StatelessWidget {
  const _WorkTypePanel({required this.isHomeSelected, required this.onChanged});

  final bool isHomeSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('workTypePanel'),
      height: 110,
      padding: const EdgeInsets.only(left: 10, top: 8),
      decoration: BoxDecoration(
        color: attendancePrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: Row(
              children: [
                Text(
                  'Select Work Type',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: attendancePrimary,
                  ),
                ),
                Spacer(),
                Text(
                  'E',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: attendancePrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: attendancePrimary.withValues(alpha: 0.2)),
          Row(
            children: [
              _WorkTypeRadio(
                key: const Key('homeWorkType'),
                label: 'Home',
                icon: Icons.home_outlined,
                value: true,
                groupValue: isHomeSelected,
                onChanged: onChanged,
              ),
              const SizedBox(width: 2),
              _WorkTypeRadio(
                key: const Key('onsiteWorkType'),
                label: 'Onsite',
                icon: Icons.apartment_outlined,
                value: false,
                groupValue: isHomeSelected,
                onChanged: onChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkTypeRadio extends StatelessWidget {
  const _WorkTypeRadio({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool value;
  final bool groupValue;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                value == groupValue
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: attendancePrimary,
                size: 22,
              ),
            ),
            Icon(icon, size: 20, color: attendancePrimary),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}

class _Clock extends StatelessWidget {
  const _Clock({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _clockText(now),
          key: const Key('currentClock'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: attendancePrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _longDate(now),
          key: const Key('currentDate'),
          style: const TextStyle(fontSize: 12, color: Colors.black),
        ),
      ],
    );
  }
}

class _AttendanceHistory extends StatelessWidget {
  const _AttendanceHistory({
    required this.day,
    required this.punches,
    required this.loading,
  });

  final DateTime day;
  final List<StoredAttendancePunch> punches;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final newestFirst = punches.reversed.toList(growable: false);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today’s Attendance',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: attendancePrimary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: const Key('attendancePunchHistory'),
            height: 52,
            decoration: BoxDecoration(
              color: attendancePrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _DateBlock(day: day),
                Expanded(
                  child: loading
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              key: Key('historyLoadingIndicator'),
                              strokeWidth: 2,
                              color: attendancePrimary,
                            ),
                          ),
                        )
                      : newestFirst.isEmpty
                      ? const Center(
                          child: Text(
                            'No punch data',
                            key: Key('emptyAttendanceHistory'),
                            style: TextStyle(
                              color: attendancePending,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (
                                var index = 0;
                                index < newestFirst.length;
                                index++
                              )
                                _PunchColumn(
                                  punch: newestFirst[index],
                                  number: newestFirst.length - index,
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: attendancePrimary,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _weekdayAbbreviation(day),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w400,
              fontSize: 8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${day.day}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PunchColumn extends StatelessWidget {
  const _PunchColumn({required this.punch, required this.number});

  final StoredAttendancePunch punch;
  final int number;

  @override
  Widget build(BuildContext context) {
    final color = punch.isPending ? attendancePending : attendancePrimary;
    return Container(
      key: Key('punch_${punch.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Punch $number',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w400,
              fontSize: 8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _shortTime(punch.punchedAt),
            key: Key('punchTime_${punch.id}'),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

String _clockText(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '${hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')} $period';
}

String _shortTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '${hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')} $period';
}

String _longDate(DateTime value) {
  const weekdays = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${value.day} ${months[value.month - 1]}, '
      '${weekdays[value.weekday - 1]}';
}

String _weekdayAbbreviation(DateTime value) {
  const weekdays = <String>['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  return weekdays[value.weekday - 1];
}
