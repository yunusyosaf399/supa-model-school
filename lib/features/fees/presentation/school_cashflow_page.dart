import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/school_cashflow_repository.dart';
import '../data/fee_setup_repository.dart';

String _cashDate(DateTime d)=>d.year.toString().padLeft(4,'0')+'-'+
 d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
String _cashAmount(int minor,String currency)=>currency+' '+FeeMoney.showMinor(minor);

class SchoolCashflowPage extends StatefulWidget {
  const SchoolCashflowPage({super.key,required this.repository,
    required this.schoolId,required this.yearId,this.initialCampusId});
  final SchoolCashflowRepository repository;
  final String schoolId,yearId;
  final String? initialCampusId;
  @override State<SchoolCashflowPage> createState()=>_SchoolCashflowPageState();
}

class _SchoolCashflowPageState extends State<SchoolCashflowPage>{
  SchoolCashflowReport? report;
  String? error,yearId,campusId;
  late DateTime from,to;
  bool busy=false;
  int request=0;

  @override void initState(){
    super.initState();
    yearId=widget.yearId;campusId=widget.initialCampusId;
    final now=DateTime.now();
    to=DateTime(now.year,now.month,now.day);
    from=to.subtract(const Duration(days:29));
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)load();});
  }
  @override void didUpdateWidget(covariant SchoolCashflowPage old){
    super.didUpdateWidget(old);
    if(old.schoolId!=widget.schoolId||old.yearId!=widget.yearId||
       old.initialCampusId!=widget.initialCampusId){
      report=null;yearId=widget.yearId;campusId=widget.initialCampusId;
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)load();});
    }
  }
  Future<void> load()async{
    final token=++request;
    setState((){busy=true;error=null;});
    try{
      final value=await widget.repository.load(
        schoolId:widget.schoolId,yearId:yearId!,
        campusId:campusId,from:_cashDate(from),to:_cashDate(to));
      if(!mounted||token!=request)return;
      setState((){busy=false;report=value;});
    }catch(e){
      if(!mounted||token!=request)return;
      setState((){
        busy=false;report=null;
        error='Unable to read school finance: '+e.toString();
      });
    }
  }
  void update(VoidCallback change){
    if(busy)return;
    setState((){change();report=null;error=null;});
    load();
  }
  void preset(int days){
    final now=DateTime.now();
    final end=DateTime(now.year,now.month,now.day);
    update((){to=end;from=end.subtract(Duration(days:days-1));});
  }
  Future<void> dates()async{
    if(busy)return;
    SchoolCashflowChoice? current;
    for(final y in report?.years??const <SchoolCashflowChoice>[]){
      if(y.id==yearId)current=y;
    }
    final first=DateTime.tryParse(current?.startsOn??'')??DateTime(2015);
    final end=DateTime.tryParse(current?.endsOn??'')??DateTime(2100);
    final now=DateTime.now();
    final last=end.isAfter(now)?now:end;
    if(last.isBefore(first))return;
    var start=from.isBefore(first)?first:from;
    if(start.isAfter(last))start=last;
    var stop=to.isAfter(last)?last:to;
    if(stop.isBefore(start))stop=start;
    final period=await showDateRangePicker(context:context,
      firstDate:first,lastDate:last,
      initialDateRange:DateTimeRange(start:start,end:stop),
      helpText:'Posted cash movements • Max 93 days');
    if(!mounted||period==null)return;
    if(period.end.difference(period.start).inDays>92){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Choose at most 93 days.')));
      return;
    }
    update((){from=period.start;to=period.end;});
  }
  Widget metric(String label,int minor,String currency)=>Card.outlined(
    child:Padding(padding:const EdgeInsets.all(12),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(label,style:Theme.of(context).textTheme.bodyMedium),
        Text(_cashAmount(minor,currency),
          style:Theme.of(context).textTheme.titleMedium),
      ])));

  @override Widget build(BuildContext context){
    final data=report;
    final summary=data?.summary;
    return RefreshIndicator(onRefresh:load,child:ListView(
      key:const Key('school-cashflow-page'),
      padding:const EdgeInsets.all(14),children:[
        Wrap(alignment:WrapAlignment.spaceBetween,runSpacing:8,
          crossAxisAlignment:WrapCrossAlignment.center,children:[
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('School Cash Movement',
              style:Theme.of(context).textTheme.headlineSmall),
            const Text('Owner • Posted transactions, not a profit statement'),
          ]),
          IconButton(key:const Key('school-cashflow-refresh'),
            tooltip:'Refresh',onPressed:busy?null:load,
            icon:const Icon(Icons.refresh)),
        ]),
        const SizedBox(height:8),
        const Text('Fee receipts, non-student fees, unreversed retail '
          'sales, approved paid expenses and salary payments. '
          'This is NOT net profit or an audited bank balance.'),
        const SizedBox(height:12),
        Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton(key:const Key('school-cashflow-today'),
            onPressed:busy?null:()=>preset(1),child:const Text('Today')),
          OutlinedButton(key:const Key('school-cashflow-week'),
            onPressed:busy?null:()=>preset(7),child:const Text('Last 7 Days')),
          OutlinedButton(key:const Key('school-cashflow-month'),
            onPressed:busy?null:()=>preset(30),child:const Text('Last 30 Days')),
          OutlinedButton.icon(key:const Key('school-cashflow-dates'),
            onPressed:busy?null:dates,
            icon:const Icon(Icons.date_range_outlined),
            label:const Text('Dates')),
          if(data!=null)OutlinedButton.icon(
            key:const Key('school-cashflow-copy-csv'),
            onPressed:(){
              Clipboard.setData(ClipboardData(text:data.toCsv()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content:Text('Transactions copied as CSV')));
            },icon:const Icon(Icons.copy_all_outlined),
            label:const Text('Copy CSV')),
        ]),
        Text('Period: '+_cashDate(from)+' to '+_cashDate(to)+
          (data==null?'':' • '+data.timezone)),
        if(busy)const LinearProgressIndicator(),
        if(error!=null)ListTile(
          leading:const Icon(Icons.error_outline),title:Text(error!),
          trailing:TextButton(onPressed:load,child:const Text('Retry'))),
        if(data!=null)...[
          const SizedBox(height:10),
          Wrap(spacing:8,runSpacing:8,children:[
            SizedBox(width:215,child:DropdownButtonFormField<String>(
              key:const Key('school-cashflow-year'),value:yearId,
              isExpanded:true,decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Academic Year'),
              items:[for(final y in data.years)
                DropdownMenuItem(value:y.id,child:Text(y.name))],
              onChanged:busy?null:(v){
                if(v==null||v==yearId)return;
                final y=data.years.firstWhere((x)=>x.id==v);
                final first=DateTime.tryParse(y.startsOn??'');
                final last=DateTime.tryParse(y.endsOn??'');
                if(first==null||last==null)return;
                final now=DateTime.now();
                final end=last.isAfter(now)?now:last;
                update((){
                  yearId=v;to=end;
                  final candidate=end.subtract(const Duration(days:29));
                  from=candidate.isBefore(first)?first:candidate;
                });
              })),
            SizedBox(width:215,child:DropdownButtonFormField<String>(
              key:const Key('school-cashflow-campus'),value:campusId??'all',
              isExpanded:true,decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Campus'),
              items:[
                const DropdownMenuItem(value:'all',
                  child:Text('All Campuses')),
                for(final c in data.campuses)
                  DropdownMenuItem(value:c.id,child:Text(c.name)),
              ],
              onChanged:busy?null:(v)=>update((){
                campusId=v=='all'?null:v;
              }))),
          ]),
          const SizedBox(height:14),
          Text('Posted Money Movement',
            style:Theme.of(context).textTheme.titleLarge),
          LayoutBuilder(builder:(context,size){
            const gap=8.0;
            final columns=size.maxWidth>=950?3:size.maxWidth>=540?2:1;
            final width=(size.maxWidth-gap*(columns-1))/columns;
            final rows=<({String label,int amount})>[
              (label:'Money Received',amount:summary!.inflowMinor),
              (label:'Money Paid Out',amount:summary.outflowMinor),
              (label:'Net Posted Movement (Not Profit)',amount:summary.netMinor),
              (label:'Student Fee Receipts',amount:summary.studentFeeMinor),
              (label:'Other Payer Fee Receipts',amount:summary.otherFeeMinor),
              (label:'Canteen Collections',amount:summary.canteenMinor),
              (label:'Uniform Collections',amount:summary.uniformMinor),
              (label:'Approved Paid Expenses',amount:summary.expenseMinor),
              (label:'Salary Payments',amount:summary.salaryMinor),
              (label:'Fee Refunds',amount:summary.feeRefundMinor),
              (label:'Cash Received',amount:summary.cashInMinor),
              (label:'Bank Received',amount:summary.bankInMinor),
              (label:'Cash Paid Out',amount:summary.cashOutMinor),
              (label:'Bank Paid Out',amount:summary.bankOutMinor),
            ];
            return Wrap(spacing:gap,runSpacing:gap,children:[
              for(final m in rows)SizedBox(width:width,
                child:metric(m.label,m.amount,data.currency)),
            ]);
          }),
          ListTile(
            leading:Icon(summary!.reconciles&&data.unbalancedFeeReceipts==0
              ?Icons.verified_outlined:Icons.warning_amber_outlined),
            title:Text(summary.reconciles&&data.unbalancedFeeReceipts==0
              ?'Posted transaction amounts reconcile'
              :'Reconciliation requires attention'),
            subtitle:Text(summary.transactionLines.toString()+
              ' source entries • Fee receipt exceptions: '+
              data.unbalancedFeeReceipts.toString())),
          Card.outlined(child:Padding(padding:const EdgeInsets.all(12),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Accounting Notes',
                style:Theme.of(context).textTheme.titleMedium),
              Text('Cancelled retail sales excluded: '+
                _cashAmount(data.cancelledRetailMinor,data.currency)+
                ' ('+data.cancelledRetailCount.toString()+' cancellations)'),
              Text('Direct stock consumption (non-cash): '+
                _cashAmount(data.directStockCostMinor,data.currency)),
              Text('Pending expense requests excluded: '+
                data.pendingExpenseRequests.toString()),
              const Text('Stock cost is non-cash and is not subtracted '
                'again from movements. A sale cancellation is not '
                'proof that cash was refunded.'),
            ]))),
          const SizedBox(height:12),
          Text('Daily Inflows & Outflows',
            style:Theme.of(context).textTheme.titleLarge),
          if(data.daily.isEmpty)const Text('No posted transactions for this period.'),
          for(final day in data.daily)Card.outlined(child:ListTile(
            title:Text(day.date),
            subtitle:Text('In '+_cashAmount(day.inflowMinor,data.currency)+
              '\nOut '+_cashAmount(day.outflowMinor,data.currency)),
            isThreeLine:true,
            trailing:Text(_cashAmount(day.netMinor,data.currency)))),
          const SizedBox(height:12),
          Text('Posted Transaction Details',
            style:Theme.of(context).textTheme.titleLarge),
          for(final e in data.entries)Card.outlined(child:ListTile(
            title:Text(e.reference+' • '+e.counterparty,
              maxLines:2,overflow:TextOverflow.ellipsis),
            subtitle:Text(e.date+' • '+e.source+' • '+e.category+
              ' • '+e.method.toUpperCase()),
            trailing:Text(_cashAmount(e.signedMinor,data.currency)))),
          const SizedBox(height:10),
          Text(data.scopeNote,style:Theme.of(context).textTheme.bodySmall),
        ],
      ]));
  }
}
