import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import 'campus_cache_database.dart';

/// Local-only, campus-pinned admission draft input.
/// Never store real child PII until offline authorization, encryption, secure
/// backups, and authenticated backend reconciliation are implemented.
class OfflineAdmissionDraftWrite {
  const OfflineAdmissionDraftWrite({
    required this.schoolId,
    required this.campusId,
    required this.deviceId,
    required this.academicYearId,
    required this.applicantName,
    this.localApplicationId,
    this.operationId,
    this.dateOfBirth,
    this.previousSchool,
    this.requestedClassId,
    this.requestedSectionId,
  });
  final String schoolId, campusId, deviceId, academicYearId, applicantName;
  final String? localApplicationId, operationId, dateOfBirth, previousSchool;
  final String? requestedClassId, requestedSectionId;
}

class QueuedAdmissionDraft {
  const QueuedAdmissionDraft(this.operationId, this.localApplicationId, this.localRevision);
  final String operationId, localApplicationId;
  final int localRevision;
}

class LeasedOfflineOperation {
  const LeasedOfflineOperation({
    required this.operationId,
    required this.leaseToken,
    required this.localApplicationId,
    required this.payloadJson,
    required this.expectedCloudRevision,
    required this.localRevision,
    required this.attemptCount,
  });
  final String operationId, leaseToken, localApplicationId, payloadJson;
  final int localRevision, attemptCount;
  final int? expectedCloudRevision;
}

/// Transactional local persistence only; no network transport.
///
/// All operations are serialized in SQLite by ascending sequence_no. A leased
/// or conflicted head blocks later actions, preventing dependent updates from
/// overtaking a previously queued admission. The D04-T03 server integration
/// must validate receipt identity and expected cloud revisions independently.
class OfflineOutboxRepository {
  OfflineOutboxRepository(
    this.db, {
    int Function()? clockMs,
    String Function()? uuidV4,
  }) : _clock = clockMs ??
           (() => DateTime.now().toUtc().millisecondsSinceEpoch),
       _newId = uuidV4 ?? _generateUuidV4;

  final CampusCacheDatabase db;
  final int Function() _clock;
  final String Function() _newId;

  static final Random _random = Random.secure();
  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _errorCodeRegex = RegExp(r'^[A-Z][A-Z0-9_]{0,47}$');

