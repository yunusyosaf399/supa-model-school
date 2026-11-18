import 'package:supabase_flutter/supabase_flutter.dart';

import 'fee_monthly_repository.dart';
import 'fee_payment_repository.dart';

class CategoryBillResult {
  const CategoryBillResult({
    required this.added,required this.skipped,required this.eligible,
    required this.category,
  });
  final int added,skipped,eligible;
  final String category;
}

class OtherPersonCharge {
  const OtherPersonCharge({
    required this.id,required this.categoryId,required this.categoryName,
    required this.frequency,required this.amountMinor,required this.paidMinor,
    required this.outstandingMinor,required this.dueOn,required this.memo,
  });
  final String id,categoryId,categoryName,frequency,dueOn,memo;
  final int amountMinor,paidMinor,outstandingMinor;
  factory OtherPersonCharge.parse(Map<String,dynamic> x) => OtherPersonCharge(
    id:x['id'] as String,categoryId:x['category_id'] as String,
    categoryName:x['category'] as String,frequency:x['frequency'] as String,
    amountMinor:feeInt(x['amount_minor']),paidMinor:feeInt(x['paid_minor']),
    outstandingMinor:feeInt(x['outstanding_minor']),
    dueOn:x['due_on'].toString(),memo:x['memo'] as String);
}

class OtherPersonReceipt {
  const OtherPersonReceipt({
    required this.number,required this.amountMinor,required this.method});
  final String number,method;
  final int amountMinor;
  factory OtherPersonReceipt.parse(Map<String,dynamic> x) =>
    OtherPersonReceipt(number:x['number'] as String,
      amountMinor:feeInt(x['amount_minor']),method:x['method'] as String);
}
class OtherPersonAccount {
  const OtherPersonAccount({required this.id,required this.name,
    this.contact,required this.charges,required this.receipts});
  final String id,name;
  final String? contact;
  final List<OtherPersonCharge> charges;
  final List<OtherPersonReceipt> receipts;
  int get dueMinor=>charges.fold<int>(0,(a,c)=>a+c.outstandingMinor);

  factory OtherPersonAccount.parse(Map<String,dynamic> x)=>OtherPersonAccount(
    id:x['id'] as String,name:x['name'] as String,
    contact:x['contact'] as String?,
    charges:List.unmodifiable([
      for(final row in feeRows(x['charges']))OtherPersonCharge.parse(row)]),
    receipts:List.unmodifiable([
      for(final row in feeRows(x['receipts']))OtherPersonReceipt.parse(row)]));
}
class OtherPeopleLedger {
  const OtherPeopleLedger({required this.schoolId,required this.campusId,
    required this.yearId,required this.currency,required this.canCollect,
    required this.people,required this.categories});
  final String schoolId,campusId,yearId,currency;
  final bool canCollect;
  final List<OtherPersonAccount> people;
  final List<FeePaymentCategory> categories;
  factory OtherPeopleLedger.parse(Map<String,dynamic> x)=>OtherPeopleLedger(
    schoolId:x['school_id'] as String,campusId:x['campus_id'] as String,
    yearId:x['year_id'] as String,currency:x['currency'] as String,
    canCollect:x['can_collect']==true,
    people:List.unmodifiable([
      for(final row in feeRows(x['people']))OtherPersonAccount.parse(row)]),
    categories:List.unmodifiable([
      for(final row in feeRows(x['categories']))
        FeePaymentCategory.fromJson({...row,'active':true})]));
}

abstract class FeeBillingRepository {
  const FeeBillingRepository();
  Future<CategoryBillResult> generateCategory({
    required String schoolId,required String campusId,required String yearId,
    required String month,required String categoryId,
    required String scope,String? targetId,int? overrideMinor,
    required bool includeOptional,required String operationId});
  Future<OtherPeopleLedger> otherPeople({
    required String schoolId,required String campusId,required String yearId});
  Future<String> createPerson({
    required String schoolId,required String campusId,
    required String name,String? contact,required String operationId});
  Future<String> chargePerson({
    required String schoolId,required String campusId,required String yearId,
    required String personId,required String categoryId,
    required int amountMinor,required String dueOn,
    required String memo,required String operationId});
  Future<QuickPayReceipt> collectPerson({
    required String schoolId,required String campusId,required String yearId,
    required String personId,required int amountMinor,required String method,
    String? bankRef,required List<QuickPayAllocation> allocations,
    required String operationId});
}

