import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/operations/data/owner_operations_repository.dart';
import 'package:supa_model_school/features/operations/presentation/owner_staff_directory_page.dart';
import 'package:supa_model_school/features/operations/presentation/owner_transport_directory_page.dart';

const owner = OwnerAccess(
  userId: 'owner-id',
  displayName: 'Owner',
  schoolId: 'school-1',
  schoolName: 'Supa Model School',
  campuses: [OwnerCampus(id: 'campus-1', name: 'Main Campus')],
  activeYearId: 'year-1',
  activeYearLabel: '2026-2027',
  setupComplete: true,
);

class FakeOwnerOperationsRepository implements OwnerOperationsRepository {
  final calls = <String>[];
  bool fail = false;

  @override
  Future<StaffDirectorySnapshot> loadStaff({
    required String schoolId,
    required String campusId,
  }) async {
    calls.add('staff:' + schoolId + ':' + campusId);
    if (fail) throw StateError('Read permission denied');
    return const StaffDirectorySnapshot(
      schoolId: 'school-1',
      campusId: 'campus-1',
      departments: [
        StaffDepartment(code: 'SAMPLE_ACADEMICS', name: 'Academics'),
        StaffDepartment(code: 'SAMPLE_ADMIN', name: 'Administration'),
      ],
      positionCount: 2,
      staff: [
        StaffMember(
          id: 'staff-1',
          employeeNo: 'SAMPLE-EMP-001',
          name: 'SAMPLE Shazia Khan',
          department: 'Academics',
          position: 'Class Teacher',
          status: 'active',
          employmentType: 'permanent',
          hiredOn: '2026-04-01',
          isTeaching: true,
          hasAccount: false,
        ),
        StaffMember(
          id: 'staff-2',
          employeeNo: 'SAMPLE-EMP-002',
          name: 'SAMPLE Farooq Ahmad',
          department: 'Administration',
          position: 'Principal',
          status: 'active',
          employmentType: 'permanent',
          hiredOn: '2026-04-01',
          isTeaching: false,
          hasAccount: false,
        ),
      ],
    );
  }

  @override
  Future<TransportDirectorySnapshot> loadTransport({
    required String schoolId,
    required String campusId,
    required String academicYearId,
  }) async {
    calls.add('transport:' + schoolId + ':' + campusId + ':' + academicYearId);
    if (fail) throw StateError('Read permission denied');
    return const TransportDirectorySnapshot(
      schoolId: 'school-1',
      campusId: 'campus-1',
      yearId: 'year-1',
      yearLabel: '2026-2027',
      vehicles: [
        TransportVehicle(
          id: 'bus-1',
          registration: 'SAMPLE-BUS-001',
          capacity: 24,
          status: 'active',
        ),
      ],
      routes: [
        TransportRoute(
          id: 'route-1',
          code: 'SAMPLE-RT-01',
          name: 'SAMPLE Mingora North Route',
          active: true,
          stops: [
            TransportStop(
              id: 'stop-1',
              order: 1,
              name: 'SAMPLE Mingora Bazaar',
              pickupTime: '07:20:00',
              dropoffTime: '14:30:00',
            ),
            TransportStop(
              id: 'stop-2',
              order: 2,
              name: 'SAMPLE Fizagat Stop',
            ),
          ],
          students: [
            TransportRider(
              id: 'student-1',
              name: 'Areeba Fatima',
              registration: 'SAMPLE-2026-0003',
              className: 'Grade 1',
              sectionName: 'A',
              stopName: 'SAMPLE Mingora Bazaar',
              startsOn: '2026-11-18',
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  test('transport snapshot totals are calculated from actual rows', () {
    const route = TransportRoute(
      id: 'r', code: 'RT', name: 'Route', active: true,
      stops: [
        TransportStop(id: 's1', name: 'Stop One', order: 1),
        TransportStop(id: 's2', name: 'Stop Two', order: 2),
      ],
      students: [
        TransportRider(id: 'st', name: 'Student', registration: 'X',
          className: 'Class', stopName: 'Stop One', startsOn: '2026-11-18'),
      ],
    );
    const snapshot = TransportDirectorySnapshot(
      schoolId: 's', campusId: 'c', yearId: 'y',
      yearLabel: '2026-2027', vehicles: [], routes: [route],
    );
    expect(snapshot.stopCount, 2);
    expect(snapshot.riderCount, 1);
  });

  testWidgets('Staff directory reads Owner campus and filters names',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeOwnerOperationsRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: OwnerStaffDirectoryPage(
        owner: owner, repository: repo, selectedCampusId: 'campus-1'))));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('staff:school-1:campus-1'));
    expect(find.byKey(const Key('owner-staff-live-page')), findsOneWidget);
    expect(find.text('Employees: 2'), findsOneWidget);
    expect(find.text('SAMPLE Shazia Khan'), findsOneWidget);
    expect(find.text('SAMPLE Farooq Ahmad'), findsOneWidget);
    expect(find.text('No login account linked'), findsNWidgets(2));
    await tester.enterText(
      find.byKey(const Key('owner-staff-search')), 'Shazia');
    await tester.pumpAndSettle();
    expect(find.text('SAMPLE Shazia Khan'), findsOneWidget);
    expect(find.text('SAMPLE Farooq Ahmad'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Staff screen shows a real permission failure, not demo data',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 810));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeOwnerOperationsRepository()..fail = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: OwnerStaffDirectoryPage(owner: owner, repository: repo))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Read permission denied'), findsOneWidget);
    expect(find.byKey(const Key('owner-staff-SAMPLE-EMP-001')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Transport shows real vehicles, stops and assigned students',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeOwnerOperationsRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: OwnerTransportDirectoryPage(
        owner: owner, repository: repo, selectedCampusId: 'campus-1'))));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('transport:school-1:campus-1:year-1'));
    expect(find.byKey(const Key('owner-transport-live-page')), findsOneWidget);
    expect(find.text('Vehicles: 1'), findsOneWidget);
    expect(find.text('Riders: 1'), findsOneWidget);
    expect(find.text('SAMPLE-BUS-001'), findsOneWidget);
    expect(find.text('SAMPLE Mingora North Route'), findsOneWidget);
    expect(find.text('SAMPLE Mingora Bazaar'), findsWidgets);
    expect(find.text('Areeba Fatima'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Transport search does not invent matching routes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeOwnerOperationsRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: OwnerTransportDirectoryPage(owner: owner, repository: repo))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('owner-transport-search')));
    await tester.enterText(
      find.byKey(const Key('owner-transport-search')), 'No such route');
    await tester.pumpAndSettle();
    expect(find.text('No matching routes found.'), findsOneWidget);
    expect(find.byKey(const Key('owner-route-SAMPLE-RT-01')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
