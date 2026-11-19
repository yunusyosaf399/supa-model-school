import 'package:supabase_flutter/supabase_flutter.dart';

class FeeCategory {
  const FeeCategory({
    required this.id, required this.code, required this.name,
    required this.frequency, required this.discountable, required this.active,
  });
  final String id, code, name, frequency;
  final bool discountable, active;

  factory FeeCategory.fromJson(Map<String, dynamic> data) => FeeCategory(
    id: data['id'] as String,
    code: data['code'] as String,
    name: data['name'] as String,
    frequency: data['frequency'] as String,
    discountable: data['discountable'] == true,
    active: data['active'] == true,
  );
}

class FeePlanLine {
  const FeePlanLine({
    required this.categoryId, required this.amountMinor,
    this.optional = false,
  });
  final String categoryId;
  final int amountMinor;
  final bool optional;

  factory FeePlanLine.fromJson(Map<String, dynamic> data) => FeePlanLine(
    categoryId: data['category_id'] as String,
    amountMinor: (data['amount_minor'] as num).toInt(),
    optional: data['optional'] == true,
  );

  Map<String, Object> toJson() => {
    'category_id': categoryId,
    'amount_minor': amountMinor,
    'optional': optional,
  };
}

class ClassFeePlan {
  const ClassFeePlan({
    required this.id, required this.name, required this.version,
    required this.status, required this.effectiveFrom, required this.lines,
  });
  final String id, name, status, effectiveFrom;
  final int version;
  final List<FeePlanLine> lines;

  factory ClassFeePlan.fromJson(Map<String, dynamic> data) {
    final raw = data['items'];
    return ClassFeePlan(
      id: data['id'] as String,
      name: data['name'] as String,
      version: (data['version'] as num).toInt(),
      status: data['status'] as String,
      effectiveFrom: data['effective_from'] as String,
      lines: List.unmodifiable([
        if (raw is List)
          for (final item in raw)
            FeePlanLine.fromJson(Map<String, dynamic>.from(item as Map)),
      ]),
    );
  }
}

class ClassFeeSummary {
  const ClassFeeSummary({
    required this.id, required this.name, required this.sortOrder,
    this.plan,
  });
  final String id, name;
  final int sortOrder;
  final ClassFeePlan? plan;

  factory ClassFeeSummary.fromJson(Map<String, dynamic> data) =>
    ClassFeeSummary(
      id: data['id'] as String,
      name: data['name'] as String,
      sortOrder: (data['sort_order'] as num).toInt(),
      plan: data['plan'] is Map
        ? ClassFeePlan.fromJson(Map<String, dynamic>.from(data['plan'] as Map))
        : null,
    );
}

class FeeSetupSnapshot {
  const FeeSetupSnapshot({
    required this.schoolId, required this.campusId, required this.yearId,
    required this.yearLabel, required this.currency,
    required this.categories, required this.classes,
  });
  final String schoolId, campusId, yearId, yearLabel, currency;
  final List<FeeCategory> categories;
  final List<ClassFeeSummary> classes;

  factory FeeSetupSnapshot.fromJson(Map<String, dynamic> data) {
    final categories = data['categories'];
    final classes = data['classes'];
    if (categories is! List || classes is! List) {
      throw const FormatException('Invalid school fee setup response');
    }
    return FeeSetupSnapshot(
      schoolId: data['school_id'] as String,
      campusId: data['campus_id'] as String,
      yearId: data['year_id'] as String,
      yearLabel: data['year_label'] as String,
      currency: data['currency'] as String,
      categories: List.unmodifiable(categories.map((item) =>
        FeeCategory.fromJson(Map<String, dynamic>.from(item as Map)))),
      classes: List.unmodifiable(classes.map((item) =>
        ClassFeeSummary.fromJson(Map<String, dynamic>.from(item as Map)))),
    );
  }
}


