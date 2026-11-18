import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fee_billing_repository.dart';
import '../data/fee_monthly_repository.dart';
import '../data/fee_payment_repository.dart';
import '../data/fee_setup_repository.dart';

String _money(int minor,String currency)=>currency+' '+FeeMoney.showMinor(minor);

class FeeOtherPeoplePage extends StatefulWidget{
  const FeeOtherPeoplePage({super.key,required this.repository,
    required this.schoolId,required this.campusId,required this.yearId});
  final FeeBillingRepository repository;
  final String schoolId,campusId,yearId;
  @override State<FeeOtherPeoplePage> createState()=>_FeeOtherPeoplePageState();
}
class _FeeOtherPeoplePageState extends State<FeeOtherPeoplePage>{
  OtherPeopleLedger? data;
  bool loading=false;
  String? error,notice;
  int request=0;
  String filter='';
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)load();});
  }
  @override void didUpdateWidget(covariant FeeOtherPeoplePage old){
    super.didUpdateWidget(old);
    if(old.schoolId!=widget.schoolId||old.campusId!=widget.campusId||
      old.yearId!=widget.yearId){
      data=null;
      WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)load();});
    }
  }
  Future<void> load()async{
    final seq=++request;
    setState((){loading=true;error=null;});
    try{
      final row=await widget.repository.otherPeople(
        schoolId:widget.schoolId,campusId:widget.campusId,yearId:widget.yearId);
      if(!mounted||seq!=request)return;
      setState((){data=row;loading=false;});
    }catch(e){
      if(!mounted||seq!=request)return;
      setState((){loading=false;error='Other payer ledger unavailable: '+e.toString();});
    }
  }

  Future<void> createPerson() async{
    final name=TextEditingController(),contact=TextEditingController();
    final op=FeeOperationId.create();
    bool busy=false,locked=false;
    String? issue;
    await showDialog<void>(context:context,builder:(dialog)=>
      StatefulBuilder(builder:(dialog,change)=>AlertDialog(
        title:const Text('Add Non-Student Payer'),
        content:SizedBox(width:470,child:SingleChildScrollView(
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Text('For a visitor or other person who pays an '
              'individual school fee. Do not create a fake student.'),
            const SizedBox(height:10),
            TextField(key:const Key('fee-other-person-name'),
              controller:name,enabled:!locked,
              decoration:const InputDecoration(labelText:'Full Name',
                border:OutlineInputBorder())),
            const SizedBox(height:10),
            TextField(key:const Key('fee-other-person-contact'),
              controller:contact,enabled:!locked,
              decoration:const InputDecoration(labelText:'Contact (optional)',
                border:OutlineInputBorder())),
            if(issue!=null)Text(issue!,style:TextStyle(
              color:Theme.of(dialog).colorScheme.error)),
          ]))),
        actions:[
          TextButton(onPressed:busy?null:()=>Navigator.pop(dialog),
            child:const Text('Cancel')),
          FilledButton(key:const Key('fee-other-save-person'),
            onPressed:busy?null:() async{
              if(name.text.trim().length<2){
                change(()=>issue='Enter payer name.');return;
              }
              change((){busy=true;locked=true;issue=null;});
              try{
                await widget.repository.createPerson(
                  schoolId:widget.schoolId,campusId:widget.campusId,
                  name:name.text.trim(),
                  contact:contact.text.trim().isEmpty?null:contact.text.trim(),
                  operationId:op);
                if(!dialog.mounted)return;
                Navigator.pop(dialog);
                if(mounted){notice='Other payer created.';await load();}
              }catch(e){
                if(dialog.mounted)change((){
                  busy=false;issue='Not confirmed: '+e.toString()+
                    '. Retry same details.';});
              }
            },child:Text(locked?'Retry Save':'Save Payer')),
        ])));
    // Dialog exit animates after the route result completes. Dispose only
    // once its TextFields are fully removed from the widget tree.
    await Future<void>.delayed(const Duration(milliseconds:400));
    name.dispose();contact.dispose();
  }

  Future<void> charge(OtherPeopleLedger w,OtherPersonAccount person) async{
    if(w.categories.isEmpty)return;
    final amount=TextEditingController();
    final due=TextEditingController(text:DateTime.now().toIso8601String().substring(0,10));
    final note=TextEditingController(text:'Individual school fee');
    String categoryId=w.categories.first.id;
    final op=FeeOperationId.create();
    bool busy=false,locked=false;
    String? issue;
    await showDialog<void>(context:context,builder:(dialog)=>
      StatefulBuilder(builder:(dialog,change)=>AlertDialog(
        title:Text('Generate Fee • '+person.name),
        content:SizedBox(width:510,child:SingleChildScrollView(child:
          Column(mainAxisSize:MainAxisSize.min,children:[
            DropdownButtonFormField<String>(
              key:const Key('fee-other-charge-category'),value:categoryId,
              decoration:const InputDecoration(labelText:'Fee Category',
                border:OutlineInputBorder()),
              items:[
                for(final c in w.categories)
                  DropdownMenuItem(value:c.id,child:Text(c.name,
                    overflow:TextOverflow.ellipsis)),
              ],onChanged:locked?null:(v)=>change((){
                if(v!=null)categoryId=v;
              })),
            const SizedBox(height:9),
            TextField(key:const Key('fee-other-charge-amount'),
              controller:amount,enabled:!locked,
              keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:InputDecoration(labelText:'Amount ('+w.currency+')',
                border:const OutlineInputBorder())),
            const SizedBox(height:9),
            TextField(key:const Key('fee-other-charge-date'),
              controller:due,enabled:!locked,
              decoration:const InputDecoration(labelText:'Due Date (YYYY-MM-DD)',
                border:OutlineInputBorder())),
            const SizedBox(height:9),
            TextField(key:const Key('fee-other-charge-note'),
              controller:note,enabled:!locked,maxLength:500,
              decoration:const InputDecoration(labelText:'Reason / Description',
                border:OutlineInputBorder())),
            if(issue!=null)Text(issue!,style:TextStyle(
              color:Theme.of(dialog).colorScheme.error)),
          ]))),
        actions:[
          TextButton(onPressed:busy?null:()=>Navigator.pop(dialog),
            child:const Text('Cancel')),
          FilledButton(key:const Key('fee-other-post-charge'),
            onPressed:busy?null:()async{
              final minor=FeeMoney.parseMinor(amount.text);
              final date=DateTime.tryParse(due.text.trim());
              if(minor==null||minor<=0||date==null||
                due.text.trim().length!=10||note.text.trim().length<3){
                change(()=>issue='Enter a valid amount, due date and reason.');return;
              }
              change((){busy=true;locked=true;issue=null;});
              try{
                await widget.repository.chargePerson(
                  schoolId:w.schoolId,campusId:w.campusId,yearId:w.yearId,
                  personId:person.id,categoryId:categoryId,
                  amountMinor:minor,dueOn:due.text.trim(),
                  memo:note.text.trim(),operationId:op);
                if(!dialog.mounted)return;
                Navigator.pop(dialog);
                if(mounted){notice='Individual charge generated.';await load();}
              }catch(e){
                if(dialog.mounted)change((){
                  busy=false;issue='Not confirmed: '+e.toString()+
                    '. Retry the same charge details.';});
              }
            },child:Text(locked?'Retry Posting':'Post Fee Charge')),
        ])));
    await Future<void>.delayed(const Duration(milliseconds:400));
    amount.dispose();due.dispose();note.dispose();
  }

  Future<void> collect(OtherPeopleLedger w,OtherPersonAccount person) async{
    final result=await Navigator.push<bool>(context,MaterialPageRoute(
      builder:(_)=>OtherPersonQuickPayPage(
        repository:widget.repository,ledger:w,person:person)));
    if(result==true&&mounted)await load();
  }

  @override Widget build(BuildContext context){
    final w=data;
    final people=(w?.people??const <OtherPersonAccount>[]).where(
      (p)=>p.name.toLowerCase().contains(filter.toLowerCase())||
        (p.contact??'').toLowerCase().contains(filter.toLowerCase())).toList();
    return Scaffold(key:const Key('fee-other-payers-page'),
      appBar:AppBar(title:const Text('Non-Student Fees'),
        actions:[IconButton(onPressed:loading?null:load,
          icon:const Icon(Icons.refresh))]),
      body:RefreshIndicator(onRefresh:load,child:ListView(
        padding:const EdgeInsets.all(14),children:[
          const Text('Charge and collect individual fees from visitors '
            'or other people, separately from student accounts.'),
          if(loading)const LinearProgressIndicator(),
          if(error!=null)Text(error!,style:TextStyle(
            color:Theme.of(context).colorScheme.error)),
          if(notice!=null)Text(notice!),
          if(w!=null)...[
            const SizedBox(height:12),
            if(w.canCollect)FilledButton.icon(
              key:const Key('fee-other-add-person'),
              onPressed:createPerson,icon:const Icon(Icons.person_add_alt_1),
              label:const Text('Add Non-Student Payer')),
            const SizedBox(height:12),
            TextField(key:const Key('fee-other-filter'),
              decoration:const InputDecoration(
                labelText:'Search payers',prefixIcon:Icon(Icons.search),
                border:OutlineInputBorder()),
              onChanged:(v)=>setState(()=>filter=v)),
            const SizedBox(height:10),
            Text('Payers: '+people.length.toString(),
              style:Theme.of(context).textTheme.titleLarge),
            if(people.isEmpty)
              const Text('No registered non-student payers for this campus.'),
            for(final p in people)Card.outlined(
              key:Key('fee-other-person-'+p.id),
              child:Padding(padding:const EdgeInsets.all(12),child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(p.name,style:Theme.of(context).textTheme.titleMedium),
                  if(p.contact!=null)Text(p.contact!),
                  Text('Outstanding '+_money(p.dueMinor,w.currency)),
                  for(final c in p.charges)
                    ListTile(dense:true,
                      title:Text(c.categoryName+' • '+c.memo),
                      subtitle:Text('Due '+c.dueOn),
                      trailing:Text(_money(c.outstandingMinor,w.currency))),
                  for(final r in p.receipts.take(3))
                    ListTile(dense:true,
                      title:Text('Receipt '+r.number),
                      subtitle:Text(r.method.toUpperCase()),
                      trailing:Text(_money(r.amountMinor,w.currency))),
                  if(w.canCollect)Wrap(spacing:8,children:[
                    OutlinedButton.icon(
                      key:Key('fee-other-add-charge-'+p.id),
                      onPressed:()=>charge(w,p),
                      icon:const Icon(Icons.add_circle_outline),
                      label:const Text('Generate Fee')),
                    FilledButton.icon(
                      key:Key('fee-other-collect-'+p.id),
                      onPressed:p.dueMinor>0?()=>collect(w,p):null,
                      icon:const Icon(Icons.payments_outlined),
                      label:const Text('Collect Payment')),
                  ]),
                ]))),
          ],
        ])),
    );
  }
}

