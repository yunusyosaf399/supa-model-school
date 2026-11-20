import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../data/fee_demand_slip.dart';
import '../data/fee_payment_repository.dart';
import 'fee_demand_slip_pdf.dart';
import '../data/fee_setup_repository.dart';

/// Bulk read-only demand slip printer for one class or one class section.
/// Re-fetches authorized posted balances before every print/share operation.
class FeeBulkDemandSlipsPage extends StatefulWidget {
  const FeeBulkDemandSlipsPage({
    super.key,required this.repository,required this.initialWorkspace,
    this.initialClassId,this.initialSectionId,this.initialMonth});
  final FeePaymentRepository repository;
  final FeePaymentWorkspace initialWorkspace;
  final String? initialClassId,initialSectionId,initialMonth;
  @override State<FeeBulkDemandSlipsPage> createState()=>_FeeBulkDemandSlipsPageState();
}

class _FeeBulkDemandSlipsPageState extends State<FeeBulkDemandSlipsPage> {
  late FeePaymentWorkspace workspace;
  String? classId,sectionId,month,error,notice;
  bool includeArrears=true,loading=false,printing=false;
  int sequence=0;

  @override void initState(){
    super.initState();
    workspace=widget.initialWorkspace;
    classId=widget.initialClassId;
    sectionId=widget.initialSectionId;
    month=widget.initialMonth;
    _chooseMonth();
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)refresh();
    });
  }

  List<String> get months{
    final found=<String>{
      for(final s in workspace.students)
        for(final c in s.charges)
          if(c.month.length>=7)c.month.substring(0,7),
    }.toList()..sort();
    return found;
  }

  void _chooseMonth(){
    final choices=months;
    final current=DateTime.now();
    final now=current.year.toString().padLeft(4,'0')+'-'+
      current.month.toString().padLeft(2,'0');
    if(month!=null&&choices.contains(month))return;
    final past=choices.where((m)=>m.compareTo(now)<=0).toList();
    month=past.isNotEmpty?past.last:(choices.isNotEmpty?choices.last:null);
  }

  Future<void> refresh()async{
    final seq=++sequence;
    setState((){loading=true;error=null;notice=null;});
    try{
      final updated=await widget.repository.workspace(
        schoolId:widget.initialWorkspace.schoolId,
        campusId:widget.initialWorkspace.campusId,
        yearId:widget.initialWorkspace.yearId);
      if(!mounted||seq!=sequence)return;
      if(updated.schoolId!=widget.initialWorkspace.schoolId||
         updated.campusId!=widget.initialWorkspace.campusId||
         updated.yearId!=widget.initialWorkspace.yearId){
        throw StateError('Unexpected school, campus or year in fee records');
      }
      setState((){
        workspace=updated;loading=false;
        if(!workspace.students.any((s)=>s.classId==classId)){
          classId=null;sectionId=null;
        }else if(sectionId!=null&&!workspace.students.any(
          (s)=>s.classId==classId&&s.sectionId==sectionId)){
          sectionId=null;
        }
        _chooseMonth();
      });
    }catch(e){
      if(!mounted||seq!=sequence)return;
      setState((){
        loading=false;error='Cannot refresh posted fee balances: '+e.toString();
      });
    }
  }

  FeeDemandBatch? _preview(){
    if(month==null||classId==null)return null;
    try{
      return FeeDemandBatch.build(workspace:workspace,month:month!,
        classId:classId!,sectionId:sectionId,
        includeArrears:includeArrears);
    }on FormatException{return null;}
  }

  Future<void> print({String copy='both',bool share=false})async{
    if(printing||loading)return;
    final original=_preview();
    if(original==null||original.students.isEmpty)return;
    setState((){printing=true;error=null;notice=null;});
    try{
      // Never print an old preview without comparing it with live posted
      // balances. This also rejects access revoked since the screen opened.
      final latest=await widget.repository.workspace(
        schoolId:workspace.schoolId,campusId:workspace.campusId,
        yearId:workspace.yearId);
      if(!mounted)return;
      if(latest.schoolId!=workspace.schoolId||
          latest.campusId!=workspace.campusId||
          latest.yearId!=workspace.yearId){
        throw StateError('Fee workspace changed unexpectedly');
      }
      final updated=FeeDemandBatch.build(
        workspace:latest,month:original.month,
        classId:original.classId,sectionId:sectionId,
        includeArrears:includeArrears);
      // Compare exact charge-level allocations, not only totals: another
      // collector could reallocate the same total across categories.
      Map<String,String> signature(FeeDemandBatch b)=>{
        for(final student in b.students)
          student.id:student.lines.map((line)=>
            [line.chargeId,line.month,line.category,
             line.billedMinor,line.paidMinor,line.dueMinor]
              .join(':')).join('|'),
      };
      final before=signature(original);
      final after=signature(updated);
      if(before.length!=after.length||
          before.entries.any((e)=>after[e.key]!=e.value)){
        setState((){
          workspace=latest;
          notice='Student balances changed after the preview. '
            'Review the updated amounts and press Print again.';
        });
        return;
      }
      final selected=updated.students;
      final yes=await showDialog<bool>(context:context,builder:(ctx)=>
        AlertDialog(
          title:const Text('Confirm bulk demand slip printing'),
          content:Text(
            'Class: '+updated.className+
            (updated.sectionName==null?'':' · '+updated.sectionName!)+
            '\nBilling month: '+updated.month+
            '\nStudents with outstanding fees: '+selected.length.toString()+
            '\nCurrent month due: '+updated.currency+' '+
              FeeMoney.showMinor(updated.currentDueMinor)+
            '\nPrevious arrears due: '+updated.currency+' '+
              FeeMoney.showMinor(updated.arrearsDueMinor)+
            '\nTotal due: '+updated.currency+' '+
              FeeMoney.showMinor(updated.totalDueMinor)+
            '\nCopies: '+(copy=='both'?'Student and Office':copy)+
            '\n\nThese are unpaid fee demand notices, not receipts. '
            'No new charges or payments will be posted.'),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx,false),
              child:const Text('Cancel')),
            FilledButton(key:const Key('bulk-demand-confirm'),
              onPressed:()=>Navigator.pop(ctx,true),
              child:Text(share?'Share PDF':'Print Slips')),
          ]));
      if(!mounted||yes!=true)return;
      if(share){
        final bytes=await FeeDemandSlipPdf.build(
          updated,PdfPageFormat.a4,copy:copy);
        await Printing.sharePdf(bytes:bytes,
          filename:'fee_demand_'+updated.month+
            '_'+updated.className.replaceAll(RegExp(r'[^A-Za-z0-9_-]'),'_')+
            '_'+copy+'.pdf');
      }else{
        await Printing.layoutPdf(
          name:'Fee demand '+updated.className+' '+updated.month,
          onLayout:(format)=>FeeDemandSlipPdf.build(
            updated,format,copy:copy));
      }
      if(mounted)setState(()=>workspace=latest);
    }catch(e){
      if(mounted)setState(()=>error='Cannot print demand slips: '+e.toString());
    }finally{
      if(mounted)setState(()=>printing=false);
    }
  }

  @override Widget build(BuildContext context){
    final classes=<String,String>{
      for(final s in workspace.students)s.classId:s.className};
    final sections=<String,String>{
      for(final s in workspace.students)
        if(s.classId==classId&&s.sectionId!=null)
          s.sectionId!:s.sectionName??'Section'};
    final batch=_preview();
    Widget amount(String label,int value)=>Card.outlined(
      child:Padding(padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(label,style:Theme.of(context).textTheme.bodySmall),
          Text(workspace.currency+' '+FeeMoney.showMinor(value),
            style:Theme.of(context).textTheme.titleMedium),
        ])));
    return Scaffold(
      appBar:AppBar(title:const Text('Bulk Monthly Fee Demand Slips'),
        actions:[
          IconButton(key:const Key('bulk-demand-refresh'),
            tooltip:'Refresh posted balances',
            onPressed:loading||printing?null:refresh,
            icon:const Icon(Icons.refresh)),
        ]),
      body:ListView(key:const Key('bulk-fee-demand-page'),
        padding:const EdgeInsets.all(16),children:[
        Text('Print Monthly Fee Demand Slips',
          style:Theme.of(context).textTheme.headlineSmall),
        Text('Academic Year: '+workspace.yearLabel+' · '+
          workspace.currency+' · authorized campus'),
        const SizedBox(height:8),
        const Text('Select a class and optionally one section. '
          'Only students with outstanding posted charges are included. '
          'Students with fully paid fees are skipped. '
          'This does not generate or collect fees.'),
        if(loading)const LinearProgressIndicator(),
        if(error!=null)ListTile(
          title:Text(error!,style:TextStyle(
            color:Theme.of(context).colorScheme.error)),
          trailing:TextButton(onPressed:refresh,child:const Text('Retry'))),
        if(notice!=null)Card.outlined(child:ListTile(
          leading:const Icon(Icons.info_outline),title:Text(notice!))),
        const SizedBox(height:12),
        Wrap(spacing:10,runSpacing:10,children:[
          SizedBox(width:240,child:DropdownButtonFormField<String>(
            key:const Key('bulk-demand-month'),
            value:month,isExpanded:true,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Billing month'),
            items:[
              for(final m in months)
                DropdownMenuItem(value:m,child:Text(m)),
            ],
            onChanged:loading||printing?null:
              (v)=>setState(()=>month=v),
          )),
          SizedBox(width:245,child:DropdownButtonFormField<String>(
            key:const Key('bulk-demand-class'),
            value:classId,isExpanded:true,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Class (required)'),
            items:[
              for(final c in classes.entries)
                DropdownMenuItem(value:c.key,child:Text(c.value,
                  overflow:TextOverflow.ellipsis)),
            ],
            onChanged:loading||printing?null:(v)=>setState((){
              classId=v;sectionId=null;
            }),
          )),
          SizedBox(width:245,child:DropdownButtonFormField<String>(
            key:const Key('bulk-demand-section'),
            value:sectionId??'all',isExpanded:true,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Section'),
            items:[
              const DropdownMenuItem(value:'all',
                child:Text('All sections in class')),
              for(final e in sections.entries)
                DropdownMenuItem(value:e.key,child:Text(e.value)),
            ],
            onChanged:classId==null||loading||printing?null:
              (v)=>setState(()=>sectionId=v=='all'?null:v),
          )),
        ]),
        CheckboxListTile(
          key:const Key('bulk-demand-include-arrears'),
          value:includeArrears,
          title:const Text('Include unpaid balances from earlier months'),
          subtitle:const Text('Show prior arrears separately from '
            'the selected month, using current posted balances.'),
          onChanged:loading||printing?null:
            (v)=>setState(()=>includeArrears=v??true)),
        const SizedBox(height:10),
        if(classId==null)
          const Padding(padding:EdgeInsets.all(12),
            child:Text('Choose a class before printing demand slips.'))
        else if(batch!=null)...[
          Wrap(spacing:8,runSpacing:8,children:[
            amount('Current month unpaid',batch.currentDueMinor),
            amount('Previous unpaid arrears',batch.arrearsDueMinor),
            amount('Total outstanding',batch.totalDueMinor),
          ]),
          Text('Students with unpaid balances: '+
            batch.students.length.toString(),
            style:Theme.of(context).textTheme.titleMedium),
          Text('Copy count for both: '+
            (batch.students.length*2).toString()+
            ' (some students may require more than one page)'),
          if(batch.students.isEmpty)
            const Padding(padding:EdgeInsets.all(12),
              child:Text('No unpaid posted fees for this selection. '
                'Generate the monthly fee bills first if needed.')),
          for(final s in batch.students)
            Card.outlined(child:ListTile(
              key:Key('bulk-demand-student-'+s.registration),
              title:Text(s.name+' · '+s.registration),
              subtitle:Text(s.className+
                (s.sectionName==null?'':' · '+s.sectionName!)+
                '\nCurrent: '+workspace.currency+' '+
                FeeMoney.showMinor(s.currentDueMinor)+
                ' · Arrears: '+workspace.currency+' '+
                FeeMoney.showMinor(s.arrearsDueMinor)),
              trailing:Text(workspace.currency+' '+
                FeeMoney.showMinor(s.totalDueMinor)),
            )),
          const SizedBox(height:14),
          Wrap(spacing:8,runSpacing:8,children:[
            FilledButton.icon(
              key:const Key('bulk-demand-print-both'),
              onPressed:loading||printing||batch.students.isEmpty?
                null:()=>print(),
              icon:const Icon(Icons.print_outlined),
              label:const Text('Print Student & Office Copies')),
            OutlinedButton.icon(
              key:const Key('bulk-demand-share-both'),
              onPressed:loading||printing||batch.students.isEmpty?
                null:()=>print(share:true),
              icon:const Icon(Icons.picture_as_pdf_outlined),
              label:const Text('Share Combined PDF')),
            OutlinedButton.icon(
              key:const Key('bulk-demand-print-student'),
              onPressed:loading||printing||batch.students.isEmpty?
                null:()=>print(copy:'student'),
              icon:const Icon(Icons.school_outlined),
              label:const Text('Student Copies Only')),
            OutlinedButton.icon(
              key:const Key('bulk-demand-print-office'),
              onPressed:loading||printing||batch.students.isEmpty?
                null:()=>print(copy:'office'),
              icon:const Icon(Icons.business_outlined),
              label:const Text('Office Copies Only')),
          ]),
        ],
      ]),
    );
  }
}
