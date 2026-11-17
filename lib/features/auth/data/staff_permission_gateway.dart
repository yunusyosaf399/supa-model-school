import 'package:supabase_flutter/supabase_flutter.dart';

/// Only action codes resolved by trusted database role/campus membership.
/// Feature screens must separately use authorized RPCs and Storage policies.
abstract class StaffPermissionGateway {
  const StaffPermissionGateway();
  Future<Set<String>> allowedActions();
}

class SupabaseStaffPermissionGateway implements StaffPermissionGateway {
  const SupabaseStaffPermissionGateway(this.client);
  final SupabaseClient client;

  @override
  Future<Set<String>> allowedActions() async {
    if (client.auth.currentSession == null ||
        (await client.auth.getUser()).user == null) {
      throw StateError('Signed-in staff required');
    }
    final raw = await client.rpc('sms_my_permissions');
    if (raw is! List || raw.length > 200) {
      throw StateError('Invalid staff permissions');
    }
    return Set.unmodifiable(raw.map((item) {
      if (item is! String) throw StateError('Invalid permission code');
      return item;
    }));
  }
}

class StaffPermissionTitles {
  static const sections = <String, String>{
    'dashboard': 'Dashboard',
    'students': 'Students',
    'admissions': 'Admissions',
    'exams': 'Examinations',
    'analytics': 'Analytics',
    'fees': 'Fees',
    'attendance': 'Attendance',
    'employees': 'Employees',
    'payroll': 'Payroll',
    'expenses': 'Expenses',
    'reports': 'Reports',
    'academic': 'Academics',
    'school_settings': 'Settings',
    'users': 'User Management',
  };

  static String title(String action) =>
      sections[action.split('.').first] ?? action.split('.').first;
}