class StudentFeeRateStudent {
  const StudentFeeRateStudent({required this.id,required this.name,
    required this.registration,required this.classId,required this.className,
    this.sectionName});
  final String id,name,registration,classId,className;
  final String? sectionName;
  factory StudentFeeRateStudent.fromJson(Map<String,dynamic> x) =>
    StudentFeeRateStudent(id:x['id'] as String,name:x['name'] as String,
      registration:x['registration'] as String,classId:x['class_id'] as String,
      className:x['class_name'] as String,sectionName:x['section_name'] as String?);
}
class StudentFeeRateCategory {
  const StudentFeeRateCategory({required this.id,required this.name,
    required this.code,required this.frequency});
  final String id,name,code,frequency;
  factory StudentFeeRateCategory.fromJson(Map<String,dynamic> x) =>
    StudentFeeRateCategory(id:x['id'] as String,name:x['name'] as String,
      code:x['code'] as String,frequency:x['frequency'] as String);
}
class StudentFeeRateRule {
  const StudentFeeRateRule({required this.id,required this.studentId,
    required this.categoryId,required this.kind,required this.startMonth,
    required this.reason,required this.active,this.amountMinor,this.endMonth});
  final String id,studentId,categoryId,kind,startMonth,reason;
  final int? amountMinor;
  final String? endMonth;
  final bool active;
  factory StudentFeeRateRule.fromJson(Map<String,dynamic> x) =>
    StudentFeeRateRule(id:x['id'] as String,studentId:x['student_id'] as String,
      categoryId:x['category_id'] as String,kind:x['kind'] as String,
      amountMinor:(x['amount_minor'] as num?)?.toInt(),
      startMonth:x['start_month'] as String,endMonth:x['end_month'] as String?,
      reason:x['reason'] as String,active:x['active']==true);
}
class StudentFeeRatesSnapshot {
  const StudentFeeRatesSnapshot({required this.schoolId,required this.campusId,
    required this.yearId,required this.currency,required this.students,
    required this.categories,required this.rules});
  final String schoolId,campusId,yearId,currency;
  final List<StudentFeeRateStudent> students;
  final List<StudentFeeRateCategory> categories;
  final List<StudentFeeRateRule> rules;
  factory StudentFeeRatesSnapshot.fromJson(Map<String,dynamic> x) {
    List<Map<String,dynamic>> rows(Object? v) {
      if(v is! List)throw const FormatException('Invalid rate snapshot');
      return [for(final y in v)Map<String,dynamic>.from(y as Map)];
    }
    return StudentFeeRatesSnapshot(
      schoolId:x['school_id'] as String,campusId:x['campus_id'] as String,
      yearId:x['year_id'] as String,currency:x['currency'] as String,
      students:List.unmodifiable([
        for(final y in rows(x['students']))StudentFeeRateStudent.fromJson(y)]),
      categories:List.unmodifiable([
        for(final y in rows(x['categories']))StudentFeeRateCategory.fromJson(y)]),
      rules:List.unmodifiable([
        for(final y in rows(x['rules']))StudentFeeRateRule.fromJson(y)]));
  }
}

abstract class FeeSetupRepository {
  const FeeSetupRepository();

  Future<StudentFeeRatesSnapshot> loadStudentRates({
    required String schoolId,required String campusId,required String yearId,
  }) => throw UnsupportedError('Student rate setup unavailable');

  Future<void> saveStudentRate({
    required String schoolId,required String campusId,required String yearId,
    required String studentId,required String categoryId,required String kind,
    int? amountMinor,required String startMonth,String? endMonth,
    required String reason,required String operationId,
  }) => throw UnsupportedError('Student rate changes unavailable');


  Future<FeeSetupSnapshot> load({
    required String schoolId, required String campusId,
    required String academicYearId,
  });

  Future<void> createCategory({
    required String schoolId, required String code, required String name,
    required String frequency, required bool discountable,
  });

  Future<void> saveClassPlan({
    required String schoolId, required String campusId,
    required String academicYearId, required String classId,
    required String name, required List<FeePlanLine> items,
  });
}

class SupabaseFeeSetupRepository implements FeeSetupRepository {
  const SupabaseFeeSetupRepository(this.client);
  final SupabaseClient client;

  @override
  Future<StudentFeeRatesSnapshot> loadStudentRates({
    required String schoolId,required String campusId,required String yearId,
  }) async {
    _requireSession();
    final response=await client.rpc('owner_student_fee_rates_snapshot',params:{
      'p_school':schoolId,'p_campus':campusId,'p_year':yearId});
    if(response is! Map)throw StateError('Invalid student rates response');
    final result=StudentFeeRatesSnapshot.fromJson(Map<String,dynamic>.from(response));
    if(result.schoolId!=schoolId||result.campusId!=campusId||
       result.yearId!=yearId) {
      throw StateError('Fee rates returned from an unrelated school/year');
    }
    return result;
  }

