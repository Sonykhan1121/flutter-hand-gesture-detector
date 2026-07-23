import 'dart:typed_data';

class AttendanceProfileMetadata {
  const AttendanceProfileMetadata({
    required this.displayName,
    required this.companyId,
    required this.imageFile,
  });

  final String displayName;
  final String companyId;
  final String imageFile;
}

class AttendanceProfile {
  const AttendanceProfile({
    required this.displayName,
    required this.companyId,
    required this.imageFile,
    required this.imageBytes,
  });

  final String displayName;
  final String companyId;
  final String imageFile;
  final Uint8List imageBytes;
}
