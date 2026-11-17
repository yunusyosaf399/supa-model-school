import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A private school asset. Access is checked by Supabase Storage policies
/// and the Owner-only metadata update RPC, never by client-side role flags.
class SchoolLogoService extends ChangeNotifier {
  SchoolLogoService(this.client);
  final SupabaseClient client;
  static const bucket = 'sms-school-logos';
  static const maxBytes = 2097152;
  Uint8List? _bytes;
  Uint8List? get bytes => _bytes;
  bool _busy = false;
  bool get busy => _busy;

  Future<void> load(String? objectPath) async {
    if (objectPath == null || objectPath.isEmpty) {
      _bytes = null;
      notifyListeners();
      return;
    }
    try {
      _bytes = await client.storage.from(bucket).download(objectPath);
    } catch (_) {
      _bytes = null; // Keep the default icon when offline or unauthorized.
    }
    notifyListeners();
  }

  Future<bool> upload(String schoolId) async {
    if (_busy) return false;
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (selection == null || selection.files.isEmpty) return false;
    final file = selection.files.single;
    final bytes = file.bytes;
    final extension = file.extension?.toLowerCase() == 'jpeg'
        ? 'jpg' : file.extension?.toLowerCase();
    if (bytes == null || bytes.isEmpty || bytes.length > maxBytes ||
        !{'png', 'jpg', 'webp'}.contains(extension)) {
      throw const FormatException('Choose PNG/JPG/WebP under 2 MiB');
    }
    final valid = extension == 'png'
        ? bytes.length > 8 && bytes[0] == 0x89 &&
          bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47
        : extension == 'jpg'
          ? bytes.length > 3 && bytes[0] == 0xff && bytes[1] == 0xd8
          : bytes.length > 12 &&
            String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
            String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    if (!valid) throw const FormatException('Invalid image file');
    _busy = true;
    notifyListeners();
    try {
      final random = Random.secure();
      final id = List.generate(16, (_) =>
          random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      final path = schoolId + '/logos/' + id + '.' + extension!;
      await client.storage.from(bucket).uploadBinary(
        path, bytes,
        fileOptions: FileOptions(
          upsert: false, cacheControl: '0',
          contentType: switch (extension) {
            'png' => 'image/png',
            'webp' => 'image/webp',
            _ => 'image/jpeg',
          },
        ),
      );
      final response = await client.rpc('owner_set_school_logo', params: {
        'p_school': schoolId, 'p_path': path,
      });
      if (response is! Map || response['logo_storage_path'] != path) {
        throw StateError('School logo was not confirmed by the server');
      }
      _bytes = bytes;
      notifyListeners();
      return true;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
