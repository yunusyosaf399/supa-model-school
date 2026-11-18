import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fees/data/fee_payment_repository.dart';

class ExpenseCategory {
  const ExpenseCategory({required this.id,required this.code,
    required this.name,required this.kind,required this.active});
  final String id,code,name,kind;
  final bool active;
  factory ExpenseCategory.parse(Map<String,dynamic> x)=>ExpenseCategory(
    id:x['id'] as String,code:x['code'] as String,name:x['name'] as String,
    kind:x['kind'] as String,active:x['active']==true);
}
class ExpenseAccount {
  const ExpenseAccount({required this.id,required this.name,
    required this.method,required this.status,this.maskedReference});
  final String id,name,method,status;
  final String? maskedReference;
  factory ExpenseAccount.parse(Map<String,dynamic> x)=>ExpenseAccount(
    id:x['id'] as String,name:x['name'] as String,
    method:x['method'] as String,status:x['status'] as String,
    maskedReference:x['masked_reference'] as String?);
}
class ExpensePayment {
  const ExpensePayment({required this.id,required this.amountMinor,
    required this.paidOn,required this.accountId,this.vendor,this.reference});
  final String id,paidOn,accountId;
  final String? vendor,reference;
  final int amountMinor;
  factory ExpensePayment.parse(Map<String,dynamic> x)=>ExpensePayment(
    id:x['id'] as String,paidOn:x['paid_on'].toString(),
    accountId:x['account_id'] as String,
    vendor:x['vendor'] as String?,reference:x['reference'] as String?,
    amountMinor:feeInt(x['amount_minor']));
}
class ExpenseRequest {
  const ExpenseRequest({
    required this.id,required this.categoryId,required this.category,
    required this.kind,required this.amountMinor,required this.paidMinor,
    required this.expenseDate,required this.purpose,required this.status,
    required this.requesterId,required this.payments,this.rejectionReason});
  final String id,categoryId,category,kind,expenseDate,purpose,status,requesterId;
  final int amountMinor,paidMinor;
  final String? rejectionReason;
  final List<ExpensePayment> payments;
  int get remainingMinor=>amountMinor-paidMinor;
  factory ExpenseRequest.parse(Map<String,dynamic> x)=>ExpenseRequest(
    id:x['id'] as String,categoryId:x['category_id'] as String,
    category:x['category'] as String,kind:x['kind'] as String,
    amountMinor:feeInt(x['amount_minor']),paidMinor:feeInt(x['paid_minor']),
    expenseDate:x['expense_date'].toString(),purpose:x['purpose'] as String,
    status:x['status'] as String,requesterId:x['requester_id'] as String,
    rejectionReason:x['rejection_reason'] as String?,
    payments:List.unmodifiable([
      for(final row in feeRows(x['payments']))ExpensePayment.parse(row)]));
}
class ExpenseWorkspace {
  const ExpenseWorkspace({
    required this.schoolId,required this.campusId,required this.currency,
    required this.timezone,required this.isOwner,required this.canCreate,
    required this.canRead,required this.canPay,
    required this.categories,required this.accounts,required this.requests});
  final String schoolId,campusId,currency,timezone;
  final bool isOwner,canCreate,canRead,canPay;
  final List<ExpenseCategory> categories;
  final List<ExpenseAccount> accounts;
  final List<ExpenseRequest> requests;
  factory ExpenseWorkspace.parse(Map<String,dynamic> x)=>ExpenseWorkspace(
    schoolId:x['school_id'] as String,campusId:x['campus_id'] as String,
    currency:x['currency'] as String,timezone:x['timezone'] as String,
    isOwner:x['is_owner']==true,canCreate:x['can_create']==true,
    canRead:x['can_read']==true,canPay:x['can_pay']==true,
    categories:List.unmodifiable([
      for(final row in feeRows(x['categories']))ExpenseCategory.parse(row)]),
    accounts:List.unmodifiable([
      for(final row in feeRows(x['accounts']))ExpenseAccount.parse(row)]),
    requests:List.unmodifiable([
      for(final row in feeRows(x['requests']))ExpenseRequest.parse(row)]));
}

