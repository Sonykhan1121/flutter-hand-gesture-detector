// Archived attendance-page prototype kept for reference; every line below is
// commented out, so this file is not part of the active app build.
// import 'dart:async';
// import 'dart:convert';
//
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';
//
// import 'adminFaceDetection.dart';
//
// class AttendancePage extends StatefulWidget {
//   const AttendancePage({super.key});
//
//   static const Color primary = Color(0xFF004D71);
//   static const Color primaryLight = Color(0x1A004D71);
//   static const Color borderColor = Color(0xFFD6E6F0);
//   static const Color darkText = Color(0xFF1F1F1F);
//   static const Color mutedText = Color(0xFF9E9B9B);
//   static const Color warning = Color(0xFFFF8A00);
//
//   @override
//   State<AttendancePage> createState() => _AttendancePageState();
// }
//
// class _AttendancePageState extends State<AttendancePage> {
//   static const String _empId = '3531774223'; // Mostakima
//   // static const String _empId = '3531774258'; // Tamanna
//
//   static const String _macId = '08_2c_6d_f4_f4_99';
//
//   static final Uri _punchApiUrl = Uri.parse(
//     'https://grozziie.zjweiting.com:3091/grozziie-attendance-debug/attendance/punch-update',
//   );
//
//   late DateTime _now;
//   Timer? _timer;
//
//   bool _isPunchProcessing = false;
//   List<DateTime> _todayPunchTimes = [];
//
//   @override
//   void initState() {
//     super.initState();
//
//     _now = DateTime.now();
//     _loadTodayPunchTimes();
//
//     _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
//       if (!mounted) return;
//
//       final previousDateKey = _formatDateKey(_now);
//       final currentNow = DateTime.now();
//       final currentDateKey = _formatDateKey(currentNow);
//
//       setState(() {
//         _now = currentNow;
//       });
//
//       if (previousDateKey != currentDateKey) {
//         await _loadTodayPunchTimes();
//       }
//     });
//   }
//
//   @override
//   void dispose() {
//     _timer?.cancel();
//     super.dispose();
//   }
//
//   Future<void> _handleFaceAttendance() async {
//     if (_isPunchProcessing) return;
//
//     setState(() {
//       _isPunchProcessing = true;
//     });
//
//     try {
//       final bool? faceDetected = await Navigator.push<bool>(
//         context,
//         MaterialPageRoute(
//           builder: (_) => const AdminFaceDetection(fontorback: 1),
//         ),
//       );
//
//       if (!mounted) return;
//
//       if (faceDetected != true) {
//         _showSnackBar('Face not detected.');
//         return;
//       }
//
//       final punchTime = DateTime.now();
//
//       await _savePunchTimeToSharedPreferences(punchTime);
//
//       final statusCode = await _sendSinglePunchTimeToApi(
//         punchTime: punchTime,
//       );
//
//       if (!mounted) return;
//
//       if (statusCode == 200) {
//         _showSnackBar('Punch saved and synced successfully.');
//       } else {
//         _showSnackBar('Punch saved locally. API sync failed: $statusCode');
//       }
//     } catch (e) {
//       debugPrint('Punch error: $e');
//
//       if (mounted) {
//         _showSnackBar('Something went wrong. Please try again.');
//       }
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isPunchProcessing = false;
//         });
//       }
//     }
//   }
//
//   Future<void> _loadTodayPunchTimes() async {
//     final prefs = await SharedPreferences.getInstance();
//
//     final todayKey = _attendanceKey(DateTime.now());
//     final savedJson = prefs.getString(todayKey);
//
//     if (savedJson == null || savedJson.isEmpty) {
//       if (!mounted) return;
//
//       setState(() {
//         _todayPunchTimes = [];
//       });
//       return;
//     }
//
//     try {
//       final decoded = jsonDecode(savedJson);
//
//       if (decoded is! List) {
//         if (!mounted) return;
//
//         setState(() {
//           _todayPunchTimes = [];
//         });
//         return;
//       }
//
//       final punches = decoded
//           .whereType<String>()
//           .map(DateTime.tryParse)
//           .whereType<DateTime>()
//           .toList()
//         ..sort();
//
//       if (!mounted) return;
//
//       setState(() {
//         _todayPunchTimes = punches;
//       });
//     } catch (e) {
//       debugPrint('SharedPreferences decode error: $e');
//
//       if (!mounted) return;
//
//       setState(() {
//         _todayPunchTimes = [];
//       });
//     }
//   }
//
//   Future<List<DateTime>> _savePunchTimeToSharedPreferences(
//       DateTime punchTime,
//       ) async {
//     final prefs = await SharedPreferences.getInstance();
//
//     final todayKey = _attendanceKey(punchTime);
//     final savedJson = prefs.getString(todayKey);
//
//     final List<DateTime> punches = [];
//
//     if (savedJson != null && savedJson.isNotEmpty) {
//       try {
//         final decoded = jsonDecode(savedJson);
//
//         if (decoded is List) {
//           final oldPunches = decoded
//               .whereType<String>()
//               .map(DateTime.tryParse)
//               .whereType<DateTime>();
//
//           punches.addAll(oldPunches);
//         }
//       } catch (e) {
//         debugPrint('Old punch decode error: $e');
//       }
//     }
//
//     punches.add(punchTime);
//     punches.sort();
//
//     final encodedPunches = punches
//         .map((dateTime) => dateTime.toIso8601String())
//         .toList();
//
//     await prefs.setString(todayKey, jsonEncode(encodedPunches));
//
//     if (mounted) {
//       setState(() {
//         _todayPunchTimes = punches;
//       });
//     }
//
//     return punches;
//   }
//
//   Future<int> _sendSinglePunchTimeToApi({
//     required DateTime punchTime,
//   }) async {
//     final date = _formatDateKey(punchTime);
//
//     /// Always 24-hour format.
//     /// Example: ["14:05"]
//     final checkInJson = jsonEncode([
//       _format24HourTimeWithoutSeconds(punchTime),
//     ]);
//
//     final body = <String, dynamic>{
//       'empId': _empId,
//       'macId': _macId,
//       'date': date,
//       'checkIn': checkInJson,
//       'checkOut': null,
//       'lunchTimeCheckIn': null,
//       'lunchTimeCheckOut': null,
//       'status': 'synced',
//     };
//
//     try {
//       final response = await http
//           .post(
//         _punchApiUrl,
//         headers: const {
//           'Content-Type': 'application/json; charset=UTF-8',
//         },
//         body: utf8.encode(jsonEncode(body)),
//       )
//           .timeout(const Duration(seconds: 20));
//
//       if (response.statusCode == 200) {
//         debugPrint('Attendance punched successfully.');
//       } else {
//         debugPrint(
//           'Failed to punch attendance: ${utf8.decode(response.bodyBytes)}',
//         );
//       }
//
//       return response.statusCode;
//     } catch (e) {
//       debugPrint('Error while punching attendance: $e');
//       return 400;
//     }
//   }
//
//   String _attendanceKey(DateTime dateTime) {
//     return 'attendance_${_formatDateKey(dateTime)}';
//   }
//
//   String _formatDateKey(DateTime dateTime) {
//     final year = dateTime.year.toString();
//     final month = _twoDigits(dateTime.month);
//     final day = _twoDigits(dateTime.day);
//
//     return '$year-$month-$day';
//   }
//
//   String _twoDigits(int value) {
//     return value.toString().padLeft(2, '0');
//   }
//
//   String _formatClockTime(DateTime dateTime) {
//     final hour = _twoDigits(dateTime.hour);
//     final minute = _twoDigits(dateTime.minute);
//     final second = _twoDigits(dateTime.second);
//
//     return '$hour:$minute:$second';
//   }
//
//   String _format24HourTimeWithoutSeconds(DateTime dateTime) {
//     final hour = _twoDigits(dateTime.hour);
//     final minute = _twoDigits(dateTime.minute);
//
//     return '$hour:$minute';
//   }
//
//   String _formatDate(DateTime dateTime) {
//     const months = [
//       'January',
//       'February',
//       'March',
//       'April',
//       'May',
//       'June',
//       'July',
//       'August',
//       'September',
//       'October',
//       'November',
//       'December',
//     ];
//
//     const weekdays = [
//       'Monday',
//       'Tuesday',
//       'Wednesday',
//       'Thursday',
//       'Friday',
//       'Saturday',
//       'Sunday',
//     ];
//
//     final day = _twoDigits(dateTime.day);
//     final month = months[dateTime.month - 1];
//     final year = dateTime.year;
//     final weekday = weekdays[dateTime.weekday - 1];
//
//     return '$day $month $year, $weekday';
//   }
//
//   String _shortWeekday(DateTime dateTime) {
//     const weekdays = [
//       'Mo',
//       'Tu',
//       'We',
//       'Th',
//       'Fr',
//       'Sa',
//       'Su',
//     ];
//
//     return weekdays[dateTime.weekday - 1];
//   }
//
//   void _showSnackBar(String message) {
//     if (!mounted) return;
//
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         behavior: SnackBarBehavior.floating,
//         duration: const Duration(seconds: 2),
//       ),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final currentTime = _formatClockTime(_now);
//     final currentDate = _formatDate(_now);
//
//     return Scaffold(
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.all(16),
//           child: SingleChildScrollView(
//             physics: const BouncingScrollPhysics(),
//             child: Column(
//               children: [
//                 const _TopBar(),
//                 const SizedBox(height: 16),
//                 const _EmployeeProfileSection(),
//                 const SizedBox(height: 32),
//                 const _WorkTypeSection(),
//                 const SizedBox(height: 50),
//                 _ClockSection(
//                   time: currentTime,
//                   date: currentDate,
//                 ),
//                 const SizedBox(height: 50),
//                 _ActionButtonSection(
//                   isLoading: _isPunchProcessing,
//                   onFaceAttendancePressed: _handleFaceAttendance,
//                 ),
//                 const SizedBox(height: 20),
//                 const _DeviceInfoText(),
//                 const SizedBox(height: 15),
//                 const _RefreshButton(),
//                 const SizedBox(height: 30),
//                 _TodayAttendanceSection(
//                   weekday: _shortWeekday(_now),
//                   day: _twoDigits(_now.day),
//                   punchTimes: _todayPunchTimes,
//                   formatTime: _format24HourTimeWithoutSeconds,
//                 ),
//                 const SizedBox(height: 10),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
//
// class _TopBar extends StatelessWidget {
//   const _TopBar();
//
//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       mainAxisAlignment: MainAxisAlignment.end,
//       children: [
//         Container(
//           height: 30,
//           width: 30,
//           decoration: BoxDecoration(
//             color: AttendancePage.primaryLight,
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: const Icon(
//             Icons.swap_horiz,
//             color: AttendancePage.primary,
//             size: 20,
//           ),
//         ),
//         const SizedBox(width: 16),
//         Stack(
//           clipBehavior: Clip.none,
//           children: [
//             const Icon(
//               Icons.notifications_outlined,
//               color: AttendancePage.primary,
//               size: 24,
//             ),
//             Positioned(
//               right: -2,
//               top: -2,
//               child: Container(
//                 height: 8,
//                 width: 8,
//                 decoration: const BoxDecoration(
//                   color: AttendancePage.warning,
//                   shape: BoxShape.circle,
//                 ),
//               ),
//             ),
//           ],
//         ),
//         const SizedBox(width: 16),
//         const Icon(
//           Icons.help_outline,
//           color: Colors.black,
//           size: 22,
//         ),
//       ],
//     );
//   }
// }
//
// class _EmployeeProfileSection extends StatelessWidget {
//   const _EmployeeProfileSection();
//
//   @override
//   Widget build(BuildContext context) {
//     return const Row(
//       children: [
//         CircleAvatar(
//           radius: 32,
//           backgroundColor: AttendancePage.primaryLight,
//           child: Icon(
//             Icons.person,
//             color: AttendancePage.primary,
//             size: 36,
//           ),
//         ),
//         SizedBox(width: 12),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Mostakima Akter Mita',
//                 style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.w500,
//                   color: AttendancePage.darkText,
//                 ),
//               ),
//               SizedBox(height: 4),
//               Text(
//                 'ID: TF0685',
//                 style: TextStyle(
//                   fontSize: 12,
//                   fontWeight: FontWeight.w400,
//                   color: AttendancePage.primary,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }
//
// class _WorkTypeSection extends StatelessWidget {
//   const _WorkTypeSection();
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         color: AttendancePage.primaryLight,
//         borderRadius: BorderRadius.circular(10),
//       ),
//       child: Padding(
//         padding: const EdgeInsets.only(
//           left: 10,
//           top: 8,
//           right: 10,
//           bottom: 12,
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Row(
//               children: [
//                 Text(
//                   'Select Work Type',
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.w600,
//                     color: AttendancePage.primary,
//                   ),
//                 ),
//                 Spacer(),
//                 Text(
//                   'E',
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.w600,
//                     color: AttendancePage.primary,
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 12),
//             Container(
//               height: 1,
//               color: AttendancePage.primary.withOpacity(0.2),
//             ),
//             const SizedBox(height: 8),
//             const Row(
//               children: [
//                 _WorkTypeOption(
//                   title: 'Home',
//                   icon: Icons.home_outlined,
//                   selected: false,
//                 ),
//                 SizedBox(width: 18),
//                 _WorkTypeOption(
//                   title: 'Onsite',
//                   icon: Icons.business_outlined,
//                   selected: true,
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
//
// class _WorkTypeOption extends StatelessWidget {
//   const _WorkTypeOption({
//     required this.title,
//     required this.icon,
//     required this.selected,
//   });
//
//   final String title;
//   final IconData icon;
//   final bool selected;
//
//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         _StaticRadio(selected: selected),
//         const SizedBox(width: 6),
//         Icon(
//           icon,
//           size: 20,
//           color: AttendancePage.primary,
//         ),
//         const SizedBox(width: 6),
//         Text(
//           title,
//           style: const TextStyle(
//             fontSize: 14,
//             color: AttendancePage.darkText,
//           ),
//         ),
//       ],
//     );
//   }
// }
//
// class _StaticRadio extends StatelessWidget {
//   const _StaticRadio({required this.selected});
//
//   final bool selected;
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 22,
//       width: 22,
//       decoration: BoxDecoration(
//         shape: BoxShape.circle,
//         border: Border.all(
//           color: AttendancePage.primary,
//           width: 2,
//         ),
//       ),
//       child: selected
//           ? Center(
//         child: Container(
//           height: 10,
//           width: 10,
//           decoration: const BoxDecoration(
//             color: AttendancePage.primary,
//             shape: BoxShape.circle,
//           ),
//         ),
//       )
//           : null,
//     );
//   }
// }
//
// class _ClockSection extends StatelessWidget {
//   const _ClockSection({
//     required this.time,
//     required this.date,
//   });
//
//   final String time;
//   final String date;
//
//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         Text(
//           time,
//           style: const TextStyle(
//             fontSize: 24,
//             fontWeight: FontWeight.w600,
//             color: AttendancePage.primary,
//           ),
//         ),
//         const SizedBox(height: 4),
//         Text(
//           date,
//           style: const TextStyle(
//             fontSize: 12,
//             color: Colors.black,
//           ),
//         ),
//       ],
//     );
//   }
// }
//
// class _ActionButtonSection extends StatelessWidget {
//   const _ActionButtonSection({
//     required this.isLoading,
//     required this.onFaceAttendancePressed,
//   });
//
//   final bool isLoading;
//   final Future<void> Function() onFaceAttendancePressed;
//
//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       mainAxisAlignment: MainAxisAlignment.center,
//       children: [
//         OutlinedButton.icon(
//           onPressed: isLoading ? null : () => onFaceAttendancePressed(),
//           icon: isLoading
//               ? const SizedBox(
//             height: 18,
//             width: 18,
//             child: CircularProgressIndicator(
//               strokeWidth: 2,
//               color: AttendancePage.primary,
//             ),
//           )
//               : const Icon(
//             Icons.face_retouching_natural_outlined,
//             color: AttendancePage.primary,
//             size: 20,
//           ),
//           label: Text(
//             isLoading ? 'Processing...' : 'Face Attendance',
//             style: const TextStyle(
//               fontSize: 12,
//               color: AttendancePage.primary,
//             ),
//           ),
//           style: OutlinedButton.styleFrom(
//             side: const BorderSide(color: AttendancePage.borderColor),
//             padding: const EdgeInsets.symmetric(
//               horizontal: 22,
//               vertical: 12,
//             ),
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(40),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }
//
// class _DeviceInfoText extends StatelessWidget {
//   const _DeviceInfoText();
//
//   @override
//   Widget build(BuildContext context) {
//     return const Padding(
//       padding: EdgeInsets.symmetric(horizontal: 35),
//       child: Text(
//         'When your device is near, attendance options will be available.',
//         style: TextStyle(
//           fontSize: 12,
//           color: AttendancePage.mutedText,
//         ),
//         textAlign: TextAlign.center,
//       ),
//     );
//   }
// }
//
// class _RefreshButton extends StatelessWidget {
//   const _RefreshButton();
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
//       decoration: BoxDecoration(
//         border: Border.all(color: AttendancePage.borderColor),
//         borderRadius: BorderRadius.circular(20),
//       ),
//       child: const Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Icon(
//             Icons.refresh,
//             color: AttendancePage.primary,
//             size: 20,
//           ),
//           SizedBox(width: 8),
//           Text(
//             'Refresh',
//             style: TextStyle(
//               fontSize: 12,
//               color: AttendancePage.primary,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class _TodayAttendanceSection extends StatelessWidget {
//   const _TodayAttendanceSection({
//     required this.weekday,
//     required this.day,
//     required this.punchTimes,
//     required this.formatTime,
//   });
//
//   final String weekday;
//   final String day;
//   final List<DateTime> punchTimes;
//   final String Function(DateTime dateTime) formatTime;
//
//   @override
//   Widget build(BuildContext context) {
//     final reversedPunchTimes = punchTimes.reversed.toList();
//
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 10),
//       child: Column(
//         children: [
//           const Align(
//             alignment: Alignment.topLeft,
//             child: Text(
//               "Today's Attendance",
//               style: TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.w600,
//                 color: AttendancePage.primary,
//               ),
//             ),
//           ),
//           const SizedBox(height: 10),
//           Container(
//             height: 52,
//             decoration: BoxDecoration(
//               color: AttendancePage.primaryLight,
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: Row(
//               children: [
//                 _DateBox(
//                   weekday: weekday,
//                   day: day,
//                 ),
//                 Expanded(
//                   child: punchTimes.isEmpty
//                       ? const Center(
//                     child: Text(
//                       'No punch data',
//                       style: TextStyle(
//                         fontSize: 12,
//                         color: AttendancePage.primary,
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                   )
//                       : SingleChildScrollView(
//                     scrollDirection: Axis.horizontal,
//                     child: Row(
//                       children: List.generate(
//                         reversedPunchTimes.length,
//                             (index) {
//                           final punch = reversedPunchTimes[index];
//                           final punchNumber = punchTimes.length - index;
//
//                           return _PunchTimeColumn(
//                             label: 'Punch $punchNumber',
//                             time: formatTime(punch),
//                           );
//                         },
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class _DateBox extends StatelessWidget {
//   const _DateBox({
//     required this.weekday,
//     required this.day,
//   });
//
//   final String weekday;
//   final String day;
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: 58,
//       decoration: const BoxDecoration(
//         color: AttendancePage.primary,
//         borderRadius: BorderRadius.only(
//           topLeft: Radius.circular(8),
//           bottomLeft: Radius.circular(8),
//         ),
//       ),
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Text(
//             weekday,
//             style: const TextStyle(
//               color: Colors.white,
//               fontWeight: FontWeight.w400,
//               fontSize: 8,
//             ),
//           ),
//           const SizedBox(height: 5),
//           Text(
//             day,
//             style: const TextStyle(
//               color: Colors.white,
//               fontWeight: FontWeight.w600,
//               fontSize: 12,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class _PunchTimeColumn extends StatelessWidget {
//   const _PunchTimeColumn({
//     required this.label,
//     required this.time,
//   });
//
//   final String label;
//   final String time;
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10),
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Text(
//             label,
//             style: const TextStyle(
//               color: AttendancePage.primary,
//               fontWeight: FontWeight.w400,
//               fontSize: 8,
//             ),
//           ),
//           const SizedBox(height: 5),
//           Text(
//             time,
//             style: const TextStyle(
//               color: AttendancePage.primary,
//               fontWeight: FontWeight.w600,
//               fontSize: 12,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
