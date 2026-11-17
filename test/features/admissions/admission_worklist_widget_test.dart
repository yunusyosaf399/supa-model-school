import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/admissions/data/admission_draft_repository.dart';
import 'package:supa_model_school/features/admissions/presentation/admission_draft_list_page.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';

const owner = OwnerAccess(
  userId:'test-owner', displayName:'Owner',
  schoolId:'school-1', schoolName:'School',
  setupComplete:true, activeYearId:'year-1',
  campuses:[OwnerCampus(id:'campus-a',name:'Main Campus'),
            OwnerCampus(id:'campus-b',name:'Junior Campus')],
);

class FakeWorklist extends AdmissionDraftRepository {
  FakeWorklist({this.fail=false});
  final bool fail;
  final calls=<String>[];
  @override
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request) =>
    throw UnimplementedError();

  @override
  Future<List<AdmissionDraftRecord>> listDrafts({
    required String schoolId,required String campusId,
  }) async {
    calls.add('$schoolId/$campusId');
    if (fail) throw StateError('network');
    return [
      AdmissionDraftRecord(
        id:'draft-id',revision:2,name:'TEST Admission Applicant 001',
        status:'draft',campusId:campusId,academicYearId:'year-1',
        guardians:const [],documents:const [
          {'kind':'birth_certificate','required':true,'applicable':true,'status':'missing'},
        ],
      ),
    ];
  }
}

Widget page(FakeWorklist repo,void Function(AdmissionDraftRecord) opened) =>
  MaterialApp(home: Scaffold(body: AdmissionDraftListPage(
    owner:owner,repository:repo,selectedCampusId:'campus-a',
    onNewAdmission:(){},onOpenDraft:opened,
  )));

void main() {
  testWidgets('Owner sees scoped live drafts and resumes selected item',
      (tester) async {
    final repo=FakeWorklist();
    AdmissionDraftRecord? opened;
    await tester.pumpWidget(page(repo,(record)=>opened=record));
    await tester.pumpAndSettle();
    expect(repo.calls,['school-1/campus-a']);
    expect(find.text('TEST Admission Applicant 001'),findsOneWidget);
    expect(find.textContaining('1 outstanding documents'),findsOneWidget);
    await tester.tap(find.byKey(const Key('resume-admission-draft-id')));
    await tester.pump();
    expect(opened?.id,'draft-id');
    expect(opened?.revision,2);
  });
  testWidgets('failed authorization never shows stale or demo admissions',
      (tester) async {
    final repo=FakeWorklist(fail:true);
    await tester.pumpWidget(page(repo,(_)=>{}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to load authorized'),findsOneWidget);
    expect(find.text('TEST Admission Applicant 001'),findsNothing);
    expect(find.text('Retry'),findsOneWidget);
  });
}
