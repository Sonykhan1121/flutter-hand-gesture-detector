import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/temp/attendance_employee.dart';
import 'package:gesture_detector/temp/attendance_profile_client.dart';

void main() {
  final profileEndpoint = Uri.parse(
    'https://grozziie.zjweiting.com:3091/'
    'grozziie-attendance-debug/employee/by/mac-employeId',
  );
  final imageEndpoint = Uri.parse(
    'https://grozziie.zjweiting.com:3091/'
    'grozziie-attendance-debug/api/files/download/device-wise/image',
  );

  test('configures all three employees with their own MAC', () {
    expect(
      attendanceEmployees
          .map(
            (employee) =>
                '${employee.displayName}|${employee.apiEmployeeId}|'
                '${employee.deviceMac}',
          )
          .toList(),
      <String>[
        'Mostakima Akter Mita|3531774223|08_2c_6d_f4_f4_99',
        'Tamanna|3531774258|08_2c_6d_f4_f4_99',
        'Mir Sultan|2109058928|e3_30_f3_44_74_03',
      ],
    );
  });

  test('builds Mir Sultan profile URL with employee-specific values', () {
    expect(
      attendanceProfileUri(
        endpoint: profileEndpoint,
        employee: attendanceEmployees.last,
      ).toString(),
      'https://grozziie.zjweiting.com:3091/'
      'grozziie-attendance-debug/employee/by/mac-employeId'
      '?employeeId=2109058928&mac=e3_30_f3_44_74_03',
    );
  });

  test('encodes the image filename slash as a query value', () {
    expect(
      attendanceImageUri(
        endpoint: imageEndpoint,
        imageFile:
            'e3_30_f3_44_74_03/'
            'b42ec26e-eeb9-469a-a051-5083a38eac81.jpg',
      ).toString(),
      'https://grozziie.zjweiting.com:3091/'
      'grozziie-attendance-debug/api/files/download/device-wise/image'
      '?filename=e3_30_f3_44_74_03%2F'
      'b42ec26e-eeb9-469a-a051-5083a38eac81.jpg',
    );
  });

  test('parses clean name, company ID, and image filename', () {
    final profile = attendanceProfileMetadataFromJson(<String, dynamic>{
      'name': 'Mir Sultan<1',
      'email': 'sultan@gmail.com| TG0650',
      'imageFile':
          'e3_30_f3_44_74_03/'
          'b42ec26e-eeb9-469a-a051-5083a38eac81.jpg',
    });

    expect(profile.displayName, 'Mir Sultan');
    expect(profile.companyId, 'TG0650');
    expect(
      profile.imageFile,
      'e3_30_f3_44_74_03/b42ec26e-eeb9-469a-a051-5083a38eac81.jpg',
    );
  });

  test('rejects profile email without a company ID suffix', () {
    expect(
      () => attendanceProfileMetadataFromJson(<String, dynamic>{
        'name': 'Mir Sultan',
        'email': 'sultan@gmail.com',
        'imageFile': 'employee.jpg',
      }),
      throwsA(isA<AttendanceProfileException>()),
    );
  });
}
