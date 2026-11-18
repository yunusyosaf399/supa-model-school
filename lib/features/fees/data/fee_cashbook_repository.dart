import 'package:supabase_flutter/supabase_flutter.dart';

import 'fee_payment_repository.dart';

/// Fee receipts: students and non-student payers. Not a full P&L or general ledger.
class FeeCashbookSummary {
  const FeeCashbookSummary({
    required this.amountMinor,required this.cashMinor,required this.bankMinor,
    required this.studentMinor,required this.otherMinor,
    required this.receiptCount,required this.allocationLines,
  });
  final int amountMinor,cashMinor,bankMinor,studentMinor,otherMinor;
  final int receiptCount,allocationLines;
  factory FeeCashbookSummary.fromJson(Map<String,dynamic> x) =>
    FeeCashbookSummary(
      amountMinor:feeInt(x['amount_minor']),cashMinor:feeInt(x['cash_minor']),
      bankMinor:feeInt(x['bank_minor']),studentMinor:feeInt(x['student_minor']),
      otherMinor:feeInt(x['other_minor']),receiptCount:feeInt(x['receipt_count']),
      allocationLines:feeInt(x['allocation_lines']));
  bool get totalsReconcile => amountMinor==cashMinor+bankMinor &&
    amountMinor==studentMinor+otherMinor;
}
class FeeCashbookDay {
  const FeeCashbookDay({required this.date,required this.amountMinor,
    required this.cashMinor,required this.bankMinor,required this.studentMinor,
    required this.otherMinor});
  final String date;
  final int amountMinor,cashMinor,bankMinor,studentMinor,otherMinor;
  factory FeeCashbookDay.fromJson(Map<String,dynamic> x) =>FeeCashbookDay(
    date:x['date'].toString(),amountMinor:feeInt(x['amount_minor']),
    cashMinor:feeInt(x['cash_minor']),bankMinor:feeInt(x['bank_minor']),
    studentMinor:feeInt(x['student_minor']),otherMinor:feeInt(x['other_minor']));
}
class FeeCashbookCategory {
  const FeeCashbookCategory(this.id,this.name,this.frequency,this.amountMinor);
  final String id,name,frequency;
  final int amountMinor;
  factory FeeCashbookCategory.fromJson(Map<String,dynamic> x) =>
    FeeCashbookCategory(x['id'] as String,x['name'] as String,
      x['frequency'] as String,feeInt(x['amount_minor']));
}
class FeeCashbookOption {
  const FeeCashbookOption(this.id,this.label,{this.campusId});
  final String id,label;
  final String? campusId;
  factory FeeCashbookOption.fromJson(Map<String,dynamic> x) =>
    FeeCashbookOption(x['id'] as String,
      (x['label']??x['name']) as String,
      campusId:x['campus_id'] as String?);
}
class FeeCashbookEntry {
  const FeeCashbookEntry({required this.source,required this.receiptId,
    required this.receiptNo,required this.campusId,required this.date,
    required this.method,required this.payerName,required this.payerReference,
    required this.categoryId,required this.categoryName,
    required this.amountMinor,this.className,this.classId});
  final String source,receiptId,receiptNo,campusId,date,method;
  final String payerName,payerReference,categoryId,categoryName;
  final String? className,classId;
  final int amountMinor;
  factory FeeCashbookEntry.fromJson(Map<String,dynamic> x)=>FeeCashbookEntry(
    source:x['source'] as String,receiptId:x['receipt_id'] as String,
    receiptNo:x['receipt_no'] as String,campusId:x['campus_id'] as String,
    date:x['date'].toString(),method:x['method'] as String,
    payerName:x['payer_name'] as String,
    payerReference:x['payer_reference'] as String? ?? '',
    categoryId:x['category_id'] as String,
    categoryName:x['category'] as String,
    amountMinor:feeInt(x['amount_minor']),
    className:x['class_name'] as String?,
    classId:x['class_id'] as String?);
}
class FeeCashbookReport {
  const FeeCashbookReport({required this.schoolId,required this.yearId,
    required this.campusId,required this.currency,required this.timezone,
    required this.from,required this.to,required this.method,
    required this.source,required this.summary,required this.daily,
    required this.categoryTotals,required this.entries,
    required this.yearOptions,required this.campusOptions,
    required this.categoryOptions,required this.classOptions,
    required this.unbalancedReceipts});
  final String schoolId,yearId,currency,timezone,from,to,method,source;
  final String? campusId;
  final FeeCashbookSummary summary;
  final List<FeeCashbookDay> daily;
  final List<FeeCashbookCategory> categoryTotals;
  final List<FeeCashbookEntry> entries;
  final List<FeeCashbookOption> yearOptions,campusOptions;
  final List<FeeCashbookOption> categoryOptions,classOptions;
  final int unbalancedReceipts;

