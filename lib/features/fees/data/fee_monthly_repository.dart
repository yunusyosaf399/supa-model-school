import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Financial writes only use Owner-authorized RPCs. The client never writes
/// immutable charges, receipts, discounts or allocations directly.
class FeeMonth {
  static String normalize(DateTime date) =>
    date.year.toString().padLeft(4, '0') + '-' +
    date.month.toString().padLeft(2, '0') + '-01';

  static DateTime parse(String month) => DateTime.parse(month.substring(0, 10));

  static String label(String month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final d = parse(month);
    return names[d.month - 1] + ' ' + d.year.toString();
  }
}

class FeeOperationId {
  static String create() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return h.substring(0, 8) + '-' + h.substring(8, 12) + '-' +
      h.substring(12, 16) + '-' + h.substring(16, 20) + '-' + h.substring(20);
  }
}

int _minor(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.parse(value);
  throw const FormatException('Invalid minor currency value');
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) throw const FormatException('Invalid financial rows');
  return List.unmodifiable([
    for (final item in value)
      Map<String, dynamic>.from(item as Map),
  ]);
}

class FeeLedgerStudent {
  const FeeLedgerStudent({
    required this.id, required this.name, required this.registration,
    required this.className, required this.active,
    required this.chargedMinor, required this.paidMinor,
    required this.outstandingMinor,
  });
  final String id, name, registration, className;
  final bool active;
  final int chargedMinor, paidMinor, outstandingMinor;

  factory FeeLedgerStudent.fromJson(Map<String, dynamic> row) =>
    FeeLedgerStudent(
      id: row['id'] as String,
      name: row['name'] as String,
      registration: row['registration'] as String,
      className: row['class_name'] as String,
      active: row['active'] == true,
      chargedMinor: _minor(row['charged_minor']),
      paidMinor: _minor(row['paid_minor']),
      outstandingMinor: _minor(row['outstanding_minor']),
    );
}

class FeeLedgerCategory {
  const FeeLedgerCategory({
    required this.id, required this.code, required this.name,
    required this.frequency, required this.discountable,
  });
  final String id, code, name, frequency;
  final bool discountable;
  factory FeeLedgerCategory.fromJson(Map<String, dynamic> row) =>
    FeeLedgerCategory(
      id: row['id'] as String, code: row['code'] as String,
      name: row['name'] as String,
      frequency: row['frequency'] as String,
      discountable: row['discountable'] == true,
    );
}

class FeeReceipt {
  const FeeReceipt({
    required this.id, required this.number,
    required this.studentId, required this.amountMinor,
    required this.method, required this.issuedAt,
    this.studentName = '', this.bankReference,
  });
  final String id, number, studentId, studentName, method, issuedAt;
  final String? bankReference;
  final int amountMinor;
  factory FeeReceipt.fromJson(Map<String, dynamic> row) => FeeReceipt(
    id: row['id'] as String,
    number: row['number'] as String,
    studentId: row['student_id'] as String? ?? '',
    studentName: row['name'] as String? ?? '',
    amountMinor: _minor(row['amount_minor']),
    method: row['method'] as String,
    issuedAt: row['issued_at'].toString(),
    bankReference: row['bank_reference'] as String?,
  );
}

class FeeChargeLine {
  const FeeChargeLine({
    required this.id, required this.month, required this.category,
    required this.grossMinor, required this.discountMinor,
    required this.netMinor, required this.paidMinor,
    required this.dueOn,
  });
  final String id, month, category, dueOn;
  final int grossMinor, discountMinor, netMinor, paidMinor;
  int get outstandingMinor => netMinor - paidMinor;
  factory FeeChargeLine.fromJson(Map<String, dynamic> row) => FeeChargeLine(
    id: row['id'] as String, month: row['month'].toString(),
    category: row['category'] as String,
    grossMinor: _minor(row['gross_minor']),
    discountMinor: _minor(row['discount_minor']),
    netMinor: _minor(row['net_minor']),
    paidMinor: _minor(row['paid_minor']),
    dueOn: row['due_on'].toString(),
  );
}

