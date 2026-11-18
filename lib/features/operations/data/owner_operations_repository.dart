import 'package:supabase_flutter/supabase_flutter.dart';

List<Map<String, dynamic>> _rows(Object? raw) {
  if (raw is! List) throw const FormatException('Invalid directory rows');
  return List.unmodifiable([
    for (final item in raw)
      Map<String, dynamic>.from(item as Map),
  ]);
}

class StaffMember {
  const StaffMember({
    required this.id, required this.employeeNo, required this.name,
    required this.department, required this.position, required this.status,
    required this.employmentType, required this.hiredOn,
    required this.isTeaching, required this.hasAccount,
    this.nameUr = '',
  });
  final String id, employeeNo, name, nameUr, department, position;
  final String status, employmentType, hiredOn;
  final bool isTeaching, hasAccount;

  factory StaffMember.fromJson(Map<String, dynamic> data) => StaffMember(
    id: data['id'] as String,
    employeeNo: data['employee_no'] as String,
    name: data['full_name'] as String,
    nameUr: data['full_name_ur'] as String? ?? '',
    department: data['department'] as String,
    position: data['position'] as String,
    status: data['employment_status'] as String,
    employmentType: data['employment_type'] as String,
    hiredOn: data['hired_on'].toString(),
    isTeaching: data['teaching'] == true,
    hasAccount: data['linked_login'] == true,
  );
}

class StaffDepartment {
  const StaffDepartment({
    required this.code, required this.name,
  });
  final String code, name;
  factory StaffDepartment.fromJson(Map<String, dynamic> data) =>
      StaffDepartment(
        code: data['code'] as String,
        name: data['name'] as String,
      );
}

class StaffDirectorySnapshot {
  const StaffDirectorySnapshot({
    required this.schoolId, required this.campusId,
    required this.staff, required this.departments,
    required this.positionCount,
  });
  final String schoolId, campusId;
  final List<StaffMember> staff;
  final List<StaffDepartment> departments;
  final int positionCount;

  factory StaffDirectorySnapshot.fromJson(Map<String, dynamic> data) {
    if (data['read_only'] != true) {
      throw const FormatException('Unexpected staff data access mode');
    }
    return StaffDirectorySnapshot(
      schoolId: data['school_id'] as String,
      campusId: data['campus_id'] as String,
      staff: List.unmodifiable([
        for (final row in _rows(data['staff']))
          StaffMember.fromJson(row),
      ]),
      departments: List.unmodifiable([
        for (final row in _rows(data['departments']))
          StaffDepartment.fromJson(row),
      ]),
      positionCount: _rows(data['positions']).length,
    );
  }
}

class TransportVehicle {
  const TransportVehicle({
    required this.id, required this.registration, required this.capacity,
    required this.status,
  });
  final String id, registration, status;
  final int capacity;

  factory TransportVehicle.fromJson(Map<String, dynamic> data) =>
      TransportVehicle(
        id: data['id'] as String,
        registration: data['registration_no'] as String,
        capacity: (data['capacity'] as num).toInt(),
        status: data['status'] as String,
      );
}

class TransportStop {
  const TransportStop({
    required this.id, required this.name, required this.order,
    this.pickupTime, this.dropoffTime,
  });
  final String id, name;
  final int order;
  final String? pickupTime, dropoffTime;

  factory TransportStop.fromJson(Map<String, dynamic> data) => TransportStop(
    id: data['id'] as String,
    name: data['name'] as String,
    order: (data['order'] as num).toInt(),
    pickupTime: data['pickup_time'] as String?,
    dropoffTime: data['dropoff_time'] as String?,
  );
}

class TransportRider {
  const TransportRider({
    required this.id, required this.name, required this.registration,
    required this.className, required this.stopName,
    required this.startsOn, this.sectionName,
  });
  final String id, name, registration, className, stopName, startsOn;
  final String? sectionName;

