import 'package:supabase_flutter/supabase_flutter.dart';

import 'fee_payment_repository.dart';

class SchoolCashflowSummary {
  const SchoolCashflowSummary({
    required this.inflowMinor,required this.outflowMinor,
    required this.netMinor,required this.studentFeeMinor,
    required this.otherFeeMinor,required this.canteenMinor,
    required this.uniformMinor,required this.expenseMinor,
    required this.salaryMinor,required this.feeRefundMinor,
    required this.cashInMinor,required this.bankInMinor,
    required this.cashOutMinor,required this.bankOutMinor,
    required this.transactionLines,
  });

  final int inflowMinor,outflowMinor,netMinor,studentFeeMinor,otherFeeMinor;
  final int canteenMinor,uniformMinor,expenseMinor,salaryMinor,feeRefundMinor;
  final int cashInMinor,bankInMinor,cashOutMinor,bankOutMinor;
  final int transactionLines;

  factory SchoolCashflowSummary.fromJson(Map<String,dynamic> x)=>
    SchoolCashflowSummary(
      inflowMinor:feeInt(x['inflow_minor']),
      outflowMinor:feeInt(x['outflow_minor']),
      netMinor:feeInt(x['net_movement_minor']),
      studentFeeMinor:feeInt(x['student_fee_minor']),
      otherFeeMinor:feeInt(x['other_fee_minor']),
      canteenMinor:feeInt(x['canteen_minor']),
      uniformMinor:feeInt(x['uniform_minor']),
      expenseMinor:feeInt(x['expense_minor']),
      salaryMinor:feeInt(x['salary_minor']),
      feeRefundMinor:feeInt(x['fee_refund_minor']),
      cashInMinor:feeInt(x['cash_in_minor']),
      bankInMinor:feeInt(x['bank_in_minor']),
      cashOutMinor:feeInt(x['cash_out_minor']),
      bankOutMinor:feeInt(x['bank_out_minor']),
      transactionLines:feeInt(x['transaction_lines']),
    );

  bool get reconciles =>
    inflowMinor-outflowMinor==netMinor &&
    inflowMinor==studentFeeMinor+otherFeeMinor+canteenMinor+uniformMinor &&
    outflowMinor==expenseMinor+salaryMinor+feeRefundMinor &&
    cashInMinor+bankInMinor==inflowMinor &&
    cashOutMinor+bankOutMinor==outflowMinor;
}

class SchoolCashflowEntry {
  const SchoolCashflowEntry({required this.date,required this.source,
    required this.kind,required this.reference,required this.counterparty,
    required this.category,required this.method,required this.signedMinor});
  final String date,source,kind,reference,counterparty,category,method;
  final int signedMinor;
  factory SchoolCashflowEntry.fromJson(Map<String,dynamic> x) =>
    SchoolCashflowEntry(
      date:x['date'].toString(),source:x['source'] as String,
      kind:x['kind'] as String,reference:x['reference'] as String,
      counterparty:x['counterparty'] as String,
      category:x['category'] as String,method:x['method'] as String,
      signedMinor:feeInt(x['signed_minor']),
    );
}

class SchoolCashflowDay {
  const SchoolCashflowDay(this.date,this.inflowMinor,this.outflowMinor,this.netMinor);
  final String date;
  final int inflowMinor,outflowMinor,netMinor;
  factory SchoolCashflowDay.fromJson(Map<String,dynamic> x) =>
    SchoolCashflowDay(x['date'].toString(),feeInt(x['inflow_minor']),
      feeInt(x['outflow_minor']),feeInt(x['net_minor']));
}

class SchoolCashflowChoice {
  const SchoolCashflowChoice(this.id,this.name,
      {this.startsOn,this.endsOn});
  final String id,name;
  final String? startsOn,endsOn;
  factory SchoolCashflowChoice.fromJson(Map<String,dynamic> x)=>
    SchoolCashflowChoice(x['id'] as String,
      (x['name']??x['label']) as String,
      startsOn:x['starts_on'] as String?,
      endsOn:x['ends_on'] as String?);
}