class FeeStudentDiscount {
  const FeeStudentDiscount({
    required this.categoryName, required this.kind,
    required this.startMonth, required this.reason,
    this.percentBps, this.fixedMinor,
  });
  final String categoryName, kind, startMonth, reason;
  final int? percentBps, fixedMinor;
  factory FeeStudentDiscount.fromJson(Map<String, dynamic> row) =>
    FeeStudentDiscount(
      categoryName: row['category'] as String,
      kind: row['kind'] as String,
      startMonth: row['start_month'].toString(),
      reason: row['reason'] as String,
      percentBps: row['percent_bps'] == null
        ? null : _minor(row['percent_bps']),
      fixedMinor: row['fixed_minor'] == null
        ? null : _minor(row['fixed_minor']),
    );
}

class FeeStudentStatement {
  const FeeStudentStatement({
    required this.studentId,
    required this.charges, required this.receipts, required this.discounts,
  });
  final String studentId;
  final List<FeeChargeLine> charges;
  final List<FeeReceipt> receipts;
  final List<FeeStudentDiscount> discounts;
  int get outstandingMinor =>
    charges.fold<int>(0, (sum, c) => sum + c.outstandingMinor);

  factory FeeStudentStatement.fromJson(Map<String, dynamic> data) =>
    FeeStudentStatement(
      studentId: data['student_id'] as String,
      charges: List.unmodifiable([
        for (final c in _maps(data['charges'])) FeeChargeLine.fromJson(c),
      ]),
      receipts: List.unmodifiable([
        for (final r in _maps(data['receipts'])) FeeReceipt.fromJson(r),
      ]),
      discounts: List.unmodifiable([
        for (final d in _maps(data['discounts']))
          FeeStudentDiscount.fromJson(d),
      ]),
    );
}

class FeeMonthlyLedger {
  const FeeMonthlyLedger({
    required this.schoolId, required this.campusId,
    required this.yearId, required this.month,
    required this.yearLabel, required this.currency,
    required this.chargedMinor, required this.paidMinor,
    required this.outstandingMinor, required this.receivedMinor,
    required this.students, required this.categories,
    required this.recentReceipts,
  });
  final String schoolId, campusId, yearId, month, yearLabel, currency;
  final int chargedMinor, paidMinor, outstandingMinor, receivedMinor;
  final List<FeeLedgerStudent> students;
  final List<FeeLedgerCategory> categories;
  final List<FeeReceipt> recentReceipts;

  factory FeeMonthlyLedger.fromJson(Map<String, dynamic> data) =>
    FeeMonthlyLedger(
      schoolId: data['school_id'] as String,
      campusId: data['campus_id'] as String,
      yearId: data['year_id'] as String,
      month: data['month'].toString(),
      yearLabel: data['year_label'] as String,
      currency: data['currency'] as String,
      chargedMinor: _minor(data['charged_minor']),
      paidMinor: _minor(data['paid_minor']),
      outstandingMinor: _minor(data['outstanding_minor']),
      receivedMinor: _minor(data['received_minor']),
      students: List.unmodifiable([
        for (final row in _maps(data['students']))
          FeeLedgerStudent.fromJson(row),
      ]),
      categories: List.unmodifiable([
        for (final row in _maps(data['categories']))
          FeeLedgerCategory.fromJson(row),
      ]),
      recentReceipts: List.unmodifiable([
        for (final row in _maps(data['recent_receipts']))
          FeeReceipt.fromJson(row),
      ]),
    );
}

class FeeBillResult {
  const FeeBillResult(this.addedCharges);
  final int addedCharges;
}

class FeeReceiptResult {
  const FeeReceiptResult(this.receiptId, this.number, this.amountMinor);
  final String receiptId, number;
  final int amountMinor;
}

abstract class FeeMonthlyRepository {
  const FeeMonthlyRepository();

  Future<FeeMonthlyLedger> load({
    required String schoolId, required String campusId,
    required String yearId, required String month,
  });
  Future<FeeStudentStatement> statement({
    required String schoolId, required String campusId,
    required String yearId, required String studentId,
  });
  Future<FeeBillResult> generate({
    required String schoolId, required String campusId,
    required String yearId, required String month, required String operationId,
  });
  Future<FeeReceiptResult> collect({
    required String schoolId, required String campusId, required String yearId,
    required String studentId, required int amountMinor,
    required String method, String? bankReference, required String operationId,
  });
  Future<void> grantDiscount({
    required String schoolId, required String campusId, required String yearId,
    required String studentId, required String categoryId, required String kind,
    int? percentBps, int? fixedMinor,
    required String startMonth, required String reason,
  });
}