  factory FeeCashbookReport.fromJson(Map<String,dynamic> x)=>FeeCashbookReport(
    schoolId:x['school_id'] as String,yearId:x['year_id'] as String,
    campusId:x['campus_id'] as String?,currency:x['currency'] as String,
    timezone:x['timezone'] as String,from:x['from'].toString(),
    to:x['to'].toString(),method:x['method'] as String,
    source:x['source'] as String,
    summary:FeeCashbookSummary.fromJson(
      Map<String,dynamic>.from(x['summary'] as Map)),
    daily:List.unmodifiable([for(final row in feeRows(x['daily']))
      FeeCashbookDay.fromJson(row)]),
    categoryTotals:List.unmodifiable([for(final row in feeRows(x['category_totals']))
      FeeCashbookCategory.fromJson(row)]),
    entries:List.unmodifiable([for(final row in feeRows(x['entries']))
      FeeCashbookEntry.fromJson(row)]),
    yearOptions:List.unmodifiable([for(final row in feeRows(x['year_options']))
      FeeCashbookOption.fromJson(row)]),
    campusOptions:List.unmodifiable([for(final row in feeRows(x['campus_options']))
      FeeCashbookOption.fromJson(row)]),
    categoryOptions:List.unmodifiable([for(final row in feeRows(x['category_options']))
      FeeCashbookOption.fromJson(row)]),
    classOptions:List.unmodifiable([for(final row in feeRows(x['class_options']))
      FeeCashbookOption.fromJson(row)]),
    unbalancedReceipts:feeInt(x['unbalanced_receipts']));

  static String _cell(String text){
    // Prevent spreadsheet formula injection when copying untrusted payer names.
    final unsafe=RegExp(r'^[\s]*[=+\-@\t\r]');
    final safe=unsafe.hasMatch(text) ? "'"+text : text;
    return '"'+safe.replaceAll('"','""')+'"';
  }
  String toCsv(){
    final rows=<String>[
      'Date,Receipt,Source,Payer,Reference,Class,Category,Method,'
      'Allocated Amount ('+currency+')',
      for(final e in entries)
        [e.date,e.receiptNo,e.source,e.payerName,e.payerReference,
          e.className??'',e.categoryName,e.method,
          (e.amountMinor/100).toStringAsFixed(2)].map(_cell).join(','),
    ];
    return rows.join('\n');
  }
}
abstract class FeeCashbookRepository {
  const FeeCashbookRepository();
  Future<FeeCashbookReport> load({required String schoolId,
    required String yearId,required String from,required String to,
    required String method,required String source,
    String? campusId,String? categoryId,String? classId});
}
class SupabaseFeeCashbookRepository implements FeeCashbookRepository {
  const SupabaseFeeCashbookRepository(this.client);
  final SupabaseClient client;
  @override
  Future<FeeCashbookReport> load({required String schoolId,
    required String yearId,required String from,required String to,
    required String method,required String source,
    String? campusId,String? categoryId,String? classId})async{
    if(client.auth.currentSession==null) {
      throw StateError('Sign in with a permitted school finance account');
    }
    final start=DateTime.tryParse(from),end=DateTime.tryParse(to);
    if(start==null||end==null||end.isBefore(start)||
       end.difference(start).inDays>92||
       !{'all','cash','bank'}.contains(method)||
       !{'all','student','other'}.contains(source)){
      throw const FormatException('Invalid cashbook range or filters');
    }
    final data=await client.rpc('fee_collection_cashbook',params:{
      'p_school':schoolId,'p_campus':campusId,'p_year':yearId,
      'p_from':from,'p_to':to,'p_method':method,'p_source':source,
      'p_category':categoryId,'p_class':classId});
    if(data is! Map)throw StateError('Invalid cashbook result');
    final report=FeeCashbookReport.fromJson(Map<String,dynamic>.from(data));
    if(report.schoolId!=schoolId||report.campusId!=campusId||
       report.yearId!=yearId||report.from!=from||report.to!=to||
       report.method!=method||report.source!=source) {
      throw StateError('Cashbook returned a different school/date range');
    }
    if(!report.summary.totalsReconcile){
      throw StateError('Receipt collection totals do not reconcile');
    }
    return report;
  }
}
