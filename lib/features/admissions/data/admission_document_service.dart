import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// This API intentionally exposes no private Storage read, delete, or download.
class AdmissionDocumentRecord {
  const AdmissionDocumentRecord({
    required this.id,
    required this.revision,
    required this.kind,
    required this.status,
    required this.required,
    required this.applicable,
    this.version,
  });

  final String id, kind, status;
  final int revision;
  final bool required, applicable;
  final int? version;

  factory AdmissionDocumentRecord.fromJson(Map<String, dynamic> json) {
    return AdmissionDocumentRecord(
      id: json['id'] as String,
      revision: (json['revision'] as num).toInt(),
      kind: json['kind'] as String,
      status: json['status'] as String,
      required: json['required'] == true,
      applicable: json['applicable'] == true,
      version: (json['version'] as num?)?.toInt(),
    );
  }
}

abstract class AdmissionDocumentService {
  const AdmissionDocumentService();
  Future<List<AdmissionDocumentRecord>> listDocuments(String applicationId);

  Uint8List? photoPreviewBytes(String applicationId) => null;
  Future<Uint8List?> loadPhotoPreview(String applicationId) async =>
      photoPreviewBytes(applicationId);

  /// Optional student photo is private and never substitutes for certificates.
  Future<AdmissionDocumentRecord?> preparePhoto(String applicationId) async => null;

  Future<bool> pickAndUploadPhoto({
    required String schoolId,
    required String campusId,
    required String applicationId,
    required AdmissionDocumentRecord document,
  }) => pickAndUpload(
    schoolId: schoolId,campusId: campusId,
    applicationId: applicationId,document: document,
  );

  /// Returns false on picker cancellation; true only when registration succeeds.
  Future<bool> pickAndUpload({
    required String schoolId,
    required String campusId,
    required String applicationId,
    required AdmissionDocumentRecord document,
  });
}

class _PendingRegistration {
  const _PendingRegistration(this.path, this.revision);
  final String path;
  final int revision;
}

class SupabaseAdmissionDocumentService implements AdmissionDocumentService {
  SupabaseAdmissionDocumentService(this.client);
  final SupabaseClient client;
  final Map<String, _PendingRegistration> _pending = {};
  final Map<String, Uint8List> _photoCache = {};

  @override
  Uint8List? photoPreviewBytes(String applicationId) => _photoCache[applicationId];

  @override
  Future<Uint8List?> loadPhotoPreview(String applicationId) async {
    await _requireAuth();
    final path = await client.rpc('owner_admission_photo_path', params: {
      'p_application': applicationId,
    });
    if (path is! String || path.isEmpty) return _photoCache[applicationId];
    final bytes = await client.storage.from(bucket).download(path);
    if (bytes.length > maxPhotoBytes) return null;
    _photoCache[applicationId] = bytes;
    return bytes;
  }

  static const bucket = 'sms-admission-documents';
  static const maxBytes = 10485760;
  static const maxPhotoBytes = 2097152;

