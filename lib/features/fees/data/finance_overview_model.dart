import 'fee_cashbook_repository.dart';
import 'fee_payment_repository.dart';
import 'school_cashflow_repository.dart';

/// Rolling six-month overview, assembled from existing, authorized
/// read-only financial reports. All amounts remain integer minor units.
class FinanceOverviewWindow {
  const FinanceOverviewWindow(this.start,this.end);
  final DateTime start,end;
}

String financeDay(DateTime d)=>d.year.toString().padLeft(4,'0')+'-'+
  d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
String financeMonth(DateTime d)=>d.year.toString().padLeft(4,'0')+'-'+
  d.month.toString().padLeft(2,'0');
const financeMonthNames=[
  'Jan','Feb','Mar','Apr','May','Jun',
  'Jul','Aug','Sep','Oct','Nov','Dec',
];

List<FinanceOverviewWindow> financeOverviewWindows(
    DateTime today,{DateTime? academicStart,DateTime? academicEnd}){
  final last=DateTime(today.year,today.month,today.day);
  final first=DateTime(today.year,today.month-5,1);
  final windows=<FinanceOverviewWindow>[];
  for(var n=0;n<6;n+=2){
    var from=DateTime(first.year,first.month+n,1);
    var to=DateTime(first.year,first.month+n+2,0);
    if(from.isBefore(first))from=first;
    if(academicStart!=null&&from.isBefore(academicStart))from=academicStart;
    if(to.isAfter(last))to=last;
    if(academicEnd!=null&&to.isAfter(academicEnd))to=academicEnd;
    if(to.isBefore(from))continue;
    // Each two-month window is at most 62 days; both repositories impose
    // a 93-day limit per RPC.
    windows.add(FinanceOverviewWindow(from,to));
  }
  return List.unmodifiable(windows);
}

class FinanceTrendMonth {
  const FinanceTrendMonth(this.month,this.amountMinor);
  final String month;
  final int amountMinor;
  String get label{
    final value=DateTime.tryParse(month+'-01');
    if(value==null)return month;
    return financeMonthNames[value.month-1]+' '+value.year.toString();
  }
}

class FinanceOverviewTransaction {
  const FinanceOverviewTransaction({
    required this.date,required this.source,required this.reference,
    required this.counterparty,required this.category,
    required this.amountMinor,required this.method});
  final String date,source,reference,counterparty,category,method;
  final int amountMinor;
  bool get isIncome=>amountMinor>=0;
  bool get isSalary=>source.toLowerCase().contains('salary')||
    source.toLowerCase().contains('payroll')||
    category.toLowerCase().contains('salary');
  bool get isExpense=>!isIncome&&!isSalary;
}

class FinanceOverviewSnapshot {
  const FinanceOverviewSnapshot({
    required this.currency,required this.periodStart,
    required this.periodEnd,required this.collectedMinor,
    required this.pendingMinor,required this.tuitionMinor,
    required this.transportMinor,required this.otherFeesMinor,
    required this.salariesMinor,required this.expensesMinor,
    required this.trend,required this.transactions,
    required this.feeReceiptCount,
  });

  final String currency,periodStart,periodEnd;
  final int collectedMinor,pendingMinor,tuitionMinor,transportMinor;
  final int otherFeesMinor,salariesMinor,expensesMinor,feeReceiptCount;
  final List<FinanceTrendMonth> trend;
  final List<FinanceOverviewTransaction> transactions;

  static FinanceOverviewSnapshot fromReports({
    required DateTime today,
    required FeePaymentWorkspace workspace,
    required List<FeeCashbookReport> cashbooks,
    required List<SchoolCashflowReport> cashflows,
    required String periodStart,
    required String periodEnd,
  }){
    for(final c in cashbooks){
      if(c.schoolId!=workspace.schoolId||
         c.campusId!=workspace.campusId||
         c.yearId!=workspace.yearId||
         c.currency!=workspace.currency){
        throw StateError('Collection report is outside the selected scope');
      }
      if(!c.summary.totalsReconcile){
        throw StateError('Unreconciled fee collections');
      }
    }
    for(final m in cashflows){
      if(m.schoolId!=workspace.schoolId||
         m.campusId!=workspace.campusId||
         m.yearId!=workspace.yearId||
         m.currency!=workspace.currency||
         !m.summary.reconciles){
        throw StateError('Unreconciled or out-of-scope cash movement');
      }
    }

    int sumCashbook(int Function(FeeCashbookReport) select)=>
      cashbooks.fold<int>(0,(n,r)=>n+select(r));
    int sumMovement(int Function(SchoolCashflowReport) select)=>
      cashflows.fold<int>(0,(n,r)=>n+select(r));

    final tuitionCodes=<String>{},transportCodes=<String>{};
    for(final c in workspace.categories){
      final code=c.code.toUpperCase();
      if(code.contains('TUITION'))tuitionCodes.add(c.id);
      if(code.contains('TRANSPORT'))transportCodes.add(c.id);
    }
    final categoryCash=<String,int>{};
    for(final r in cashbooks){
      for(final c in r.categoryTotals){
        categoryCash.update(c.id,(value)=>value+c.amountMinor,
          ifAbsent:()=>c.amountMinor);
      }
    }
    final collected=sumCashbook((r)=>r.summary.amountMinor);
    int groupSum(Set<String> ids)=>ids.fold<int>(0,
      (sum,id)=>sum+(categoryCash[id]??0));
    final tuition=groupSum(tuitionCodes);
    final transport=groupSum(transportCodes);
    if(tuition<0||transport<0||tuition+transport>collected){
      throw StateError('Fee collection categories cannot be reconciled');
    }
    final pending=workspace.students.fold<int>(0,
      (sum,s)=>sum+s.charges.fold<int>(0,
        (amount,c)=>amount+(c.outstandingMinor>0?c.outstandingMinor:0)));

    final first=DateTime(today.year,today.month-5,1);
    final months=<String,int>{
      for(var i=0;i<6;i++)financeMonth(DateTime(first.year,first.month+i,1)):0,
    };
    for(final r in cashbooks){
      for(final day in r.daily){
        if(day.date.length<7)continue;
        final month=day.date.substring(0,7);
        if(months.containsKey(month)){
          months[month]=months[month]!+day.amountMinor;
        }
      }
    }

    final entries=<FinanceOverviewTransaction>[
      for(final report in cashflows)
        for(final e in report.entries)
          FinanceOverviewTransaction(date:e.date,source:e.source,
            reference:e.reference,counterparty:e.counterparty,
            category:e.category,method:e.method,amountMinor:e.signedMinor),
    ]..sort((a,b){
      final date=b.date.compareTo(a.date);
      return date!=0?date:b.reference.compareTo(a.reference);
    });

    return FinanceOverviewSnapshot(
      currency:workspace.currency,periodStart:periodStart,
      periodEnd:periodEnd,collectedMinor:collected,
      pendingMinor:pending,tuitionMinor:tuition,
      transportMinor:transport,otherFeesMinor:collected-tuition-transport,
      salariesMinor:sumMovement((m)=>m.summary.salaryMinor),
      expensesMinor:sumMovement((m)=>m.summary.expenseMinor),
      feeReceiptCount:sumCashbook((r)=>r.summary.receiptCount),
      trend:List.unmodifiable([
        for(final entry in months.entries)
          FinanceTrendMonth(entry.key,entry.value),
      ]),
      transactions:List.unmodifiable(entries),
    );
  }
}