  static String _generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return hex.substring(0, 8) + '-' + hex.substring(8, 12) + '-' +
        hex.substring(12, 16) + '-' + hex.substring(16, 20) + '-' +
        hex.substring(20);
  }
  static void _assertUuid(String value) {
    if (!_uuidRegex.hasMatch(value)) throw ArgumentError('Invalid v4 operation UUID');
  }
  static void _assertErrorCode(String value) {
    if (!_errorCodeRegex.hasMatch(value)) {
      throw ArgumentError('Use safe uppercase error codes, never PII');
    }
  }

  /// Create/update local_admissions and outbox atomically. An existing
  /// operation UUID is an idempotency key: repeated, *identical* input
  /// returns its stored result without advancing local_revision.
  ///
  /// Local creation uses operationId as the provisional application UUID.
  /// The cloud will issue a different permanent application UUID; mapping
  /// that ID on acknowledgement is delegated to D04-T03.
  Future<QueuedAdmissionDraft> queueAdmissionDraft(
      OfflineAdmissionDraftWrite draft) async {
    final op = draft.operationId ?? _newId();
    final localId = draft.localApplicationId ?? op;
    _assertUuid(op);
    _assertUuid(localId);
    if (draft.schoolId.isEmpty || draft.campusId.isEmpty ||
        draft.deviceId.isEmpty || draft.academicYearId.isEmpty ||
        draft.applicantName.trim().length < 2) {
      throw ArgumentError('Required school/campus/device/year/name missing');
    }
    if (draft.requestedSectionId != null && draft.requestedClassId == null) {
      throw ArgumentError('Section requires a selected class');
    }
    if (draft.dateOfBirth != null &&
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(draft.dateOfBirth!)) {
      throw ArgumentError('Birth date must be YYYY-MM-DD');
    }
    final payload = jsonEncode({
      'operation_id': op,
      'local_application_id': localId,
      'academic_year_id': draft.academicYearId,
      'applicant_name': draft.applicantName.trim(),
      'date_of_birth': draft.dateOfBirth,
      'previous_school': draft.previousSchool?.trim(),
      'requested_class_id': draft.requestedClassId,
      'requested_section_id': draft.requestedSectionId,
    });

    return db.transaction(() async {
      if (!await db.isBoundTo(
          schoolId: draft.schoolId,
          campusId: draft.campusId,
          deviceId: draft.deviceId)) {
        throw StateError('Database not bound to verified school/campus/device');
      }

      final repeat = await db.customSelect(
        'SELECT school_id,campus_id,aggregate_id,payload_json,local_revision '
        'FROM local_outbox_operations WHERE operation_id=?',
        variables: [Variable.withString(op)],
      ).getSingleOrNull();
      if (repeat != null) {
        if (repeat.read<String>('school_id') != draft.schoolId ||
            repeat.read<String>('campus_id') != draft.campusId ||
            repeat.read<String>('aggregate_id') != localId ||
            repeat.read<String>('payload_json') != payload) {
          throw StateError('Operation UUID replayed with different contents');
        }
        return QueuedAdmissionDraft(
            op,localId,repeat.read<int>('local_revision'));
      }

      final existing = await db.customSelect(
        'SELECT local_revision,cloud_revision FROM local_admissions '
        'WHERE id=? AND school_id=? AND campus_id=?',
        variables: [
          Variable.withString(localId),
          Variable.withString(draft.schoolId),
          Variable.withString(draft.campusId),
        ],
      ).getSingleOrNull();
      final rev = (existing?.read<int>('local_revision') ?? 0) + 1;
      final cloudRev = existing?.readNullable<int>('cloud_revision');
      final now = _clock();
      if (now <= 0) throw StateError('Invalid monotonic wall-clock timestamp');

      if (existing == null) {
        await db.customStatement(
          'INSERT INTO local_admissions '
          '(id,school_id,campus_id,academic_year_id,requested_class_id,'
          'requested_section_id,applicant_name,date_of_birth,previous_school,'
          'cloud_revision,local_revision,locally_edited,updated_at_ms) '
          'VALUES (?,?,?,?,?,?,?,?,?,?,?,1,?)',
          [
            localId,draft.schoolId,draft.campusId,draft.academicYearId,
            draft.requestedClassId,draft.requestedSectionId,
            draft.applicantName.trim(),draft.dateOfBirth,
            draft.previousSchool?.trim(),cloudRev,rev,now,
          ],
        );
      } else {
        await db.customStatement(
          'UPDATE local_admissions SET academic_year_id=?,'
          'requested_class_id=?,requested_section_id=?,applicant_name=?,'
          'date_of_birth=?,previous_school=?,local_revision=?,'
          'locally_edited=1,updated_at_ms=? '
          'WHERE id=? AND school_id=? AND campus_id=?',
          [
            draft.academicYearId,draft.requestedClassId,
            draft.requestedSectionId,draft.applicantName.trim(),
            draft.dateOfBirth,draft.previousSchool?.trim(),rev,now,
            localId,draft.schoolId,draft.campusId,
          ],
        );
      }
      await db.customStatement(
        'INSERT INTO local_outbox_operations '
        '(operation_id,school_id,campus_id,aggregate_type,aggregate_id,'
        'operation_type,payload_json,expected_cloud_revision,local_revision,'
        'created_at_ms,updated_at_ms) '
        "VALUES (?,?,?,'admission',?,'admission.save_draft',?,?,?,?,?)",
        [op,draft.schoolId,draft.campusId,localId,payload,cloudRev,rev,now,now],
      );
      await _event(op,draft.schoolId,draft.campusId,'queued',now);
      return QueuedAdmissionDraft(op,localId,rev);
    });
  }

  Future<void> _event(String op,String school,String campus,String kind,
      int now,[String? code]) async {
    await db.customStatement(
      'INSERT INTO local_outbox_events '
      '(operation_id,school_id,campus_id,event_type,event_at_ms,error_code) '
      'VALUES (?,?,?,?,?,?)',
      [op,school,campus,kind,now,code],
    );
  }

  /// Lease the oldest not-yet-acknowledged operation. An unexpired lease,
  /// retry delay or conflict blocks later operations (no reordering).
  /// Expired leases may be reclaimed with the SAME op UUID and payload.
  Future<LeasedOfflineOperation?> claimNext({int leaseMs=30000}) async {
    if (leaseMs < 1000 || leaseMs > 300000) {
      throw ArgumentError.value(leaseMs,'leaseMs');
    }
    return db.transaction(() async {
      final row = await db.customSelect(
        "SELECT * FROM local_outbox_operations WHERE status<>'acked' "
        'ORDER BY sequence_no LIMIT 1',
      ).getSingleOrNull();
      if (row == null) return null;
      final status = row.read<String>('status');
      final now = _clock();
      if (status == 'conflict' ||
          (status == 'sending' &&
            (row.readNullable<int>('lease_until_ms') ?? 0) > now) ||
          (status == 'pending' &&
            (row.readNullable<int>('retry_after_ms') ?? 0) > now)) {
        return null;
      }
      final op = row.read<String>('operation_id');
      final school = row.read<String>('school_id');
      final campus = row.read<String>('campus_id');
      final token = _newId();
      _assertUuid(token);
      await db.customStatement(
        "UPDATE local_outbox_operations SET status='sending',"
        'lease_token=?,lease_until_ms=?,retry_after_ms=NULL,'
        'attempt_count=attempt_count+1,updated_at_ms=? '
        'WHERE operation_id=?',
        [token,now+leaseMs,now,op],
      );
      await _event(op,school,campus,'claimed',now);
      return LeasedOfflineOperation(
        operationId: op, leaseToken: token,
        localApplicationId: row.read<String>('aggregate_id'),
        payloadJson: row.read<String>('payload_json'),
        expectedCloudRevision: row.readNullable<int>('expected_cloud_revision'),
        localRevision: row.read<int>('local_revision'),
        attemptCount: row.read<int>('attempt_count') + 1,
      );
    });
  }

  Future<(String,String)> _validateLease(String op,String token) async {
    _assertUuid(op);
    _assertUuid(token);
    final row = await db.customSelect(
      'SELECT school_id,campus_id,status,lease_token,lease_until_ms '
      'FROM local_outbox_operations WHERE operation_id=?',
      variables: [Variable.withString(op)],
    ).getSingleOrNull();
    if (row == null || row.read<String>('status') != 'sending' ||
        row.readNullable<String>('lease_token') != token ||
        (row.readNullable<int>('lease_until_ms') ?? 0) <= _clock()) {
      throw StateError('Expired, stale or invalid operation lease');
    }
    return (row.read<String>('school_id'),row.read<String>('campus_id'));
  }

  /// Transport errors requeue the SAME UUID and payload, with backoff.
  Future<void> releaseForRetry({
    required String operationId,
    required String leaseToken,
    required String errorCode,
    int delayMs=5000,
  }) async {
    _assertErrorCode(errorCode);
    if (delayMs < 0 || delayMs > 86400000) throw ArgumentError('Invalid backoff');
    await db.transaction(() async {
      final (school,campus) = await _validateLease(operationId,leaseToken);
      final now = _clock();
      await db.customStatement(
        "UPDATE local_outbox_operations SET status='pending',"
        'lease_token=NULL,lease_until_ms=NULL,retry_after_ms=?,'
        'last_error_code=?,updated_at_ms=? WHERE operation_id=?',
        [now+delayMs,errorCode,now,operationId],
      );
      await _event(operationId,school,campus,'released',now,errorCode);
    });
  }

  /// Only the future authenticated sync handler may call this after a
  /// verified server acknowledgement of the SAME UUID. No records deleted.
  Future<void> acknowledgeFromServer({
    required String operationId,
    required String leaseToken,
    required int serverRevision,
  }) async {
    if (serverRevision < 0) throw ArgumentError('Invalid server revision');
    await db.transaction(() async {
      final (school,campus) = await _validateLease(operationId,leaseToken);
      final now = _clock();
      await db.customStatement(
        "UPDATE local_outbox_operations SET status='acked',"
        'lease_token=NULL,lease_until_ms=NULL,server_revision=?,'
        'acknowledged_at_ms=?,updated_at_ms=?,last_error_code=NULL '
        'WHERE operation_id=?',
        [serverRevision,now,now,operationId],
      );
      await _event(operationId,school,campus,'acked',now);
      // Do not clear local_admissions.locally_edited here. The backend
      // receipt, cloud application ID and all dependent draft revisions
      // must be reconciled atomically in D04-T03 / D04-T04.
    });
  }

  Future<void> flagConflict({
    required String operationId,
    required String leaseToken,
    required String errorCode,
  }) async {
    _assertErrorCode(errorCode);
    await db.transaction(() async {
      final (school,campus) = await _validateLease(operationId,leaseToken);
      final now = _clock();
      await db.customStatement(
        "UPDATE local_outbox_operations SET status='conflict',"
        'lease_token=NULL,lease_until_ms=NULL,retry_after_ms=NULL,'
        'last_error_code=?,updated_at_ms=? WHERE operation_id=?',
        [errorCode,now,operationId],
      );
      await _event(operationId,school,campus,'conflict',now,errorCode);
    });
  }

  Future<int> outstandingCount() async {
    final row = await db.customSelect(
      "SELECT COUNT(*) AS n FROM local_outbox_operations WHERE status<>'acked'",
    ).getSingle();
    return row.read<int>('n');
  }
}
