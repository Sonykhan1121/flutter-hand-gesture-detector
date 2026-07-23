import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'attendance_employee.dart';
import 'attendance_profile.dart';

class AttendanceProfileException implements Exception {
  const AttendanceProfileException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AttendanceProfileClient {
  Future<AttendanceProfileMetadata> fetchProfile(AttendanceEmployee employee);

  Future<Uint8List> downloadImage(String imageFile);
}

class IoAttendanceProfileClient implements AttendanceProfileClient {
  IoAttendanceProfileClient({
    required this.profileEndpoint,
    required this.imageEndpoint,
    this.timeout = const Duration(seconds: 20),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final Uri profileEndpoint;
  final Uri imageEndpoint;
  final Duration timeout;
  final HttpClient Function() _clientFactory;

  @override
  Future<AttendanceProfileMetadata> fetchProfile(
    AttendanceEmployee employee,
  ) async {
    final uri = attendanceProfileUri(
      endpoint: profileEndpoint,
      employee: employee,
    );
    final bytes = await _getBytes(uri, operation: 'Employee profile');
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw AttendanceProfileException(
        'Employee profile returned invalid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AttendanceProfileException(
        'Employee profile response was not a JSON object.',
      );
    }
    return attendanceProfileMetadataFromJson(decoded);
  }

  @override
  Future<Uint8List> downloadImage(String imageFile) async {
    final uri = attendanceImageUri(
      endpoint: imageEndpoint,
      imageFile: imageFile,
    );
    final bytes = await _getBytes(uri, operation: 'Employee image');
    validateAttendanceImageBytes(bytes);
    return bytes;
  }

  Future<Uint8List> _getBytes(Uri uri, {required String operation}) async {
    final client = _clientFactory();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final builder = await response
          .fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (buffer, chunk) => buffer..add(chunk),
          )
          .timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw AttendanceProfileException(
          '$operation failed with HTTP ${response.statusCode}.',
        );
      }
      return builder.takeBytes();
    } on TimeoutException {
      throw AttendanceProfileException(
        '$operation timed out after ${timeout.inSeconds} seconds.',
      );
    } on SocketException catch (error) {
      throw AttendanceProfileException(
        '$operation network error: ${error.message}',
      );
    } on HttpException catch (error) {
      throw AttendanceProfileException(
        '$operation HTTP error: ${error.message}',
      );
    } finally {
      client.close(force: true);
    }
  }
}

void validateAttendanceImageBytes(Uint8List bytes) {
  final isPng =
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;
  final isJpeg =
      bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;
  final isWebP =
      bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
  if (!isPng && !isJpeg && !isWebP) {
    throw const AttendanceProfileException(
      'Employee image response was not a valid PNG, JPEG, or WebP image.',
    );
  }
}

Uri attendanceProfileUri({
  required Uri endpoint,
  required AttendanceEmployee employee,
}) {
  return endpoint.replace(
    queryParameters: <String, String>{
      'employeeId': employee.apiEmployeeId,
      'mac': employee.deviceMac,
    },
  );
}

Uri attendanceImageUri({required Uri endpoint, required String imageFile}) {
  return endpoint.replace(
    queryParameters: <String, String>{'filename': imageFile},
  );
}

AttendanceProfileMetadata attendanceProfileMetadataFromJson(
  Map<String, dynamic> json,
) {
  final rawName = json['name']?.toString().trim() ?? '';
  final displayName = rawName.replaceFirst(RegExp(r'<\d+>?$'), '').trim();
  if (displayName.isEmpty) {
    throw const AttendanceProfileException(
      'Employee profile did not contain a valid name.',
    );
  }

  final email = json['email']?.toString() ?? '';
  final separator = email.lastIndexOf('|');
  final companyId = separator < 0 ? '' : email.substring(separator + 1).trim();
  if (companyId.isEmpty) {
    throw const AttendanceProfileException(
      'Employee profile email did not contain a company ID after "|".',
    );
  }

  final imageFile = json['imageFile']?.toString().trim() ?? '';
  if (imageFile.isEmpty) {
    throw const AttendanceProfileException(
      'Employee profile did not contain an image filename.',
    );
  }

  return AttendanceProfileMetadata(
    displayName: displayName,
    companyId: companyId,
    imageFile: imageFile,
  );
}