class SchoolCashflowReport {
  const SchoolCashflowReport({
    required this.schoolId,required this.campusId,required this.yearId,
    required this.from,required this.to,required this.timezone,
    required this.currency,required this.summary,required this.daily,
    required this.entries,required this.cancelledRetailMinor,
    required this.cancelledRetailCount,required this.directStockCostMinor,
    required this.pendingExpenseRequests,required this.unbalancedFeeReceipts,
    required this.campuses,required this.years,required this.scopeNote,
  });
  final String schoolId,yearId,from,to,timezone,currency,scopeNote;
  final String? campusId;
  final SchoolCashflowSummary summary;
  final List<SchoolCashflowDay> daily;
  final List<SchoolCashflowEntry> entries;
  final int cancelledRetailMinor,cancelledRetailCount,directStockCostMinor;
  final int pendingExpenseRequests,unbalancedFeeReceipts;
  final List<SchoolCashflowChoice> campuses,years;

  factory SchoolCashflowReport.fromJson(Map<String,dynamic> x) =>
    SchoolCashflowReport(
      schoolId:x['school_id'] as String,campusId:x['campus_id'] as String?,
      yearId:x['year_id'] as String,from:x['from'].toString(),
      to:x['to'].toString(),timezone:x['timezone'] as String,
      currency:x['currency'] as String,scopeNote:x['scope_note'] as String,
      summary:SchoolCashflowSummary.fromJson(
        Map<String,dynamic>.from(x['summary'] as Map)),
      daily:List.unmodifiable([
        for(final y in feeRows(x['daily']))SchoolCashflowDay.fromJson(y)]),
      entries:List.unmodifiable([
        for(final y in feeRows(x['entries']))SchoolCashflowEntry.fromJson(y)]),
      cancelledRetailMinor:feeInt(x['cancelled_retail_minor']),
      cancelledRetailCount:feeInt(x['cancelled_retail_count']),
      directStockCostMinor:feeInt(x['direct_stock_cost_minor']),
      pendingExpenseRequests:feeInt(x['pending_expense_requests']),
      unbalancedFeeReceipts:feeInt(x['unbalanced_fee_receipts']),
      campuses:List.unmodifiable([
        for(final y in feeRows(x['campus_options']))
          SchoolCashflowChoice.fromJson(y)]),
      years:List.unmodifiable([
        for(final y in feeRows(x['year_options']))
          SchoolCashflowChoice.fromJson(y)]),
    );

  static String _safeCell(String s) {
    final isFormula=RegExp(r'^[\s]*[=+\-@\t\r]').hasMatch(s);
    final safe=isFormula?"'"+s:s;
    return '"'+safe.replaceAll('"','""')+'"';
  }
  String toCsv(){
    final rows=<String>[
      'Date,Source,Reference,Counterparty,Category,Payment Method,'
        'Inflow ('+currency+'),Outflow ('+currency+')',
      for(final e in entries)
        [e.date,e.source,e.reference,e.counterparty,e.category,e.method,
          (e.signedMinor>0?e.signedMinor/100:0.0).toStringAsFixed(2),
          (e.signedMinor<0?-e.signedMinor/100:0.0).toStringAsFixed(2),
        ].map(_safeCell).join(','),
    ];
    return rows.join('\n');
  }
}

abstract class SchoolCashflowRepository {
  const SchoolCashflowRepository();
  Future<SchoolCashflowReport> load({
    required String schoolId,required String yearId,
    String? campusId,required String from,required String to,
  });
}

class SupabaseSchoolCashflowRepository implements SchoolCashflowRepository {
  const SupabaseSchoolCashflowRepository(this.client);
  final SupabaseClient client;
  @override
  Future<SchoolCashflowReport> load({required String schoolId,
    required String yearId,String? campusId,required String from,
    required String to})async{
    if(client.auth.currentSession==null){
      throw StateError('Verified School Owner login required');
    }
    final start=DateTime.tryParse(from),end=DateTime.tryParse(to);
    if(start==null||end==null||end.isBefore(start)||
      end.difference(start).inDays>92) {
      throw const FormatException('Invalid financial report dates');
    }
    final result=await client.rpc('school_cashflow_report',params:{
      'p_school':schoolId,'p_campus':campusId,'p_year':yearId,
      'p_from':from,'p_to':to,
    });
    if(result is! Map)throw StateError('Unexpected report payload');
    final data=SchoolCashflowReport.fromJson(Map<String,dynamic>.from(result));
    if(data.schoolId!=schoolId||data.campusId!=campusId||
       data.yearId!=yearId||data.from!=from||data.to!=to) {
      throw StateError('Report scope does not match requested school');
    }
    if(!data.summary.reconciles){
      throw StateError('Posted financial movement totals do not reconcile');
    }
    return data;
  }
}
