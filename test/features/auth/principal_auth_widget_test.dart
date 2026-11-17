import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/main.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/auth/data/principal_auth_gateway.dart';
import 'package:supa_model_school/features/admissions/data/admission_approval_repository.dart';

class NonOwner implements OwnerAuthGateway {
  @override bool get configured=>true;
  @override Future<OwnerAccess?> restore() async=>null;
  @override Future<OwnerAccess> signIn(String email,String password) async=>
      throw StateError('No unique authorized Owner membership');
  @override Future<void> signOut() async {}
  @override Future<void> sendRecovery(String email) async {}
  @override Future<void> changePassword(String old,String next) async {}
  @override Future<OwnerAccess> completeInitialSetup(OwnerInitialSetupRequest request) =>
      throw UnimplementedError();
}

class PrincipalSessionFake implements PrincipalAuthGateway {
  @override bool get configured=>true;
  bool loggedOut=false;
  @override Future<PrincipalAccess?> restore() async=>null;
  @override Future<PrincipalAccess> signIn(String email,String password) async {
    if(email!='principal@example.test' || password!='principal-pass') {
      throw StateError('Credentials rejected');
    }
    return const PrincipalAccess(
      userId:'principal-auth-id',displayName:'TEST Principal',
      schoolId:'school-1',schoolName:'Supa Model School',
      campuses:[PrincipalCampus(id:'campus-1',name:'Main Campus')],
    );
  }
  @override Future<void> signOut() async {loggedOut=true;}
}

class PrincipalQueueFake implements AdmissionApprovalRepository {
  int readCount=0;
  @override Future<AdmissionSubmitResult> submit(AdmissionSubmitRequest request)=>
    throw UnimplementedError();
  @override Future<List<PrincipalApprovalItem>> listPending({
    required String schoolId,required String campusId,
  }) async {
    if(schoolId!='school-1'||campusId!='campus-1') {
      throw StateError('Unauthorized campus');
    }
    readCount++;
    return const [];
  }
  @override Future<PrincipalDecisionResult> review({
    required String applicationId,required int expectedRevision,
    required String operationId,required String decision,String? reason,
  }) => throw UnimplementedError();
  @override Future<List<PrincipalDocumentRecord>> listDocuments(String id) =>
    throw UnimplementedError();
  @override Future<String> signedDocumentUrl(PrincipalDocumentRecord doc)=>
    throw UnimplementedError();
  @override Future<void> reviewDocument({
    required String documentId,required int expectedRevision,
    required String operationId,required String decision,String? reason,
  }) => throw UnimplementedError();
}

void main() {
  test('Principal context rejects absent or invalid campuses',(){
    expect(()=>PrincipalAccess.fromJson({
      'user_id':'u','school_id':'s','school_name':'S',
      'display_name':'P','campuses':[],
    }),throwsStateError);
  });
  testWidgets('separate authenticated Principal login, queue and sign-out',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200,850));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final gateway=PrincipalSessionFake();
    final approvals=PrincipalQueueFake();
    await tester.pumpWidget(SupaModelSchoolApp(
      authGateway:NonOwner(),
      principalAuthGateway:gateway,
      admissionApprovalRepository:approvals,
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-email')),
      'principal@example.test');
    await tester.enterText(find.byKey(const Key('login-password')),
      'principal-pass');
    await tester.tap(find.byKey(const Key('login-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('principal-admissions-home')),findsOneWidget);
    expect(find.byKey(const Key('principal-approval-page')),findsOneWidget);
    expect(find.byKey(const Key('dashboard-page')),findsNothing);
    expect(approvals.readCount,1);
    await tester.tap(find.byKey(const Key('principal-sign-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();
    expect(gateway.loggedOut,isTrue);
    expect(find.byKey(const Key('login-email')),findsOneWidget);
  });
}
