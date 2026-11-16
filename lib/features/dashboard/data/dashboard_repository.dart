import 'package:supabase_flutter/supabase_flutter.dart';

/// Values shown on the dashboard always include an explicit provenance marker.
/// Financial and attendance amounts are nullable until those schemas exist.
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.isDemo,
    required this.schoolName,
    required this.campusName,
    required this.yearLabel,
    required this.currencyCode,
    required this.source,
    required this.activeStudents,
    required this.feeCollected,
    required this.feesOutstanding,
    required this.attendancePresent,
    required this.attendanceTotal,
    required this.feeTrend,
    required this.recentAdmissions,
    required this.pendingAdmissions,
    required this.pendingExpenses,
    required this.pendingLeave,
    required this.syncStatus,
  });

  final bool isDemo;
  final String schoolName;
  final String campusName;
  final String yearLabel;
  final String currencyCode;
  final String source;
  final int? activeStudents;
  final num? feeCollected;
  final num? feesOutstanding;
  final int? attendancePresent;
  final int? attendanceTotal;
  final List<DashboardFeeMonth> feeTrend;
  final List<DashboardAdmission> recentAdmissions;
  final int? pendingAdmissions;
  final int? pendingExpenses;
  final int? pendingLeave;
  final String syncStatus;

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static num? _number(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  factory DashboardSnapshot.fromJson(Map<String, dynamic> data) {
    final rawTrend = data['fee_trend'];
    final rawAdmissions = data['recent_admissions'];
    return DashboardSnapshot(
      isDemo: data['is_demo'] == true,
      schoolName: (data['school_name'] ?? 'Supa Model School').toString(),
      campusName: (data['campus_name'] ?? 'Campus').toString(),
      yearLabel: (data['year_label'] ?? 'Not configured').toString(),
      currencyCode: (data['currency_code'] ?? '').toString(),
      source: (data['source'] ?? 'unknown').toString(),
      activeStudents: _integer(data['active_students']),
      feeCollected: _number(data['fee_collected']),
      feesOutstanding: _number(data['fees_outstanding']),
      attendancePresent: _integer(data['attendance_present']),
      attendanceTotal: _integer(data['attendance_total']),
      feeTrend: [
        if (rawTrend is List)
          for (final item in rawTrend)
            if (item is Map)
              DashboardFeeMonth(
                label: (item['label'] ?? '').toString(),
                amount: _number(item['amount']) ?? 0,
              ),
      ],
      recentAdmissions: [
        if (rawAdmissions is List)
          for (final item in rawAdmissions)
            if (item is Map)
              DashboardAdmission(
                name: (item['name'] ?? '').toString(),
                className: (item['class'] ?? '').toString(),
                when: (item['when'] ?? '').toString(),
              ),
      ],
      pendingAdmissions: _integer(data['pending_admissions']),
      pendingExpenses: _integer(data['pending_expenses']),
      pendingLeave: _integer(data['pending_leave']),
      syncStatus: (data['sync_status'] ?? 'Not configured').toString(),
    );
  }

  /// Clearly marked preview; it never claims that school transactions exist.
  static DashboardSnapshot preview() => DashboardSnapshot.fromJson({
        'is_demo': true,
        'source': 'local_preview',
        'school_name': 'Supa Model School',
        'campus_name': 'Sample Campus A',
        'year_label': '2026–2027 (sample)',
        'currency_code': 'PKR',
        'active_students': 1248,
        'fee_collected': 4860750,
        'fees_outstanding': 742500,
        'attendance_present': 1215,
        'attendance_total': 1248,
        'pending_admissions': 7,
        'pending_expenses': 4,
        'pending_leave': 3,
        'sync_status': 'Not configured',
        'recent_admissions': [
          {'name': 'Demo Student 001', 'class': 'Grade 1 A', 'when': 'Today'},
          {'name': 'Demo Student 002', 'class': 'Grade 2 A', 'when': 'Today'},
          {'name': 'Demo Student 003', 'class': 'Grade 3 B', 'when': 'Yesterday'},
          {'name': 'Demo Student 004', 'class': 'Grade 5 A', 'when': 'Yesterday'},
        ],
        'fee_trend': [
          {'label': 'Jun', 'amount': 380000},
          {'label': 'Jul', 'amount': 520000},
          {'label': 'Aug', 'amount': 700000},
          {'label': 'Sep', 'amount': 650000},
          {'label': 'Oct', 'amount': 810000},
          {'label': 'Nov', 'amount': 915000},
        ],
      });
}

class DashboardFeeMonth {
  const DashboardFeeMonth({required this.label, required this.amount});
  final String label;
  final num amount;
}

class DashboardAdmission {
  const DashboardAdmission({
    required this.name,
    required this.className,
    required this.when,
  });
  final String name;
  final String className;
  final String when;
}

abstract class DashboardRepository {
  const DashboardRepository();

  Future<DashboardSnapshot> load({
    required String schoolId,
    required String campusId,
  });
}

class UnconfiguredDashboardRepository implements DashboardRepository {
  const UnconfiguredDashboardRepository();

  @override
  Future<DashboardSnapshot> load({
    required String schoolId,
    required String campusId,
  }) async => DashboardSnapshot.preview();
}

/// Only uses publishable-key Auth session and server-enforced Owner scoped RPC.
/// Does not query DB02 child PII tables directly.
class SupabaseDashboardRepository implements DashboardRepository {
  const SupabaseDashboardRepository(this.client);

  final SupabaseClient client;

  @override
  Future<DashboardSnapshot> load({
    required String schoolId,
    required String campusId,
  }) async {
    final response = await client.rpc('owner_dashboard_snapshot', params: {
      'p_school_id': schoolId,
      'p_campus_id': campusId,
    });
    if (response is! Map) {
      throw StateError('Invalid dashboard response');
    }
    return DashboardSnapshot.fromJson(
      Map<String, dynamic>.from(response),
    );
  }
}
