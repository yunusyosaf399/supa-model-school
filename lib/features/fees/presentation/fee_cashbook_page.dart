import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fee_cashbook_repository.dart';
import '../data/fee_setup_repository.dart';

String _date(DateTime d)=>d.year.toString().padLeft(4,'0')+'-'+
  d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');

String _amount(int minor,String currency)=>
  currency+' '+FeeMoney.showMinor(minor);

class FeeCashbookPage extends StatefulWidget {
  const FeeCashbookPage({super.key,required this.repository,
    required this.schoolId,required this.yearId,
    required this.initialCampusId,this.allowAllCampuses=false});
  final FeeCashbookRepository repository;
  final String schoolId,yearId;
  final String? initialCampusId;
  final bool allowAllCampuses;

  @override State<FeeCashbookPage> createState()=>_FeeCashbookPageState();
}

class _FeeCashbookPageState extends State<FeeCashbookPage> {
  FeeCashbookReport? report;
  String? error,yearId,campusId,categoryId,classId;
  String method='all',source='all';
  late DateTime from,to;
  bool loading=false;
  int request=0;

  @override void initState(){
    super.initState();
    final now=DateTime.now();
    from=DateTime(now.year,now.month,now.day).subtract(
      const Duration(days:29));
    to=DateTime(now.year,now.month,now.day);
    yearId=widget.yearId;
    campusId=widget.initialCampusId;
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)load();});
  }
  @override void didUpdateWidget(covariant FeeCashbookPage old){
    super.didUpdateWidget(old);
    if(old.schoolId!=widget.schoolId||old.yearId!=widget.yearId||
      old.initialCampusId!=widget.initialCampusId||
      old.allowAllCampuses!=widget.allowAllCampuses){
      report=null;
      yearId=widget.yearId;
      campusId=widget.initialCampusId;
      categoryId=null;classId=null;
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)load();});
    }
  }
  Future<void> load()async{
    final seq=++request;
    setState((){loading=true;error=null;});
    try{
      final result=await widget.repository.load(
        schoolId:widget.schoolId,yearId:yearId!,
        campusId:campusId,from:_date(from),to:_date(to),
        method:method,source:source,
        categoryId:categoryId,classId:classId);
      if(!mounted||seq!=request)return;
      setState((){report=result;loading=false;});
    }catch(e){
      if(!mounted||seq!=request)return;
      setState((){
        loading=false;
        report=null;
        error='Unable to load fee cashbook: '+e.toString();
      });
    }
  }
  void changeFilters(VoidCallback action){
    if(loading)return;
    setState((){action();report=null;error=null;});
    load();
  }
  void preset(int days){
    final now=DateTime.now();
    final end=DateTime(now.year,now.month,now.day);
    changeFilters((){
      to=end;from=end.subtract(Duration(days:days-1));
    });
  }
  Future<void> pickRange()async{
    if(loading)return;
    final range=await showDateRangePicker(context:context,
      firstDate:DateTime(2015),lastDate:DateTime.now(),
      initialDateRange:DateTimeRange(start:from,end:to),
      helpText:'Select a fee collection date range (up to 93 days)',
      saveText:'Apply');
    if(!mounted||range==null)return;
    if(range.end.difference(range.start).inDays>92){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Choose up to 93 consecutive days.')));
      return;
    }
    changeFilters((){from=range.start;to=range.end;});
  }

  Widget selector(String key,String title,String value,
    List<DropdownMenuItem<String>> options,
    ValueChanged<String?> change)=>SizedBox(width:220,
      child:DropdownButtonFormField<String>(
        key:Key(key),value:value,isExpanded:true,
        decoration:InputDecoration(isDense:true,
          border:const OutlineInputBorder(),labelText:title),
        items:options,onChanged:loading?null:change));

  Widget metric(String title,int minor,String currency)=>Card.outlined(
    child:Padding(padding:const EdgeInsets.all(12),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:Theme.of(context).textTheme.bodySmall),
        Text(_amount(minor,currency),
          style:Theme.of(context).textTheme.titleMedium),
      ])));

  @override Widget build(BuildContext context){
    final data=report;
    final summary=data?.summary;
    final categoryOptions=data?.categoryOptions ??
      const <FeeCashbookOption>[];
    final classOptions=data?.classOptions ??const <FeeCashbookOption>[];
    final campusOptions=data?.campusOptions ??
      const <FeeCashbookOption>[];
    return RefreshIndicator(onRefresh:load,child:ListView(
      key:const Key('fee-cashbook-live-page'),
      padding:const EdgeInsets.all(14),children:[
        Wrap(alignment:WrapAlignment.spaceBetween,runSpacing:8,
          crossAxisAlignment:WrapCrossAlignment.center,children:[
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Fee Income & Collection Cashbook',
              style:Theme.of(context).textTheme.headlineSmall),
            const Text('Student + other payer receipts • Reconciled allocations'),
          ]),
          IconButton(
            key:const Key('fee-cashbook-refresh'),
            tooltip:'Refresh report',onPressed:loading?null:load,
            icon:const Icon(Icons.refresh)),
        ]),
        const SizedBox(height:8),
        const Text('This is a fee-receipt cashbook, not full school profit. '
          'It excludes uncollected bills, retail sales, expenses and '
          'other general-ledger transactions.'),
        const SizedBox(height:12),
        Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton(key:const Key('fee-cashbook-today'),
            onPressed:loading?null:()=>preset(1),
            child:const Text('Today')),
          OutlinedButton(key:const Key('fee-cashbook-week'),
            onPressed:loading?null:()=>preset(7),
            child:const Text('Last 7 Days')),
          OutlinedButton(key:const Key('fee-cashbook-month'),
            onPressed:loading?null:()=>preset(30),
            child:const Text('Last 30 Days')),
          OutlinedButton.icon(key:const Key('fee-cashbook-dates'),
            onPressed:loading?null:pickRange,
            icon:const Icon(Icons.date_range_outlined),
            label:const Text('Select Dates')),
          if(data!=null)OutlinedButton.icon(
            key:const Key('fee-cashbook-copy-csv'),
            onPressed:(){
              Clipboard.setData(ClipboardData(text:data.toCsv()));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content:Text('Receipt allocations copied as CSV')));
            },icon:const Icon(Icons.copy_all_outlined),
            label:const Text('Copy CSV')),
        ]),
        Text('Period: '+_date(from)+' to '+_date(to)+
          (data==null?'':' • '+data.timezone)),
        const SizedBox(height:8),
        if(loading)const LinearProgressIndicator(),
        if(error!=null)ListTile(
          leading:const Icon(Icons.error_outline),title:Text(error!),
          trailing:TextButton(onPressed:load,child:const Text('Retry'))),
        if(data!=null)...[
          const SizedBox(height:6),
          Wrap(spacing:10,runSpacing:10,children:[
            selector('fee-cashbook-year','Academic Year',yearId!,[
              for(final y in data.yearOptions)
                DropdownMenuItem(value:y.id,child:Text(y.label)),
            ],(v){if(v!=null)changeFilters((){
              yearId=v;classId=null;
            });}),
            if(widget.allowAllCampuses)
              selector('fee-cashbook-campus','Campus',campusId??'all',[
                const DropdownMenuItem(value:'all',
                  child:Text('All campuses')),
                for(final c in campusOptions)
                  DropdownMenuItem(value:c.id,child:Text(c.label)),
              ],(v)=>changeFilters((){
                campusId=v=='all'?null:v;classId=null;
              })),
            selector('fee-cashbook-source','Payer Type',source,const [
              DropdownMenuItem(value:'all',child:Text('All fee payers')),
              DropdownMenuItem(value:'student',child:Text('Students')),
              DropdownMenuItem(value:'other',child:Text('Other payers')),
            ],(v){if(v!=null)changeFilters((){
              source=v;
              if(v=='other')classId=null;
            });}),
            selector('fee-cashbook-method','Payment Method',method,const [
              DropdownMenuItem(value:'all',child:Text('Cash + Bank')),
              DropdownMenuItem(value:'cash',child:Text('Cash')),
              DropdownMenuItem(value:'bank',child:Text('Bank')),
            ],(v){if(v!=null)changeFilters(()=>method=v);}),
            selector('fee-cashbook-category','Category',categoryId??'all',[
              const DropdownMenuItem(value:'all',
                child:Text('All categories')),
              for(final c in categoryOptions)
                DropdownMenuItem(value:c.id,child:Text(c.label,
                  overflow:TextOverflow.ellipsis)),
            ],(v)=>changeFilters(()=>categoryId=v=='all'?null:v)),
            if(source!='other')selector(
              'fee-cashbook-class','Student Class',classId??'all',[
                const DropdownMenuItem(value:'all',
                  child:Text('All classes')),
                for(final c in classOptions)
                  DropdownMenuItem(value:c.id,child:Text(c.label)),
              ],(v)=>changeFilters(()=>classId=v=='all'?null:v)),
          ]),
          const SizedBox(height:14),
          Text('Collection Totals',style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:5),
          LayoutBuilder(builder:(context,size){
            final columns=size.maxWidth>=920?3:
              size.maxWidth>=540?2:1;
            const gap=8.0;
            final width=(size.maxWidth-gap*(columns-1))/columns;
            final rows=<({String label,int minor})>[
              (label:'Total Fee Collections',minor:summary!.amountMinor),
              (label:'Cash Collected',minor:summary.cashMinor),
              (label:'Bank Collected',minor:summary.bankMinor),
              (label:'Student Fees',minor:summary.studentMinor),
              (label:'Other Payer Fees',minor:summary.otherMinor),
            ];
            return Wrap(spacing:gap,runSpacing:gap,children:[
              for(final row in rows)
                SizedBox(width:width,
                  child:metric(row.label,row.minor,data.currency)),
            ]);
          }),
          ListTile(
            leading:Icon(data.unbalancedReceipts==0 &&
                summary!.totalsReconcile
                ?Icons.verified_outlined:Icons.warning_amber_outlined),
            title:Text(data.unbalancedReceipts==0&&summary.totalsReconcile
              ?'Receipt allocations reconciled'
              :'Receipt reconciliation needs review'),
            subtitle:Text(summary.receiptCount.toString()+
              ' distinct receipts • '+summary.allocationLines.toString()+
              ' allocation lines • '+
              data.unbalancedReceipts.toString()+
              ' unmatched source receipts in period'),
          ),
          const SizedBox(height:10),
          Text('Daily Collections',
            style:Theme.of(context).textTheme.titleLarge),
          if(data.daily.isEmpty)
            const Text('No posted fee receipts for these filters.'),
          for(final day in data.daily)
            Card.outlined(
              key:Key('fee-cashbook-day-'+day.date),
              child:ListTile(
                title:Text(day.date),
                subtitle:Text('Cash '+_amount(day.cashMinor,data.currency)+
                  ' • Bank '+_amount(day.bankMinor,data.currency)+
                  '\nStudents '+_amount(day.studentMinor,data.currency)+
                  ' • Other '+_amount(day.otherMinor,data.currency)),
                isThreeLine:true,
                trailing:Text(_amount(day.amountMinor,data.currency)),
              )),
          const SizedBox(height:12),
          Text('Collections by Fee Category',
            style:Theme.of(context).textTheme.titleLarge),
          if(data.categoryTotals.isEmpty)
            const Text('No category collections for this period.'),
          for(final category in data.categoryTotals)
            ListTile(
              key:Key('fee-cashbook-category-'+category.id),
              title:Text(category.name),
              subtitle:Text(category.frequency),
              trailing:Text(_amount(category.amountMinor,data.currency)),
            ),
          const SizedBox(height:12),
          Text('Receipt Allocation Details',
            style:Theme.of(context).textTheme.titleLarge),
          const Text('One line per paid fee category; a receipt may appear '
            'several times when it pays multiple categories. '
            'The amounts are not duplicated in totals.'),
          if(data.entries.isEmpty)const Text('No matching receipts.'),
          for(final entry in data.entries)
            Card.outlined(
              key:Key('fee-cashbook-line-'+entry.receiptId+'-'+
                entry.categoryId),
              child:ListTile(
                title:Text(entry.receiptNo+' • '+entry.payerName),
                subtitle:Text(entry.date+' • '+entry.source.toUpperCase()+
                  ' • '+entry.categoryName+' • '+entry.method.toUpperCase()+
                  (entry.className==null?'':' • '+entry.className!)),
                trailing:Text(_amount(entry.amountMinor,data.currency)),
              )),
        ],
      ]));
  }
}
