import 'package:flutter/material.dart';

import '../data/expense_repository.dart';
import '../data/fee_monthly_repository.dart';
import '../data/fee_setup_repository.dart';

class ExpensePayPage extends StatefulWidget {
  const ExpensePayPage({super.key,required this.repository,
    required this.workspace,required this.request});
  final ExpenseRepository repository;
  final ExpenseWorkspace workspace;
  final ExpenseRequest request;
  @override State<ExpensePayPage> createState()=>_ExpensePayPageState();
}
class _ExpensePayPageState extends State<ExpensePayPage>{
  final amount=TextEditingController(),paidOn=TextEditingController(),
    vendor=TextEditingController(),reference=TextEditingController();
  String? accountId,operationId,error,done;
  bool busy=false;
  @override void initState(){
    super.initState();
    amount.text=FeeMoney.showMinor(widget.request.remainingMinor);
    paidOn.text=DateTime.now().toIso8601String().substring(0,10);
    final active=widget.workspace.accounts.where((a)=>a.status=='active').toList();
    if(active.isNotEmpty)accountId=active.first.id;
  }
  @override void dispose(){
    amount.dispose();paidOn.dispose();vendor.dispose();reference.dispose();
    super.dispose();
  }
  Future<void> post()async{
    if(busy||done!=null)return;
    final minor=FeeMoney.parseMinor(amount.text);
    final parsed=DateTime.tryParse(paidOn.text.trim());
    if(minor==null||minor<=0||minor>widget.request.remainingMinor||
       accountId==null||parsed==null||paidOn.text.trim().length!=10){
      setState(()=>error='Choose an account, date and amount within the approved balance.');
      return;
    }
    final account=widget.workspace.accounts.firstWhere((a)=>a.id==accountId);
    if(account.method=='bank'&&reference.text.trim().length<3){
      setState(()=>error='Bank payment reference is required.');return;
    }
    if(operationId==null){
      final confirmed=await showDialog<bool>(context:context,builder:(d)=>
        AlertDialog(title:const Text('Confirm Expense Payment'),
          content:Text('Pay '+widget.workspace.currency+' '+
            FeeMoney.showMinor(minor)+' from '+account.name+
            ' for '+widget.request.category+'?\n'
            'This posts an immutable payment and balanced journal entry.'),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(d,false),
              child:const Text('Edit')),
            FilledButton(key:const Key('expense-payment-confirm'),
              onPressed:()=>Navigator.pop(d,true),
              child:const Text('Confirm Payment')),
          ]));
      if(confirmed!=true||!mounted)return;
      operationId=FeeOperationId.create();
    }
    setState((){busy=true;error=null;});
    try{
      final result=await widget.repository.pay(
        schoolId:widget.workspace.schoolId,campusId:widget.workspace.campusId,
        requestId:widget.request.id,accountId:accountId!,amountMinor:minor,
        paidOn:paidOn.text.trim(),vendor:vendor.text.trim().isEmpty?null:vendor.text.trim(),
        reference:reference.text.trim().isEmpty?null:reference.text.trim(),
        operationId:operationId!);
      if(!mounted)return;
      setState((){
        busy=false;
        done='Payment posted: '+widget.workspace.currency+' '+
          FeeMoney.showMinor(result.amountMinor)+'. Remaining '+
          FeeMoney.showMinor(result.remainingMinor)+'. Journal '+result.journalId+'.';
      });
    }catch(e){
      if(!mounted)return;
      setState((){
        busy=false;
        error='Payment not confirmed: '+e.toString()+
          '. Retry unchanged details with the same operation.';
      });
    }
  }
  @override Widget build(BuildContext context){
    final w=widget.workspace;
    final locked=operationId!=null;
    final active=w.accounts.where((a)=>a.status=='active').toList();
    return Scaffold(
      key:const Key('expense-payment-page'),
      appBar:AppBar(title:const Text('Pay Approved Expense')),
      body:ListView(padding:const EdgeInsets.all(14),children:[
        Text(widget.request.category,style:Theme.of(context).textTheme.headlineSmall),
        Text(widget.request.purpose),
        const SizedBox(height:6),
        Text('Approved '+w.currency+' '+FeeMoney.showMinor(widget.request.amountMinor)+
          ' • Paid '+w.currency+' '+FeeMoney.showMinor(widget.request.paidMinor)),
        Text('Remaining '+w.currency+' '+FeeMoney.showMinor(widget.request.remainingMinor)),
        const SizedBox(height:12),
        if(busy)const LinearProgressIndicator(),
        if(error!=null)Text(error!,style:TextStyle(
          color:Theme.of(context).colorScheme.error)),
        if(done!=null)...[
          SelectableText(done!),
          FilledButton(key:const Key('expense-payment-done'),
            onPressed:()=>Navigator.pop(context,true),
            child:const Text('Return to Expenses')),
        ]else...[
          if(active.isEmpty)
            const Text('No active payment account. Ask Owner to configure '
              'a cashbox or bank account before posting.'),
          if(active.isNotEmpty)
            DropdownButtonFormField<String>(
              key:const Key('expense-payment-account'),value:accountId,
              isExpanded:true,decoration:const InputDecoration(
                labelText:'Pay From',border:OutlineInputBorder()),
              items:[for(final a in active)DropdownMenuItem(value:a.id,
                child:Text(a.name+' • '+a.method.toUpperCase(),
                  overflow:TextOverflow.ellipsis))],
              onChanged:locked?null:(v)=>setState(()=>accountId=v)),
          const SizedBox(height:10),
          TextField(key:const Key('expense-payment-amount'),controller:amount,
            enabled:!locked,keyboardType:const TextInputType.numberWithOptions(decimal:true),
            decoration:InputDecoration(border:const OutlineInputBorder(),
              labelText:'Amount ('+w.currency+')')),
          const SizedBox(height:10),
          TextField(key:const Key('expense-payment-date'),controller:paidOn,
            enabled:!locked,decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Paid On (YYYY-MM-DD)')),
          const SizedBox(height:10),
          TextField(key:const Key('expense-payment-vendor'),controller:vendor,
            enabled:!locked,maxLength:160,
            decoration:const InputDecoration(border:OutlineInputBorder(),
              labelText:'Vendor / Recipient (optional)')),
          const SizedBox(height:10),
          TextField(key:const Key('expense-payment-reference'),controller:reference,
            enabled:!locked,maxLength:160,
            decoration:const InputDecoration(border:OutlineInputBorder(),
              labelText:'Reference (required for bank)')),
          const SizedBox(height:10),
          FilledButton.icon(key:const Key('expense-payment-process'),
            onPressed:busy||active.isEmpty?null:post,
            icon:const Icon(Icons.payments_outlined),
            label:Text(operationId==null?'Review & Post Payment':'Retry Same Payment')),
        ],
      ]),
    );
  }
}