  factory TransportRider.fromJson(Map<String, dynamic> data) =>
      TransportRider(
        id: data['id'] as String,
        name: data['name'] as String,
        registration: data['registration'] as String,
        className: data['class_name'] as String,
        sectionName: data['section_name'] as String?,
        stopName: data['stop_name'] as String,
        startsOn: data['starts_on'].toString(),
      );
}

class TransportRoute {
  const TransportRoute({
    required this.id, required this.code, required this.name,
    required this.active, required this.stops, required this.students,
  });
  final String id, code, name;
  final bool active;
  final List<TransportStop> stops;
  final List<TransportRider> students;

  factory TransportRoute.fromJson(Map<String, dynamic> data) => TransportRoute(
    id: data['id'] as String,
    code: data['code'] as String,
    name: data['name'] as String,
    active: data['active'] == true,
    stops: List.unmodifiable([
      for (final row in _rows(data['stops']))
        TransportStop.fromJson(row),
    ]),
    students: List.unmodifiable([
      for (final row in _rows(data['students']))
        TransportRider.fromJson(row),
    ]),
  );
}

class TransportDirectorySnapshot {
  const TransportDirectorySnapshot({
    required this.schoolId, required this.campusId,
    required this.yearId, required this.yearLabel,
    required this.vehicles, required this.routes,
  });
  final String schoolId, campusId, yearId, yearLabel;
  final List<TransportVehicle> vehicles;
  final List<TransportRoute> routes;

  int get riderCount => routes.fold<int>(
      0, (count, route) => count + route.students.length);
  int get stopCount => routes.fold<int>(
      0, (count, route) => count + route.stops.length);

  factory TransportDirectorySnapshot.fromJson(Map<String, dynamic> data) {
    if (data['read_only'] != true ||
        data['vehicles_are_unassigned_to_routes'] != true) {
      throw const FormatException('Unexpected transport data access mode');
    }
    return TransportDirectorySnapshot(
      schoolId: data['school_id'] as String,
      campusId: data['campus_id'] as String,
      yearId: data['year_id'] as String,
      yearLabel: data['year_label'] as String,
      vehicles: List.unmodifiable([
        for (final row in _rows(data['vehicles']))
          TransportVehicle.fromJson(row),
      ]),
      routes: List.unmodifiable([
        for (final row in _rows(data['routes']))
          TransportRoute.fromJson(row),
      ]),
    );
  }
}

abstract class OwnerOperationsRepository {
  const OwnerOperationsRepository();

  Future<StaffDirectorySnapshot> loadStaff({
    required String schoolId, required String campusId,
  });

  Future<TransportDirectorySnapshot> loadTransport({
    required String schoolId, required String campusId,
    required String academicYearId,
  });
}

class SupabaseOwnerOperationsRepository implements OwnerOperationsRepository {
  const SupabaseOwnerOperationsRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> _rpc(
      String name, Map<String, String> params) async {
    if (client.auth.currentSession == null) {
      throw StateError('Verified Owner session required');
    }
    final response = await client.rpc(name, params: params);
    if (response is! Map) {
      throw StateError('Invalid $name response');
    }
    return Map<String, dynamic>.from(response);
  }

  @override
  Future<StaffDirectorySnapshot> loadStaff({
    required String schoolId, required String campusId,
  }) async {
    final data = await _rpc('owner_staff_directory_snapshot', {
      'p_school': schoolId,
      'p_campus': campusId,
    });
    final result = StaffDirectorySnapshot.fromJson(data);
    if (result.schoolId != schoolId || result.campusId != campusId) {
      throw StateError('Staff directory returned a different school/campus');
    }
    return result;
  }

  @override
  Future<TransportDirectorySnapshot> loadTransport({
    required String schoolId, required String campusId,
    required String academicYearId,
  }) async {
    final data = await _rpc('owner_transport_directory_snapshot', {
      'p_school': schoolId,
      'p_campus': campusId,
      'p_year': academicYearId,
    });
    final result = TransportDirectorySnapshot.fromJson(data);
    if (result.schoolId != schoolId ||
        result.campusId != campusId ||
        result.yearId != academicYearId) {
      throw StateError('Transport directory returned a different campus/year');
    }
    return result;
  }
}
