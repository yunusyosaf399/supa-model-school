import 'package:supabase_flutter/supabase_flutter.dart';

import 'fee_monthly_repository.dart';
import 'fee_detailed_statement.dart';

int feeInt(Object? x) {
  if (x is num) return x.toInt();
  if (x is String) return int.parse(x);
  throw const FormatException('Invalid fee amount');
}

List<Map<String, dynamic>> feeRows(Object? x) {
  if (x is! List) throw const FormatException('Invalid fee response');
  return List.unmodifiable([
    for (final row in x) Map<String, dynamic>.from(row as Map),
  ]);
}

class FeeYearChoice {
  const FeeYearChoice(this.id, this.label, this.active);
  final String id, label;
  final bool active;

  factory FeeYearChoice.fromJson(Map<String, dynamic> row) =>
      FeeYearChoice(row['id'] as String, row['label'] as String,
          row['active'] == true);
}

class FeePaymentCategory {
  const FeePaymentCategory({
    required this.id, required this.code, required this.name,
    required this.frequency, required this.active,
  });

  final String id, code, name, frequency;
  final bool active;

  factory FeePaymentCategory.fromJson(Map<String, dynamic> row) =>
      FeePaymentCategory(
        id: row['id'] as String, code: row['code'] as String,
        name: row['name'] as String, frequency: row['frequency'] as String,
        active: row['active'] == true,
      );
}

class FeePaymentCharge {
  const FeePaymentCharge({
    required this.id, required this.categoryId,
    required this.categoryName, required this.frequency,
    required this.month, required this.dueOn,
    required this.netMinor, required this.paidMinor,
    required this.outstandingMinor,
  });
  final String id, categoryId, categoryName, frequency, month, dueOn;
  final int netMinor, paidMinor, outstandingMinor;

  factory FeePaymentCharge.fromJson(Map<String, dynamic> row) =>
      FeePaymentCharge(
        id: row['charge_id'] as String,
        categoryId: row['category_id'] as String,
        categoryName: row['category'] as String,
        frequency: row['frequency'] as String,
        month: row['month'].toString(),
        dueOn: row['due_on'].toString(),
        netMinor: feeInt(row['net_minor']),
        paidMinor: feeInt(row['paid_minor']),
        outstandingMinor: feeInt(row['outstanding_minor']),
      );
}

class FeePaymentStudent {
  const FeePaymentStudent({
    required this.id, required this.name, required this.registration,
    required this.classId, required this.className,
    required this.sectionId, required this.sectionName,
    required this.charges,
  });

  final String id, name, registration, classId, className;
  final String? sectionId, sectionName;
  final List<FeePaymentCharge> charges;

  int get outstandingMinor => charges.fold<int>(0,
      (sum, c) => sum + (c.outstandingMinor > 0 ? c.outstandingMinor : 0));

  factory FeePaymentStudent.fromJson(Map<String, dynamic> row) =>
      FeePaymentStudent(
        id: row['student_id'] as String,
        name: row['name'] as String,
        registration: row['registration'] as String,
        classId: row['class_id'] as String,
        className: row['class_name'] as String,
        sectionId: row['section_id'] as String?,
        sectionName: row['section_name'] as String?,
        charges: List.unmodifiable([
          for (final charge in feeRows(row['charges']))
            FeePaymentCharge.fromJson(charge),
        ]),
      );
}

class FeePaymentWorkspace {
  const FeePaymentWorkspace({
    required this.schoolId, required this.campusId, required this.yearId,
    required this.yearLabel, required this.currency, required this.canCollect,
    required this.years, required this.categories, required this.students,
  });

  final String schoolId, campusId, yearId, yearLabel, currency;
  final bool canCollect;
  final List<FeeYearChoice> years;
  final List<FeePaymentCategory> categories;
  final List<FeePaymentStudent> students;

  factory FeePaymentWorkspace.fromJson(Map<String, dynamic> json) =>
      FeePaymentWorkspace(
        schoolId: json['school_id'] as String,
        campusId: json['campus_id'] as String,
        yearId: json['year_id'] as String,
        yearLabel: json['year_label'] as String,
        currency: json['currency'] as String,
        canCollect: json['can_collect'] == true,
        years: List.unmodifiable([
          for (final row in feeRows(json['years']))
            FeeYearChoice.fromJson(row),
        ]),
        categories: List.unmodifiable([
          for (final row in feeRows(json['categories']))
            FeePaymentCategory.fromJson(row),
        ]),
        students: List.unmodifiable([
          for (final row in feeRows(json['students']))
            FeePaymentStudent.fromJson(row),
        ]),
      );
}

class QuickPayAllocation {
  const QuickPayAllocation({required this.chargeId, required this.amountMinor});
  final String chargeId;
  final int amountMinor;

  Map<String, Object> toJson() =>
      {'charge_id': chargeId, 'amount_minor': amountMinor};
}