class SupabaseFeeBillingRepository implements FeeBillingRepository {
  const SupabaseFeeBillingRepository(this.client);
  final SupabaseClient client;

  Future<Map<String,dynamic>> rpc(
      String name,Map<String,Object?> params) async {
    if(client.auth.currentSession==null){
      throw StateError('Authenticated school staff account required');
    }
    final result=await client.rpc(name,params:params);
    if(result is! Map)throw StateError('Invalid server response from $name');
    return Map<String,dynamic>.from(result);
  }
  @override
  Future<CategoryBillResult> generateCategory({
    required String schoolId,required String campusId,required String yearId,
    required String month,required String categoryId,
    required String scope,String? targetId,int? overrideMinor,
    required bool includeOptional,required String operationId}) async {
    if(!{'campus','class','student'}.contains(scope) ||
      (scope=='campus'&&targetId!=null)||
      (scope!='campus'&&targetId==null)||
      (overrideMinor!=null&&(scope!='student'||overrideMinor<=0))){
      throw const FormatException('Invalid category billing scope');
    }
    final x=await rpc('fee_generate_category',{
      'p_school':schoolId,'p_campus':campusId,'p_year':yearId,
      'p_month':month,'p_category':categoryId,'p_scope':scope,
      'p_target':targetId,'p_override_minor':overrideMinor,
      'p_include_optional':includeOptional,'p_operation':operationId});
    if(x['saved']!=true)throw StateError('Bill was not confirmed; retry the same operation');
    return CategoryBillResult(
      added:feeInt(x['added_charges']),skipped:feeInt(x['skipped_existing']),
      eligible:feeInt(x['eligible_students']),
      category:x['category'] as String);
  }
  @override
  Future<OtherPeopleLedger> otherPeople({required String schoolId,
    required String campusId,required String yearId}) async {
    final data=OtherPeopleLedger.parse(await rpc('fee_other_people_snapshot',{
      'p_school':schoolId,'p_campus':campusId,'p_year':yearId}));
    if(data.schoolId!=schoolId||data.campusId!=campusId||data.yearId!=yearId){
      throw StateError('Other payer data is outside selected campus/year');
    }
    return data;
  }
  @override
  Future<String> createPerson({required String schoolId,
    required String campusId,required String name,String? contact,
    required String operationId}) async {
    final x=await rpc('fee_other_person_create',{
      'p_school':schoolId,'p_campus':campusId,'p_name':name,
      'p_contact':contact,'p_operation':operationId});
    if(x['saved']!=true||x['person_id'] is! String){
      throw StateError('Payer creation not confirmed');
    }
    return x['person_id'] as String;
  }
  @override
  Future<String> chargePerson({required String schoolId,
    required String campusId,required String yearId,
    required String personId,required String categoryId,
    required int amountMinor,required String dueOn,required String memo,
    required String operationId}) async {
    final x=await rpc('fee_other_post_charge',{
      'p_school':schoolId,'p_campus':campusId,'p_year':yearId,
      'p_person':personId,'p_category':categoryId,'p_amount_minor':amountMinor,
      'p_due_on':dueOn,'p_note':memo,'p_operation':operationId});
    if(x['saved']!=true||x['charge_id'] is! String ||
       feeInt(x['amount_minor'])!=amountMinor){
      throw StateError('Other payer charge not confirmed');
    }
    return x['charge_id'] as String;
  }
  @override
  Future<QuickPayReceipt> collectPerson({required String schoolId,
    required String campusId,required String yearId,
    required String personId,required int amountMinor,required String method,
    String? bankRef,required List<QuickPayAllocation> allocations,
    required String operationId}) async {
    if(amountMinor<=0 || !{'cash','bank'}.contains(method) ||
      allocations.fold<int>(0,(a,c)=>a+c.amountMinor)!=amountMinor) {
      throw const FormatException('Payment allocation does not match amount');
    }
    final x=await rpc('fee_other_collect',{
      'p_school':schoolId,'p_campus':campusId,'p_year':yearId,
      'p_person':personId,'p_amount_minor':amountMinor,
      'p_method':method,'p_bank_ref':method=='bank'?bankRef:null,
      'p_lines':[for(final a in allocations)a.toJson()],
      'p_operation':operationId});
    if(x['saved']!=true||feeInt(x['amount_minor'])!=amountMinor ||
       x['receipt_no'] is! String) {
      throw StateError('Other payer receipt not confirmed');
    }
    return QuickPayReceipt(x['receipt_id'] as String,
      x['receipt_no'] as String,amountMinor);
  }
}