class SupabaseFeeMonthlyRepository implements FeeMonthlyRepository {
  const SupabaseFeeMonthlyRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> _rpc(
    String name, Map<String, Object?> params,
  ) async {
    if (client.auth.currentSession == null) {
      throw StateError('Verified school Owner sign-in required');
    }
    final response = await client.rpc(name, params: params);
    if (response is! Map) throw StateError(name + ' returned invalid data');
    return Map<String, dynamic>.from(response);
  }

  @override
  Future<FeeMonthlyLedger> load({
    required String schoolId, required String campusId,
    required String yearId, required String month,
  }) async {
    final data = await _rpc('owner_fee_monthly_ledger', {
      'p_school': schoolId, 'p_campus': campusId,
      'p_year': yearId, 'p_month': month,
    });
    final ledger = FeeMonthlyLedger.fromJson(data);
    if (ledger.schoolId != schoolId || ledger.campusId != campusId ||
      ledger.yearId != yearId || ledger.month != month) {
      throw StateError('Finance data for an unexpected school/campus/month');
    }
    return ledger;
  }

  @override
  Future<FeeStudentStatement> statement({
    required String schoolId, required String campusId,
    required String yearId, required String studentId,
  }) async {
    final data = await _rpc('owner_fee_student_statement', {
      'p_school': schoolId, 'p_campus': campusId,
      'p_year': yearId, 'p_student': studentId,
    });
    final statement = FeeStudentStatement.fromJson(data);
    if (statement.studentId != studentId) {
      throw StateError('Unexpected student statement');
    }
    return statement;
  }

  @override
  Future<FeeBillResult> generate({
    required String schoolId, required String campusId,
    required String yearId, required String month, required String operationId,
  }) async {
    final data = await _rpc('owner_generate_monthly_bills', {
      'p_school': schoolId, 'p_campus': campusId,
      'p_year': yearId, 'p_month': month, 'p_operation': operationId,
    });
    if (data['saved'] != true || data['added_charges'] is! num) {
      throw StateError('Bill generation not confirmed; retry same operation');
    }
    return FeeBillResult((data['added_charges'] as num).toInt());
  }

  @override
  Future<FeeReceiptResult> collect({
    required String schoolId, required String campusId, required String yearId,
    required String studentId, required int amountMinor,
    required String method, String? bankReference, required String operationId,
  }) async {
    if (amountMinor <= 0 || !{'cash', 'bank'}.contains(method)) {
      throw const FormatException('Invalid payment details');
    }
    final data = await _rpc('owner_collect_student_payment', {
      'p_school': schoolId, 'p_campus': campusId, 'p_year': yearId,
      'p_student': studentId, 'p_amount_minor': amountMinor,
      'p_method': method, 'p_bank_reference': bankReference,
      'p_operation': operationId,
    });
    if (data['saved'] != true || data['receipt_no'] is! String ||
        _minor(data['amount_minor']) != amountMinor) {
      throw StateError('Payment not confirmed; retry same operation');
    }
    return FeeReceiptResult(
      data['receipt_id'] as String, data['receipt_no'] as String, amountMinor);
  }

  @override
  Future<void> grantDiscount({
    required String schoolId, required String campusId, required String yearId,
    required String studentId, required String categoryId, required String kind,
    int? percentBps, int? fixedMinor,
    required String startMonth, required String reason,
  }) async {
    final data = await _rpc('owner_set_student_fee_discount', {
      'p_school': schoolId, 'p_campus': campusId, 'p_year': yearId,
      'p_student': studentId, 'p_category': categoryId,
      'p_kind': kind, 'p_percent_bps': percentBps,
      'p_fixed_minor': fixedMinor, 'p_start_month': startMonth,
      'p_reason': reason.trim(),
    });
    if (data['saved'] != true || data['id'] is! String) {
      throw StateError('Scholarship save not confirmed');
    }
  }
}