  static String _randomUuid() {
    final rng = Random.secure();
    final b = List<int>.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  Future<void> _requireAuth() async {
    if (client.auth.currentSession == null ||
        (await client.auth.getUser()).user == null) {
      throw StateError('Verified school sign-in required');
    }
  }

  @override
  Future<AdmissionDocumentRecord> preparePhoto(String applicationId) async {
    await _requireAuth();
    final data = await client.rpc('owner_prepare_admission_photo',
      params: {'p_application_id':applicationId});
    if (data is! Map) throw StateError('Photo preparation not confirmed');
    return AdmissionDocumentRecord.fromJson(Map<String,dynamic>.from(data));
  }

  @override
  Future<List<AdmissionDocumentRecord>> listDocuments(
      String applicationId) async {
    await _requireAuth();
    final data = await client.rpc('owner_admission_documents',
        params: {'p_application_id': applicationId});
    if (data is! List) throw StateError('Invalid document list response');
    return List.unmodifiable(data.map((item) => AdmissionDocumentRecord.fromJson(
          Map<String, dynamic>.from(item as Map),
        )));
  }

  static String? _mime(String ext) => switch (ext) {
        'pdf' => 'application/pdf',
        'jpg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => null,
      };

  static bool _validBytes(Uint8List data, String ext) {
    if (data.isEmpty || data.length > maxBytes) return false;
    if (ext == 'pdf') {
      return data.length >= 5 &&
          data[0] == 0x25 && data[1] == 0x50 &&
          data[2] == 0x44 && data[3] == 0x46 && data[4] == 0x2d;
    }
    if (ext == 'jpg') {
      return data.length >= 3 &&
          data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff;
    }
    if (ext == 'png') {
      return data.length >= 8 &&
          data[0] == 0x89 && data[1] == 0x50 &&
          data[2] == 0x4e && data[3] == 0x47 &&
          data[4] == 0x0d && data[5] == 0x0a &&
          data[6] == 0x1a && data[7] == 0x0a;
    }
    if (ext == 'webp') {
      return data.length >= 12 &&
          data[0] == 0x52 && data[1] == 0x49 &&
          data[2] == 0x46 && data[3] == 0x46 &&
          data[8] == 0x57 && data[9] == 0x45 &&
          data[10] == 0x42 && data[11] == 0x50;
    }
    return false;
  }

  Future<void> _register(AdmissionDocumentRecord document,
      _PendingRegistration pending) async {
    final response = await client.rpc('owner_register_admission_upload',
        params: {
          'p_document_id': document.id,
          'p_object_path': pending.path,
          'p_expected_revision': pending.revision,
        });
    if (response is! Map || response['status'] != 'uploaded') {
      throw StateError('Upload metadata registration was not confirmed');
    }
    _pending.remove(document.id);
  }

  @override
  Future<bool> pickAndUpload({
    required String schoolId,
    required String campusId,
    required String applicationId,
    required AdmissionDocumentRecord document,
  }) => _pickAndUpload(
    schoolId:schoolId,campusId:campusId,
    applicationId:applicationId,document:document,photoOnly:false);

  @override
  Future<bool> pickAndUploadPhoto({
    required String schoolId,
    required String campusId,
    required String applicationId,
    required AdmissionDocumentRecord document,
  }) => _pickAndUpload(
    schoolId:schoolId,campusId:campusId,
    applicationId:applicationId,document:document,photoOnly:true);

  Future<bool> _pickAndUpload({
    required String schoolId,
    required String campusId,
    required String applicationId,
    required AdmissionDocumentRecord document,
    required bool photoOnly,
  }) async {
    if (photoOnly != (document.kind == 'photo')) {
      throw StateError('Invalid photo document type');
    }
    await _requireAuth();
    if (!document.applicable ||
        !{'missing', 'uploaded', 'rejected'}.contains(document.status)) {
      throw StateError('Document cannot be uploaded in this state');
    }
    final earlier = _pending[document.id];
    if (earlier != null) {
      await _register(document, earlier);
      return true;
    }
    final selection = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: photoOnly
        ? const ['jpg','jpeg','png','webp']
        : const ['pdf','jpg','jpeg','png','webp'],
      withData: true,
      allowMultiple: false,
    );
    if (selection == null || selection.files.isEmpty) return false;
    final selected = selection.files.single;
    final bytes = selected.bytes;
    final rawExt = selected.extension?.toLowerCase();
    final extension = rawExt == 'jpeg' ? 'jpg' : rawExt;
    if (bytes == null || extension == null ||
        _mime(extension) == null || !_validBytes(bytes, extension) ||
        (photoOnly && (bytes.length > maxPhotoBytes || extension == 'pdf'))) {
      throw StateError(photoOnly
        ? 'Invalid student photo. Use JPG/PNG/WebP under 2 MiB.'
        : 'Invalid certificate. Use PDF/JPG/PNG/WebP under 10 MiB.');
    }
    final objectPath = '$schoolId/$campusId/$applicationId/'
        '${document.id}/${_randomUuid()}.$extension';
    await client.storage.from(bucket).uploadBinary(
      objectPath,
      bytes,
      fileOptions: FileOptions(
        contentType: _mime(extension),
        upsert: false,
        cacheControl: '0',
      ),
    );
    final pending = _PendingRegistration(objectPath, document.revision);
    _pending[document.id] = pending;
    await _register(document, pending);
    if (photoOnly) _photoCache[applicationId] = bytes;
    return true;
  }
}
