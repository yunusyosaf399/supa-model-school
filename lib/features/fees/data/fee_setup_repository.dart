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

abstract class FeeSetupRepository {
  const FeeSetupRepository();

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