class OtherPersonQuickPayPage extends StatefulWidget{
  const OtherPersonQuickPayPage({super.key,required this.repository,
    required this.ledger,required this.person});
  final FeeBillingRepository repository;
  final OtherPeopleLedger ledger;
  final OtherPersonAccount person;
  @override State<OtherPersonQuickPayPage> createState()=>
    _OtherPersonQuickPayPageState();
}
class _OtherPersonQuickPayPageState extends State<OtherPersonQuickPayPage>{
  final amount=TextEditingController(),bank=TextEditingController();
  final lineInputs=<String,TextEditingController>{};
  final op=FeeOperationId.create();
  String method='cash';
  String? error;
  bool review=false,busy=false,posted=false;
  List<QuickPayAllocation>? frozen;
  QuickPayReceipt? receipt;
  List<OtherPersonCharge> get charges=>
    widget.person.charges.where((c)=>c.outstandingMinor>0).toList()
      ..sort((a,b)=>a.dueOn.compareTo(b.dueOn));
  @override void initState(){
    super.initState();
    amount.text=FeeMoney.showMinor(widget.person.dueMinor);
  }
  @override void dispose(){
    amount.dispose();bank.dispose();
    for(final c in lineInputs.values)c.dispose();
    super.dispose();
  }
  void preview(){
    final amt=FeeMoney.parseMinor(amount.text);
    if(amt==null||amt<=0||amt>widget.person.dueMinor||
       (method=='bank'&&bank.text.trim().length<3)){
      setState(()=>error='Enter an amount within outstanding dues and '
        'a bank reference if applicable.');return;
    }
    var remaining=amt;
    for(final c in charges){
      final take=remaining<c.outstandingMinor?remaining:c.outstandingMinor;
      lineInputs[c.id]=TextEditingController(text:FeeMoney.showMinor(take));
      remaining-=take;
    }
    setState((){review=true;error=null;});
  }
  List<QuickPayAllocation> allocations(){
    final amt=FeeMoney.parseMinor(amount.text);
    var total=0;
    final result=<QuickPayAllocation>[];
    for(final c in charges){
      final sum=FeeMoney.parseMinor(lineInputs[c.id]?.text??'');
      if(sum==null||sum<0||sum>c.outstandingMinor){
        throw FormatException('Invalid amount for '+c.categoryName);
      }
      if(sum>0)result.add(QuickPayAllocation(chargeId:c.id,amountMinor:sum));
      total+=sum;
    }
    if(total!=amt||total<=0){
      throw const FormatException('Allocations must equal the amount received.');
    }
    return result;
  }
  Future<void> process()async{
    if(busy||posted)return;
    if(frozen==null){
      List<QuickPayAllocation> chosen;
      try{chosen=allocations();}
      on FormatException catch(e){setState(()=>error=e.message);return;}
      final yes=await showDialog<bool>(context:context,builder:(d)=>
        AlertDialog(title:const Text('Confirm Non-Student Fee Payment'),
          content:Text('Collect '+_money(FeeMoney.parseMinor(amount.text)!,
            widget.ledger.currency)+' from '+widget.person.name+
            '? This records an immutable receipt.'),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(d,false),
              child:const Text('Edit')),
            FilledButton(key:const Key('fee-other-confirm-collect'),
              onPressed:()=>Navigator.pop(d,true),
              child:const Text('Confirm Collection')),
          ]));
      if(yes!=true||!mounted)return;
      frozen=List.unmodifiable(chosen);
    }
    setState((){busy=true;error=null;});
    try{
      final r=await widget.repository.collectPerson(
        schoolId:widget.ledger.schoolId,
        campusId:widget.ledger.campusId,
        yearId:widget.ledger.yearId,
        personId:widget.person.id,
        amountMinor:FeeMoney.parseMinor(amount.text)!,
        method:method,
        bankRef:method=='bank'?bank.text.trim():null,
        allocations:frozen!,operationId:op);
      if(!mounted)return;
      setState((){receipt=r;posted=true;busy=false;});
    }catch(e){
      if(!mounted)return;
      setState((){busy=false;
        error='Receipt not confirmed: '+e.toString()+
          '. Retry unchanged details or close and refresh first.';});
    }
  }
  @override Widget build(BuildContext context){
    var allocated=0;bool valid=true;
    if(review)for(final c in charges){
      final n=FeeMoney.parseMinor(lineInputs[c.id]?.text??'');
      if(n==null||n<0||n>c.outstandingMinor)valid=false;
      else allocated+=n;
    }
    final amt=FeeMoney.parseMinor(amount.text)??0;
    return Scaffold(key:const Key('fee-other-quickpay-page'),
      appBar:AppBar(title:Text('Collect • '+widget.person.name)),
      body:ListView(padding:const EdgeInsets.all(14),children:[
        Text('Outstanding '+_money(widget.person.dueMinor,
          widget.ledger.currency),style:Theme.of(context).textTheme.titleLarge),
        if(error!=null)Text(error!,style:TextStyle(
          color:Theme.of(context).colorScheme.error)),
        if(busy)const LinearProgressIndicator(),
        if(receipt!=null)...[
          const Icon(Icons.check_circle_outline,size:46),
          SelectableText('Receipt '+receipt!.number),
          Text('Collected '+_money(receipt!.amountMinor,
            widget.ledger.currency)),
          TextButton.icon(onPressed:()=>Clipboard.setData(
            ClipboardData(text:receipt!.number)),
            icon:const Icon(Icons.copy),label:const Text('Copy Receipt Number')),
          FilledButton(key:const Key('fee-other-payment-done'),
            onPressed:()=>Navigator.pop(context,true),
            child:const Text('Return to Payer Ledger')),
        ]else if(!review)...[
          const SizedBox(height:10),
          TextField(key:const Key('fee-other-pay-amount'),
            controller:amount,keyboardType:const TextInputType.numberWithOptions(
              decimal:true),decoration:InputDecoration(
              labelText:'Amount ('+widget.ledger.currency+')',
              border:const OutlineInputBorder())),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(
            key:const Key('fee-other-pay-method'),value:method,
            decoration:const InputDecoration(labelText:'Payment Method',
              border:OutlineInputBorder()),
            items:const [
              DropdownMenuItem(value:'cash',child:Text('Cash')),
              DropdownMenuItem(value:'bank',child:Text('Bank Transfer')),
            ],onChanged:(v)=>setState((){if(v!=null)method=v;})),
          if(method=='bank')TextField(
            key:const Key('fee-other-pay-bank'),controller:bank,
            decoration:const InputDecoration(labelText:'Bank Reference',
              border:OutlineInputBorder())),
          const SizedBox(height:12),
          FilledButton(key:const Key('fee-other-pay-review'),
            onPressed:preview,child:const Text('Auto Allocate & Review')),
        ]else...[
          const Text('Edit allocation amounts across posted charges. '
            'The sum must equal the received amount.'),
          for(final c in charges)Card.outlined(child:Padding(
            padding:const EdgeInsets.all(12),child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(c.categoryName+' • '+c.memo),
                Text('Due '+_money(c.outstandingMinor,widget.ledger.currency)),
                TextField(key:Key('fee-other-alloc-'+c.id),
                  controller:lineInputs[c.id],enabled:frozen==null,
                  keyboardType:const TextInputType.numberWithOptions(decimal:true),
                  decoration:const InputDecoration(
                    border:OutlineInputBorder(),labelText:'Allocate'),
                  onChanged:(_)=>setState((){})),
              ]))),
          Text('Allocated '+_money(allocated,widget.ledger.currency)+
            ' / '+_money(amt,widget.ledger.currency)),
          const SizedBox(height:10),
          Wrap(spacing:8,children:[
            OutlinedButton(onPressed:frozen!=null?null:
              ()=>setState(()=>review=false),
              child:const Text('Edit Payment Details')),
            FilledButton(key:const Key('fee-other-pay-process'),
              onPressed:busy||(frozen==null&&(!valid||allocated!=amt))
                ?null:process,child:Text(frozen==null?
                  'Process Payment':'Retry Same Payment')),
          ]),
        ],
      ]));
  }
}
