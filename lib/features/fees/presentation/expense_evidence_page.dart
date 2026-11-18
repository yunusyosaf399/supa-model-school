import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/expense_evidence_repository.dart';
import '../data/expense_repository.dart';
import '../data/fee_setup_repository.dart';

/// Request-scoped evidence review. Payment receipts point to immutable DB29
/// posted payment IDs; document verification never changes the ledger.
class ExpenseEvidencePage extends StatefulWidget {
  const ExpenseEvidencePage({super.key,required this.repository,
    required this.workspace,required this.request});
  final ExpenseEvidenceRepository repository;
  final ExpenseWorkspace workspace;
  final ExpenseRequest request;
  @override
  State<ExpenseEvidencePage> createState()=>_ExpenseEvidencePageState();
}
class _ExpenseEvidencePageState extends State<ExpenseEvidencePage>{
  ExpenseEvidenceWorkspace? evidence;
  String? paymentId,error,notice;
  bool loading=false,busy=false;
  @override
  void initState(){
    super.initState();
    if(widget.request.payments.isNotEmpty)paymentId=widget.request.payments.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)load();});
  }
  Future<void> load()async{
    setState((){loading=true;error=null;});
    try{
      final data=await widget.repository.list(
        schoolId:widget.workspace.schoolId,campusId:widget.workspace.campusId,
        requestId:widget.request.id);
      if(!mounted)return;
      setState((){evidence=data;loading=false;});
    }catch(e){
      if(mounted)setState((){
        loading=false;error='Evidence unavailable: $e';
      });
    }
  }
  Future<void> upload(String kind)async{
    if(busy)return;
    final target=kind=='receipt'?paymentId:null;
    if(kind=='receipt'&&target==null){
      setState(()=>error='Select an actual posted payment for the receipt.');
      return;
    }
    setState((){busy=true;notice=null;error=null;});
    try{
      final saved=await widget.repository.pickAndUpload(
        schoolId:widget.workspace.schoolId,campusId:widget.workspace.campusId,
        requestId:widget.request.id,kind:kind,paymentId:target);
      if(!mounted)return;
      if(saved){
        notice='Evidence uploaded. Owner verification is pending.';
        await load();
      }else{setState(()=>notice='No file selected.');}
    }catch(e){
      if(mounted)setState(()=>error='Upload was not confirmed: $e. '
        'Retry the same document; duplicates are prevented.');
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }
  Future<void> preview(ExpenseEvidence attachment)async{
    if(busy)return;
    setState((){busy=true;error=null;});
    try{
      final signed=await widget.repository.signedPreview(attachment);
      final launched=await launchUrl(Uri.parse(signed),
        mode:LaunchMode.externalApplication);
      if(!launched)throw StateError('Could not open private preview.');
    }catch(e){
      if(mounted)setState(()=>error='Preview unavailable: $e');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> verify(ExpenseEvidence attachment,String decision)async{
    if(busy||evidence?.isOwner!=true||attachment.status!='pending')return;
    String reason='';
    final confirmed=await showDialog<bool>(context:context,builder:(d)=>
      AlertDialog(title:Text(decision=='verified'
        ?'Verify Receipt / Invoice':'Reject Receipt / Invoice'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          Text(attachment.fileName),
          const Text('Document verification does not create or amend payment.'),
          if(decision=='rejected')TextField(
            key:const Key('expense-evidence-reject-reason'),
            onChanged:(v)=>reason=v,maxLength:500,
            decoration:const InputDecoration(border:OutlineInputBorder(),
              labelText:'Rejection reason (required)')),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(d,false),
            child:const Text('Cancel')),
          FilledButton(key:const Key('expense-evidence-review-confirm'),
            onPressed:()=>Navigator.pop(d,true),
            child:Text(decision=='verified'?'Verify':'Reject')),
        ]));
    if(confirmed!=true||!mounted)return;
    if(decision=='rejected'&&reason.trim().length<4){
      setState(()=>error='Rejection requires at least 4 characters.');
      return;
    }
    setState((){busy=true;error=null;notice=null;});
    try{
      await widget.repository.review(
        schoolId:widget.workspace.schoolId,campusId:widget.workspace.campusId,
        attachmentId:attachment.id,decision:decision,
        reason:decision=='rejected'?reason.trim():null);
      if(!mounted)return;
      notice='Evidence $decision. The posted payment record is unchanged.';
      await load();
    }catch(e){
      if(mounted)setState(()=>error='Verification not confirmed: $e');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context){
    final items=evidence?.attachments??const <ExpenseEvidence>[];
    final canInvoice=evidence?.canUploadInvoice==true;
    final canReceipt=evidence?.canUploadReceipt==true&&
      widget.request.payments.isNotEmpty;
    return Scaffold(key:const Key('expense-evidence-page'),
      appBar:AppBar(title:const Text('Expense Receipts & Invoices')),
      body:RefreshIndicator(onRefresh:load,child:ListView(
        padding:const EdgeInsets.all(14),children:[
          Text(widget.request.category,
            style:Theme.of(context).textTheme.titleLarge),
          Text(widget.request.purpose),
          const SizedBox(height:6),
          Text('Request status: ${widget.request.status} • '
            'Invoices are linked to this request; receipts link to a posted payment.'),
          const SizedBox(height:8),
          if(loading||busy)const LinearProgressIndicator(),
          if(error!=null)Text(error!,style:TextStyle(
            color:Theme.of(context).colorScheme.error)),
          if(notice!=null)Text(notice!),
          const SizedBox(height:10),
          if(canInvoice)FilledButton.icon(
            key:const Key('expense-upload-invoice'),
            onPressed:busy?null:()=>upload('invoice'),
            icon:const Icon(Icons.upload_file),
            label:const Text('Upload Invoice (PDF / Image)')),
          if(evidence?.canUploadReceipt==true)...[
            const SizedBox(height:8),
            if(widget.request.payments.isNotEmpty)...[
              DropdownButtonFormField<String>(
                key:const Key('expense-receipt-payment'),
                value:paymentId,
                decoration:const InputDecoration(
                  border:OutlineInputBorder(),labelText:'Link Receipt to Payment'),
                isExpanded:true,
                items:[for(final p in widget.request.payments)
                  DropdownMenuItem(value:p.id,
                    child:Text('${p.paidOn} • ${widget.workspace.currency} '
                      '${FeeMoney.showMinor(p.amountMinor)} • ${p.id}',
                      overflow:TextOverflow.ellipsis))],
                onChanged:busy?null:(v)=>setState(()=>paymentId=v)),
              const SizedBox(height:8),
            ],
            FilledButton.icon(key:const Key('expense-upload-receipt'),
              onPressed:busy||!canReceipt?null:()=>upload('receipt'),
              icon:const Icon(Icons.receipt_long),
              label:const Text('Upload Payment Receipt')),
          ],
          const Divider(height:28),
          Text('Uploaded Evidence',style:Theme.of(context).textTheme.titleMedium),
          if(evidence!=null&&items.isEmpty)
            const Text('No invoices or receipts registered for this request.'),
          for(final entry in items)
            Card.outlined(key:Key('expense-evidence-row-${entry.id}'),
              child:Padding(padding:const EdgeInsets.all(10),child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('${entry.kind.toUpperCase()} • ${entry.status.toUpperCase()}',
                    style:Theme.of(context).textTheme.titleSmall),
                  Text(entry.fileName,overflow:TextOverflow.ellipsis),
                  Text('${(entry.bytes/1024).toStringAsFixed(1)} KiB • '
                    'Uploaded ${entry.uploadedAt}'),
                  if(entry.paymentId!=null)
                    SelectableText('Linked posted payment: ${entry.paymentId}',
                      key:Key('expense-evidence-payment-${entry.id}')),
                  if(entry.rejectionReason!=null)
                    Text('Rejected: ${entry.rejectionReason}'),
                  Wrap(spacing:8,runSpacing:8,children:[
                    OutlinedButton.icon(
                      key:Key('expense-evidence-preview-${entry.id}'),
                      onPressed:busy?null:()=>preview(entry),
                      icon:const Icon(Icons.open_in_new),
                      label:const Text('Private Preview (90 sec)')),
                    if(evidence?.isOwner==true&&entry.status=='pending')...[
                      FilledButton(key:Key('expense-evidence-verify-${entry.id}'),
                        onPressed:busy?null:()=>verify(entry,'verified'),
                        child:const Text('Verify')),
                      OutlinedButton(key:Key('expense-evidence-reject-${entry.id}'),
                        onPressed:busy?null:()=>verify(entry,'rejected'),
                        child:const Text('Reject')),
                    ],
                  ]),
                ]))),
          const SizedBox(height:8),
          const Text('Evidence stays private and cannot be overwritten or deleted '
            'from the app. Verified documents are audit evidence only. '
            'They do not create, reverse, or approve cash payments.'),
        ],
      )));
  }
}