abstract class ExpenseRepository {
  const ExpenseRepository();
  Future<ExpenseWorkspace> workspace({
    required String schoolId,required String campusId});
  Future<String> createCategory({
    required String schoolId,required String code,required String name,
    required String kind,required String operationId});
  Future<String> createAccount({
    required String schoolId,required String campusId,required String name,
    required String kind,String? maskedReference,required String operationId});
  Future<String> request({
    required String schoolId,required String campusId,
    required String categoryId,required int amountMinor,
    required String expenseDate,required String purpose,
    required String operationId});
  Future<String> review({
    required String schoolId,required String campusId,required String requestId,
    required String decision,String? reason,required String operationId});
  Future<ExpensePaidResult> pay({
    required String schoolId,required String campusId,required String requestId,
    required String accountId,required int amountMinor,
    required String paidOn,String? vendor,String? reference,
    required String operationId});
}
class ExpensePaidResult {
  const ExpensePaidResult({required this.paymentId,required this.journalId,
    required this.amountMinor,required this.remainingMinor});
  final String paymentId,journalId;
  final int amountMinor,remainingMinor;
}

class SupabaseExpenseRepository implements ExpenseRepository {
  const SupabaseExpenseRepository(this.client);
  final SupabaseClient client;
  Future<Map<String,dynamic>> _rpc(String name,Map<String,Object?> params)async{
    if(client.auth.currentSession==null){
      throw StateError('Authenticated school account required');
    }
    final response=await client.rpc(name,params:params);
    if(response is! Map)throw StateError('Invalid $name server response');
    return Map<String,dynamic>.from(response);
  }
  Future<String> _write(String fn,Map<String,Object?> params,
      String key)async{
    final x=await _rpc(fn,params);
    if(x['saved']!=true||x[key] is! String){
      throw StateError('Operation not confirmed. Retry with same details.');
    }
    return x[key] as String;
  }
  @override
  Future<ExpenseWorkspace> workspace({
    required String schoolId,required String campusId})async{
    final w=ExpenseWorkspace.parse(await _rpc('expense_workspace',{
      'p_school':schoolId,'p_campus':campusId}));
    if(w.schoolId!=schoolId||w.campusId!=campusId){
      throw StateError('Expense data outside authorized campus');
    }
    return w;
  }
  @override
  Future<String> createCategory({required String schoolId,required String code,
    required String name,required String kind,
    required String operationId})=>_write('expense_create_category',{
      'p_school':schoolId,'p_code':code,'p_name':name,'p_kind':kind,
      'p_operation':operationId},'category_id');
  @override
  Future<String> createAccount({required String schoolId,
    required String campusId,required String name,required String kind,
    String? maskedReference,required String operationId})=>
    _write('expense_create_account',{
      'p_school':schoolId,'p_campus':campusId,'p_name':name,
      'p_kind':kind,'p_masked':maskedReference,
      'p_operation':operationId},'account_id');
  @override
  Future<String> request({required String schoolId,
    required String campusId,required String categoryId,
    required int amountMinor,required String expenseDate,
    required String purpose,required String operationId}) {
    if(amountMinor<=0)throw const FormatException('Expense must be positive');
    return _write('expense_request',{
      'p_school':schoolId,'p_campus':campusId,
      'p_category':categoryId,'p_amount_minor':amountMinor,
      'p_expense_date':expenseDate,'p_purpose':purpose,
      'p_operation':operationId},'request_id');
  }
  @override
  Future<String> review({required String schoolId,required String campusId,
    required String requestId,required String decision,String? reason,
    required String operationId})async{
    if(!{'approved','rejected'}.contains(decision)){
      throw const FormatException('Only approve or reject supported');
    }
    final x=await _rpc('expense_review',{
      'p_school':schoolId,'p_campus':campusId,
      'p_request':requestId,'p_decision':decision,
      'p_reason':decision=='rejected'?reason:null,
      'p_operation':operationId});
    if(x['saved']!=true||x['request_id']!=requestId||
      x['status']!=decision){
      throw StateError('Approval result not confirmed. Retry same operation.');
    }
    return decision;
  }
  @override
  Future<ExpensePaidResult> pay({required String schoolId,
    required String campusId,required String requestId,
    required String accountId,required int amountMinor,
    required String paidOn,String? vendor,String? reference,
    required String operationId})async{
    if(amountMinor<=0)throw const FormatException('Invalid payment amount');
    final x=await _rpc('expense_payment',{
      'p_school':schoolId,'p_campus':campusId,'p_request':requestId,
      'p_account':accountId,'p_amount_minor':amountMinor,
      'p_paid_on':paidOn,'p_vendor':vendor,'p_reference':reference,
      'p_operation':operationId});
    if(x['saved']!=true||x['payment_id'] is! String||
      x['journal_id'] is! String||feeInt(x['amount_minor'])!=amountMinor){
      throw StateError('Payment not confirmed. Retry same operation.');
    }
    return ExpensePaidResult(
      paymentId:x['payment_id'] as String,
      journalId:x['journal_id'] as String,amountMinor:amountMinor,
      remainingMinor:feeInt(x['remaining_minor']));
  }
}