  @override
  Future<void> saveStudentRate({
    required String schoolId,required String campusId,required String yearId,
    required String studentId,required String categoryId,required String kind,
    int? amountMinor,required String startMonth,String? endMonth,
    required String reason,required String operationId,
  }) async {
    _requireSession();
    if(!{'override','exempt','standard'}.contains(kind)||
      (kind=='override'&&(amountMinor==null||amountMinor<=0))||
      (kind!='override'&&amountMinor!=null)||
      reason.trim().length<4||reason.trim().length>500||
      !RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(startMonth)||
      (endMonth!=null&&
       !RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(endMonth))) {
      throw const FormatException('Invalid individual fee rate terms');
    }
    final response=await client.rpc('owner_set_student_fee_rate',params:{
      'p_school':schoolId,'p_campus':campusId,'p_year':yearId,
      'p_student':studentId,'p_category':categoryId,
      'p_kind':kind,'p_amount_minor':amountMinor,
      'p_start_month':startMonth,'p_end_month':endMonth,
      'p_reason':reason.trim(),'p_operation':operationId,
    });
    if(response is! Map || response['saved']!=true ||
       response['rate_id'] is! String||response['student_id']!=studentId||
       response['category_id']!=categoryId||response['kind']!=kind){
      throw StateError('Rate change not confirmed; retry same operation');
    }
  }


  void _requireSession() {
    if (client.auth.currentSession == null) {
      throw StateError('Verified school Owner sign-in required');
    }
  }

  @override
  Future<FeeSetupSnapshot> load({
    required String schoolId, required String campusId,
    required String academicYearId,
  }) async {
    _requireSession();
    final response = await client.rpc('owner_fee_setup_snapshot', params: {
      'p_school': schoolId, 'p_campus': campusId, 'p_year': academicYearId,
    });
    if (response is! Map) throw StateError('Invalid fee setup response');
    final snapshot = FeeSetupSnapshot.fromJson(Map<String, dynamic>.from(response));
    if (snapshot.schoolId != schoolId || snapshot.campusId != campusId ||
        snapshot.yearId != academicYearId) {
      throw StateError('Fee setup returned a different school or campus');
    }
    return snapshot;
  }

  @override
  Future<void> createCategory({
    required String schoolId, required String code, required String name,
    required String frequency, required bool discountable,
  }) async {
    _requireSession();
    final response = await client.rpc('owner_create_fee_category', params: {
      'p_school': schoolId,
      'p_code': code.trim().toUpperCase(),
      'p_name': name.trim(),
      'p_frequency': frequency,
      'p_discountable': discountable,
    });
    if (response is! Map || response['saved'] != true ||
        response['code'] != code.trim().toUpperCase()) {
      throw StateError('Category save not confirmed. Refresh before retrying.');
    }
  }

  @override
  Future<void> saveClassPlan({
    required String schoolId, required String campusId,
    required String academicYearId, required String classId,
    required String name, required List<FeePlanLine> items,
  }) async {
    _requireSession();
    if (items.isEmpty || items.length > 30 ||
        items.any((item) => item.amountMinor < 0)) {
      throw const FormatException('Select valid fee categories and amounts');
    }
    final response = await client.rpc('owner_save_class_fee_plan', params: {
      'p_school': schoolId, 'p_campus': campusId, 'p_year': academicYearId,
      'p_class': classId, 'p_name': name.trim(),
      'p_items': items.map((item) => item.toJson()).toList(),
    });
    if (response is! Map || response['saved'] != true ||
        (response['item_count'] as num?)?.toInt() != items.length) {
      throw StateError('Fee plan save not confirmed. Refresh before retrying.');
    }
  }
}

/// Monetary values use integer minor units, never binary floating point.
class FeeMoney {
  static int? parseMinor(String text) {
    final cleaned = text.trim();
    if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(cleaned)) return null;
    final parts = cleaned.split('.');
    final major = int.parse(parts[0]);
    final fraction = parts.length == 1
      ? 0 : int.parse(parts[1].padRight(2, '0'));
    return major * 100 + fraction;
  }

  static String showMinor(int minor) {
    final major = minor ~/ 100;
    final cents = (minor % 100).toString().padLeft(2, '0');
    return '$major.$cents';
  }
}
