import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../data/fee_detailed_statement.dart';
import '../data/fee_payment_repository.dart';
import '../data/fee_receipt_slip.dart';
import '../data/fee_setup_repository.dart';
import 'fee_receipt_slip_pdf.dart';

/// Preview and print one already-posted receipt only. No payment writes.
class FeeReceiptSlipPage extends StatefulWidget {
  const FeeReceiptSlipPage({
    super.key,required this.repository,required this.schoolId,
    required this.campusId,required this.yearId,required this.studentId,
    required this.receiptId,this.preloadedLedger});
  final FeePaymentRepository repository;
  final String schoolId,campusId,yearId,studentId,receiptId;
  final FeeDetailedStudentLedger? preloadedLedger;

  @override State<FeeReceiptSlipPage> createState()=>_FeeReceiptSlipPageState();
}

class _FeeReceiptSlipPageState extends State<FeeReceiptSlipPage> {
  FeeReceiptSlip? slip;
  String? error;
  bool loading=false,printing=false;

  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)load();
    });
  }

  Future<void> load()async{
    setState((){loading=true;error=null;});
    try{
      final data=widget.preloadedLedger??await widget.repository.detailedLedger(
        schoolId:widget.schoolId,campusId:widget.campusId,
        yearId:widget.yearId,studentId:widget.studentId);
      if(data.schoolId!=widget.schoolId||data.campusId!=widget.campusId||
        data.yearId!=widget.yearId||data.studentId!=widget.studentId) {
        throw StateError('Receipt data outside the selected school scope');
      }
      final result=FeeReceiptSlip.fromLedger(data,widget.receiptId);
      if(!mounted)return;
      setState((){loading=false;slip=result;});
    }catch(e){
      if(!mounted)return;
      setState((){
        loading=false;error='Cannot load confirmed receipt: '+e.toString();
        slip=null;
      });
    }
  }

  Future<void> print({String copy='both',bool share=false})async{
    final r=slip;
    if(r==null||printing)return;
    setState(()=>printing=true);
    try{
      if(share){
        final bytes=await FeeReceiptSlipPdf.build(r,PdfPageFormat.a4,copy:copy);
        await Printing.sharePdf(bytes:bytes,
          filename:'fee_receipt_'+r.receiptNo.replaceAll(
             RegExp(r'[^A-Za-z0-9_-]'),'_')+'_'+copy+'.pdf');
      }else{
        await Printing.layoutPdf(
          name:'Fee receipt '+r.receiptNo+' ('+copy+')',
          onLayout:(format)=>FeeReceiptSlipPdf.build(r,format,copy:copy));
      }
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text('Receipt printing unavailable: '+e.toString())));
    }finally{
      if(mounted)setState(()=>printing=false);
    }
  }

  @override Widget build(BuildContext context){
    final r=slip;
    String money(int v)=>r==null?'':r.currency+' '+FeeMoney.showMinor(v);
    return Scaffold(
      appBar:AppBar(title:const Text('Fee Collection Receipt'),
        actions:[
          IconButton(key:const Key('fee-receipt-reload'),
            tooltip:'Reload verified receipt',
            onPressed:loading?null:load,icon:const Icon(Icons.refresh)),
        ]),
      body:ListView(key:const Key('fee-receipt-slip-page'),
        padding:const EdgeInsets.all(16),children:[
        if(loading)const LinearProgressIndicator(),
        if(error!=null)ListTile(title:Text(error!,
          style:TextStyle(color:Theme.of(context).colorScheme.error)),
          trailing:TextButton(onPressed:load,child:const Text('Retry'))),
        if(r!=null)...[
          Text(r.schoolName,
            style:Theme.of(context).textTheme.titleLarge),
          Text('Receipt '+r.receiptNo,
            style:Theme.of(context).textTheme.titleMedium),
          Text('Student: '+r.studentName+' · '+r.registration),
          Text(r.className+(r.sectionName==null?'':' · '+r.sectionName!)+
            ' · '+r.yearLabel),
          Text('Issued: '+FeeReceiptSlipPdf.issued(r.issuedAt)),
          Text('Method: '+r.method.toUpperCase()),
          if(r.bankReference!=null)Text('Bank Ref: '+r.bankReference!),
          const SizedBox(height:10),
          Text('Total received: '+money(r.amountMinor),
            style:Theme.of(context).textTheme.titleLarge),
          const Text('This is a posted payment receipt, not a new fee '
            'transaction. Student and Office copies contain identical '
            'receipt details.'),
          const SizedBox(height:12),
          Wrap(spacing:8,runSpacing:8,children:[
            FilledButton.icon(
              key:const Key('fee-receipt-print-both'),
              onPressed:printing?null:()=>print(),
              icon:const Icon(Icons.print_outlined),
              label:const Text('Print Both Copies')),
            OutlinedButton.icon(
              key:const Key('fee-receipt-share-both'),
              onPressed:printing?null:()=>print(share:true),
              icon:const Icon(Icons.picture_as_pdf_outlined),
              label:const Text('Share 2-Copy PDF')),
            OutlinedButton.icon(
              key:const Key('fee-receipt-print-student'),
              onPressed:printing?null:()=>print(copy:'student'),
              icon:const Icon(Icons.school_outlined),
              label:const Text('Student Copy')),
            OutlinedButton.icon(
              key:const Key('fee-receipt-print-office'),
              onPressed:printing?null:()=>print(copy:'office'),
              icon:const Icon(Icons.business_outlined),
              label:const Text('Office Copy')),
          ]),
          const SizedBox(height:18),
          Text('Collected by Fee Category',
            style:Theme.of(context).textTheme.titleMedium),
          for(final group in r.categoryTotals.entries)
            ListTile(title:Text(group.key),
              trailing:Text(money(group.value))),
          const SizedBox(height:12),
          Text('Individual Charge Allocations',
            style:Theme.of(context).textTheme.titleMedium),
          for(final line in r.lines)
            ListTile(
              title:Text(line.category+' · '+line.month.substring(0,7)),
              subtitle:Text('Charge ID: '+line.chargeId),
              trailing:Text(money(line.amountMinor))),
          const SizedBox(height:12),
          Text('Previous Payment History',
            style:Theme.of(context).textTheme.titleMedium),
          if(r.priorReceipts.isEmpty)
            const Text('No earlier posted receipts in this academic year.'),
          for(final prior in r.priorReceipts)
            ListTile(
              title:Text('Receipt '+prior.number),
              subtitle:Text(FeeReceiptSlipPdf.issued(prior.issuedAt)),
              trailing:Text(money(prior.yearAllocated))),
        ],
      ]),
    );
  }
}
