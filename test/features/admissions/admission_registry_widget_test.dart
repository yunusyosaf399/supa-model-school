import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/admissions/data/admission_draft_repository.dart';
import 'package:supa_model_school/features/admissions/presentation/admission_draft_list_page.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';

const owner=OwnerAccess(
  userId:'owner-test',displayName:'Owner',
  schoolId:'school-1',schoolName:'Supa Model School',
  setupComplete:true,activeYearId:'year-1',
  campuses:[OwnerCampus(id:'campus-1',name:'Main Campus')],
);

class RegistryFake implements AdmissionDraftRepository {
  @override
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request)=>
    throw UnimplementedError();
  @override
  Future<List<AdmissionDraftRecord>> listDrafts({
    required String schoolId,required String campusId,
  }) async {
    if(schoolId!='school-1'||campusId!='campus-1') {
      throw StateError('wrong campus');
    }
    return const [
      AdmissionDraftRecord(
        id:'draft-1',revision:1,name:'TEST Draft Child',
        campusId:'campus-1',academicYearId:'year-1',
        status:'draft',guardians:[],documents:[],
      ),
      AdmissionDraftRecord(
        id:'submitted-1',revision:2,name:'TEST Pending Child',
        campusId:'campus-1',academicYearId:'year-1',
        status:'submitted',guardians:[],documents:[],
        conditionalDue:'2026-12-31',
      ),
      AdmissionDraftRecord(
        id:'approved-1',revision:3,name:'TEST Approved Child',
        campusId:'campus-1',academicYearId:'year-1',
        status:'approved',studentId:'student-1',guardians:[],documents:[],
      ),
    ];
  }
}

void main(){
  test('submitted and approved records cannot resume',(){
    final pending=AdmissionDraftRecord.fromJson({
      'id':'a','revision':3,'name':'Child',
      'campus_id':'campus','academic_year_id':'year',
      'status':'submitted','student_id':null,
      'guardians':[],'documents':[],
    });
    expect(pending.canResume,false);
    expect(pending.status,'submitted');
  });
  testWidgets('Owner registry shows pending, approved and editable draft separately',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1300,900));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home:Scaffold(body:AdmissionDraftListPage(
        owner:owner,repository:RegistryFake(),
        selectedCampusId:'campus-1',
        onNewAdmission:(){},onOpenDraft:(_){},
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('TEST Pending Child'),findsOneWidget);
    expect(find.byKey(const Key('resume-admission-submitted-1')),findsNothing);
    expect(find.byKey(const Key('resume-admission-approved-1')),findsNothing);
    expect(find.byKey(const Key('resume-admission-draft-1')),findsOneWidget);
    await tester.tap(find.byKey(const Key('admissions-filter-submitted')));
    await tester.pumpAndSettle();
    expect(find.text('TEST Pending Child'),findsOneWidget);
    expect(find.text('TEST Approved Child'),findsNothing);
    expect(find.textContaining('Awaiting assigned Principal'),findsOneWidget);
  });
}
