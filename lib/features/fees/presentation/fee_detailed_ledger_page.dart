import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import '../data/fee_detailed_statement.dart';
import '../data/fee_setup_repository.dart';
import '../data/fee_payment_repository.dart';
import 'fee_statement_pdf.dart';
import 'fee_receipt_slip_page.dart';

class FeeDetailedLedgerPage extends StatefulWidget {
  const FeeDetailedLedgerPage({super.key,required this.repository,
    required this.workspace,required this.student});
  final FeePaymentRepository repository;
  final FeePaymentWorkspace workspace;
  final FeePaymentStudent student;
  @override State<FeeDetailedLedgerPage> createState()=>_FeeDetailedLedgerPageState();
}

class _FeeDetailedLedgerPageState extends State<FeeDetailedLedgerPage> {
  FeeDetailedStudentLedger? ledger;
  String? error,month,category;
  bool loading=false,printing=false;
  int serial=0;

  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)load();});
  }

  Future<void> load()async {
    final request=++serial;
    setState((){loading=true;error=null;});
    try {
      final r=await widget.repository.detailedLedger(
        schoolId:widget.workspace.schoolId,
        campusId:widget.workspace.campusId,
        yearId:widget.workspace.yearId,
        studentId:widget.student.id);
      if(!mounted||request!=serial)return;
      setState((){ledger=r;loading=false;});
    }catch(e) {
      if(!mounted||request!=serial)return;
      setState((){error='Unable to load detailed fee statement: '+e.toString();
        loading=false;ledger=null;});
    }
  }

  Future<void> openPostedReceipt(String receiptId)async{
    final data=ledger;
    if(data==null)return;
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>FeeReceiptSlipPage(
        repository:widget.repository,
        schoolId:widget.workspace.schoolId,
        campusId:widget.workspace.campusId,
        yearId:widget.workspace.yearId,
        studentId:widget.student.id,
        receiptId:receiptId,preloadedLedger:data)));
  }

  Future<void> printStatement({bool share=false})async{
    final r=ledger;
    if(r==null||printing)return;
    setState(()=>printing=true);
    try {
      if(share){
        final bytes=await FeeStatementPdf.build(r,PdfPageFormat.a4);
        await Printing.sharePdf(bytes:bytes,
          filename:'fee_statement_'+
            r.registration.replaceAll(RegExp(r'[^A-Za-z0-9_-]'),'_')+'.pdf');
      }else{
        await Printing.layoutPdf(
          name:'Fee statement - '+r.registration,
          onLayout:(format)=>FeeStatementPdf.build(r,format));
      }
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text('Unable to create/print PDF: '+e.toString())));
    }finally{
      if(mounted)setState(()=>printing=false);
    }
  }

  String money(int minor,String currency)=>currency+' '+FeeMoney.showMinor(minor);
  Widget stat(String title,int minor,String currency)=>Card.outlined(
    child:Padding(padding:const EdgeInsets.all(12),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:Theme.of(context).textTheme.bodySmall),
        Text(money(minor,currency),
          style:Theme.of(context).textTheme.titleMedium),
      ])));

  @override Widget build(BuildContext context){
    final r=ledger;
    final filtered=(r?.charges??const <FeeLedgerChargeDetail>[]).where((c)=>
      (month==null||c.month.substring(0,7)==month)&&
      (category==null||c.categoryId==category)).toList();
    return Scaffold(
      appBar:AppBar(title:const Text('Student Fee Statement'),actions:[
        IconButton(key:const Key('student-ledger-refresh'),
          tooltip:'Refresh statement',onPressed:loading?null:load,
          icon:const Icon(Icons.refresh)),
      ]),
      body:RefreshIndicator(onRefresh:load,
        child:ListView(key:const Key('detailed-fee-ledger-page'),
          padding:const EdgeInsets.all(16),children:[
          if(loading)const LinearProgressIndicator(),
          if(error!=null)ListTile(
            title:Text(error!,style:TextStyle(
              color:Theme.of(context).colorScheme.error)),
            trailing:TextButton(onPressed:load,child:const Text('Retry'))),
          if(r!=null)...[
            Text(r.schoolName,
              style:Theme.of(context).textTheme.titleLarge),
            Text(r.studentName+' · '+r.registration,
              style:Theme.of(context).textTheme.titleMedium),
            Text(r.className+(r.sectionName==null?'':' · '+r.sectionName!)
              +' · '+r.yearLabel),
            const SizedBox(height:10),
            const Text('Posted bills and receipt allocations are read-only. '
              'Monthly "Paid" means payments allocated to charges billed '
              'in that month, not necessarily cash collected that month.'),
            const SizedBox(height:12),
            Wrap(spacing:7,runSpacing:7,children:[
              FilledButton.icon(
                key:const Key('student-ledger-print'),onPressed:printing?null:
                  ()=>printStatement(),
                icon:const Icon(Icons.print_outlined),
                label:const Text('Print Statement')),
              OutlinedButton.icon(
                key:const Key('student-ledger-share'),onPressed:printing?null:
                  ()=>printStatement(share:true),
                icon:const Icon(Icons.picture_as_pdf_outlined),
                label:const Text('Share PDF')),
              OutlinedButton.icon(
                key:const Key('student-ledger-copy-csv'),
                onPressed:()=>Clipboard.setData(
                  ClipboardData(text:r.chargesCsv())),
                icon:const Icon(Icons.file_download_outlined),
                label:const Text('Copy CSV')),
            ]),
            const SizedBox(height:12),
            Wrap(spacing:8,runSpacing:4,children:[
              stat('Gross billed',r.totals.gross,r.currency),
              stat('Discounts',r.totals.discount,r.currency),
              stat('Net billed',r.totals.net,r.currency),
              stat('Paid',r.totals.paid,r.currency),
              stat('Outstanding',r.totals.outstanding,r.currency),
            ]),
            const SizedBox(height:12),
            Text('Monthly Fee Totals',style:Theme.of(context).textTheme.titleLarge),
            if(r.months.isEmpty)const Text('No bills in this academic year.'),
            for(final x in r.months)
              Card.outlined(child:ListTile(
                key:Key('student-ledger-month-'+x.label),
                title:Text(x.label.substring(0,7)+' · '+
                  x.totals.count.toString()+' charges'),
                subtitle:Text('Billed '+money(x.totals.net,r.currency)+
                  ' · Paid '+money(x.totals.paid,r.currency)),
                trailing:Text('Due '+money(x.totals.outstanding,r.currency)),
                onTap:()=>setState(()=>
                  month=month==x.label.substring(0,7)?
                    null:x.label.substring(0,7)),
              )),
            const SizedBox(height:12),
            Text('Category-wise Fee Totals',
              style:Theme.of(context).textTheme.titleLarge),
            for(final x in r.categories)
              Card.outlined(child:ListTile(
                key:Key('student-ledger-category-'+x.id!),
                title:Text(x.label+' · '+x.frequency!),
                subtitle:Text('Billed '+money(x.totals.net,r.currency)+
                  ' · Paid '+money(x.totals.paid,r.currency)+
                  ' · '+x.totals.count.toString()+' charges'),
                trailing:Text('Due '+money(x.totals.outstanding,r.currency)),
                onTap:()=>setState(()=>category=category==x.id?null:x.id),
              )),
            const SizedBox(height:12),
            Text('Individual Fee Charge History',
              style:Theme.of(context).textTheme.titleLarge),
            Wrap(spacing:8,runSpacing:8,children:[
              SizedBox(width:195,child:DropdownButtonFormField<String>(
                key:const Key('student-ledger-month-filter'),
                value:month??'all',isExpanded:true,
                decoration:const InputDecoration(border:OutlineInputBorder(),
                  labelText:'Billing month',isDense:true),
                items:[
                  const DropdownMenuItem(value:'all',child:Text('All months')),
                  for(final x in r.months)
                    DropdownMenuItem(value:x.label.substring(0,7),
                      child:Text(x.label.substring(0,7))),
                ],
                onChanged:(v)=>setState(()=>month=v=='all'?null:v),
              )),
              SizedBox(width:235,child:DropdownButtonFormField<String>(
                key:const Key('student-ledger-category-filter'),
                value:category??'all',isExpanded:true,
                decoration:const InputDecoration(border:OutlineInputBorder(),
                  labelText:'Category',isDense:true),
                items:[
                  const DropdownMenuItem(value:'all',child:Text('All categories')),
                  for(final x in r.categories)
                    DropdownMenuItem(value:x.id!,child:Text(x.label,
                      overflow:TextOverflow.ellipsis)),
                ],
                onChanged:(v)=>setState(()=>category=v=='all'?null:v),
              )),
            ]),
            if(filtered.isEmpty)
              const Padding(padding:EdgeInsets.all(16),
                child:Text('No posted charges match these filters.')),
            for(final c in filtered)
              Card.outlined(child:ExpansionTile(
                key:Key('student-ledger-charge-'+c.id),
                title:Text(c.category+' · '+c.month.substring(0,7)),
                subtitle:Text(c.source+' · '+c.description+
                  '\nGross '+money(c.totals.gross,r.currency)+
                  ' · Discount '+money(c.totals.discount,r.currency)+
                  ' · Billed '+money(c.totals.net,r.currency)+
                  ' · Paid '+money(c.totals.paid,r.currency)+
                  '\nDue date: '+c.dueOn),
                trailing:Text(money(c.totals.outstanding,r.currency)),
                children:[
                  const ListTile(title:Text('Receipt allocations'),
                    dense:true),
                  for(final a in r.allocations.where((a)=>a.chargeId==c.id))
                    ListTile(dense:true,
                      title:Text('Receipt '+a.receiptNo),
                      subtitle:Text(a.issuedAt.substring(0,10)+
                        ' · '+a.method),
                      trailing:Text(money(a.amount,r.currency))),
                  if(!r.allocations.any((a)=>a.chargeId==c.id))
                    const ListTile(
                      title:Text('No payment allocated to this charge'),
                      dense:true),
                ],
              )),
            const SizedBox(height:12),
            Text('Payment Receipt History',
              style:Theme.of(context).textTheme.titleLarge),
            if(r.receipts.isEmpty)
              const Text('No receipts allocated to this academic year.'),
            for(final p in r.receipts)
              ListTile(
                key:Key('student-ledger-receipt-'+p.number),
                title:Text('Receipt '+p.number+' · '+p.method),
                subtitle:Text(p.issuedAt.substring(0,10)+
                  (p.bankReference==null?'':' · Ref: '+p.bankReference!)+
                  '\nReceipt total: '+money(p.total,r.currency)),
                trailing:IconButton(
                  key:Key('student-ledger-print-receipt-'+p.number),
                  tooltip:'View / print receipt',
                  onPressed:()=>openPostedReceipt(p.id),
                  icon:const Icon(Icons.print_outlined)),
                onTap:()=>openPostedReceipt(p.id),
              ),
          ],
        ]),
      ),
    );
  }
}
