/// One of the fixed employees available in the standalone attendance demo.
class AttendanceEmployee {
  const AttendanceEmployee({
    required this.displayName,
    required this.apiEmployeeId,
    required this.deviceMac,
  });

  final String displayName;
  final String apiEmployeeId;
  final String deviceMac;
}

const attendanceEmployees = <AttendanceEmployee>[
  AttendanceEmployee(
    displayName: 'Mostakima Akter Mita',
    apiEmployeeId: '3531774223',
    deviceMac: '08_2c_6d_f4_f4_99',
  ),
  AttendanceEmployee(
    displayName: 'Tamanna',
    apiEmployeeId: '3531774258',
    deviceMac: '08_2c_6d_f4_f4_99',
  ),
  AttendanceEmployee(
    displayName: 'Mir Sultan',
    apiEmployeeId: '2109058928',
    deviceMac: 'e3_30_f3_44_74_03',
  ),
];