/// Preview based on posted, unpaid invoices only. The server repeats the
/// balance and ownership checks under a lock before recording money.
class QuickPayPlanner {
  static List<QuickPayAllocation> suggest(
    FeePaymentStudent student, Set<String> selectedCategories,
    int receivedMinor,
  ) {
    if (receivedMinor <= 0) throw const FormatException('Enter an amount.');
    if (selectedCategories.isEmpty) {
      throw const FormatException('Select at least one fee category.');
    }
    final eligible = student.charges.where((charge) =>
      selectedCategories.contains(charge.categoryId) &&
      charge.outstandingMinor > 0).toList()
      ..sort((a, b) {
        final due = a.dueOn.compareTo(b.dueOn);
        if (due != 0) return due;
        final month = a.month.compareTo(b.month);
        if (month != 0) return month;
        final category = a.categoryName.compareTo(b.categoryName);
        return category != 0 ? category : a.id.compareTo(b.id);
      });
    var remaining = receivedMinor;
    final result = <QuickPayAllocation>[];
    for (final charge in eligible) {
      if (remaining <= 0) break;
      final take = remaining < charge.outstandingMinor
        ? remaining : charge.outstandingMinor;
      result.add(QuickPayAllocation(chargeId: charge.id, amountMinor: take));
      remaining -= take;
    }
    if (remaining > 0) {
      throw FormatException('Selected categories have insufficient posted '
        'dues. Remaining: $remaining minor currency units.');
    }
    return List.unmodifiable(result);
  }

  static void validate(
    FeePaymentStudent student, int amountMinor,
    List<QuickPayAllocation> allocations,
  ) {
    if (amountMinor <= 0 || allocations.isEmpty) {
      throw const FormatException('A positive payment is required.');
    }
    final known = {for (final charge in student.charges) charge.id: charge};
    final seen = <String>{};
    var total = 0;
    for (final allocation in allocations) {
      final charge = known[allocation.chargeId];
      if (!seen.add(allocation.chargeId) || charge == null ||
        allocation.amountMinor <= 0 ||
        allocation.amountMinor > charge.outstandingMinor) {
        throw const FormatException(
          'Each allocation must be unique and within its outstanding fee.');
      }
      total += allocation.amountMinor;
    }
    if (total != amountMinor) {
      throw const FormatException('Allocated amount must equal payment.');
    }
  }
}

class QuickPayReceipt {
  const QuickPayReceipt(this.id, this.number, this.amountMinor);
  final String id, number;
  final int amountMinor;
}

abstract class FeePaymentRepository {
  const FeePaymentRepository();

  /// Read-only, campus-authorized school-year charges and receipt allocations.
  Future<FeeDetailedStudentLedger> detailedLedger({
    required String schoolId,required String campusId,
    required String yearId,required String studentId,
  });


  Future<FeePaymentWorkspace> workspace({
    required String schoolId, required String campusId, String? yearId,
  });

  Future<QuickPayReceipt> collect({
    required String schoolId, required String campusId,
    required String yearId, required String studentId,
    required int amountMinor, required String method,
    String? bankReference, required String operationId,
    required List<QuickPayAllocation> allocations,
  });
}

class SupabaseFeePaymentRepository implements FeePaymentRepository {
  const SupabaseFeePaymentRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> _rpc(
      String name, Map<String, Object?> params) async {
    if (client.auth.currentSession == null) {
      throw StateError('Signed-in school account required');
    }
    final data = await client.rpc(name, params: params);
    if (data is! Map) throw StateError('Invalid payment response');
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<FeeDetailedStudentLedger> detailedLedger({
    required String schoolId,required String campusId,
    required String yearId,required String studentId,
  }) async {
    final response=await _rpc('fee_student_detailed_ledger',{
      'p_school':schoolId,'p_campus':campusId,
      'p_year':yearId,'p_student':studentId});
    final value=FeeDetailedStudentLedger.fromJson(response);
    if(value.schoolId!=schoolId||value.campusId!=campusId||
       value.yearId!=yearId||value.studentId!=studentId){
      throw StateError('Statement returned another school, campus or student');
    }
    return value;
  }

  @override
  Future<FeePaymentWorkspace> workspace({
    required String schoolId, required String campusId, String? yearId,
  }) async {
    final row = await _rpc('fee_payment_workspace', {
      'p_school': schoolId, 'p_campus': campusId, 'p_year': yearId,
    });
    final result = FeePaymentWorkspace.fromJson(row);
    if (result.schoolId != schoolId || result.campusId != campusId ||
        (yearId != null && result.yearId != yearId)) {
      throw StateError('Fee workspace returned another school/campus/year');
    }
    return result;
  }

  @override
  Future<QuickPayReceipt> collect({
    required String schoolId, required String campusId,
    required String yearId, required String studentId,
    required int amountMinor, required String method,
    String? bankReference, required String operationId,
    required List<QuickPayAllocation> allocations,
  }) async {
    if (amountMinor <= 0 || !{'cash', 'bank'}.contains(method) ||
        allocations.fold<int>(0, (sum, row) => sum + row.amountMinor) !=
          amountMinor) {
      throw const FormatException('Invalid Quick Pay amount or allocations.');
    }
    final value = await _rpc('fee_quick_pay_post', {
      'p_school': schoolId, 'p_campus': campusId,
      'p_year': yearId, 'p_student': studentId,
      'p_amount_minor': amountMinor, 'p_method': method,
      'p_bank_reference': method == 'bank' ? bankReference : null,
      'p_lines': [for (final a in allocations) a.toJson()],
      'p_operation': operationId,
    });
    if (value['saved'] != true ||
        value['receipt_no'] is! String ||
        feeInt(value['amount_minor']) != amountMinor) {
      throw StateError('Payment was not confirmed; retry the same operation.');
    }
    return QuickPayReceipt(
      value['receipt_id'] as String,
      value['receipt_no'] as String, amountMinor,
    );
  }
}
