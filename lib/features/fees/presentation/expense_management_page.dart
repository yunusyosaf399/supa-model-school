import 'package:flutter/material.dart';

import '../data/expense_repository.dart';
import '../data/expense_evidence_repository.dart';
import '../data/fee_monthly_repository.dart';
import '../data/fee_setup_repository.dart';
import 'expense_pay_page.dart';
import 'expense_evidence_page.dart';

class ExpenseManagementPage extends StatefulWidget {
  const ExpenseManagementPage({super.key,required this.repository,
    required this.schoolId,required this.campusId,this.evidenceRepository});
  final ExpenseRepository repository;
  final ExpenseEvidenceRepository? evidenceRepository;
  final String schoolId,campusId;
  @override State<ExpenseManagementPage> createState()=>_ExpenseManagementPageState();
}

class _ExpenseManagementPageState extends State<ExpenseManagementPage>{
  ExpenseWorkspace? workspace;
  final catCode=TextEditingController(),catName=TextEditingController();
  final accName=TextEditingController(),accMask=TextEditingController();
  final reqAmount=TextEditingController(),reqPurpose=TextEditingController(),
    reqDate=TextEditingController();
  String catKind='operating',accKind='cash',status='all';
  String? catId,catOp,accOp,reqOp,error,notice;
  bool loading=false,writing=false;
  int version=0;

  @override void initState(){
    super.initState();
    reqDate.text=DateTime.now().toIso8601String().substring(0,10);
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)load();});
  }
  @override void didUpdateWidget(covariant ExpenseManagementPage old){
    super.didUpdateWidget(old);
    if(widget.schoolId!=old.schoolId||widget.campusId!=old.campusId){
      workspace=null;catId=null;status='all';
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)load();});
    }
  }
  @override void dispose(){
    catCode.dispose();catName.dispose();accName.dispose();accMask.dispose();
    reqAmount.dispose();reqPurpose.dispose();reqDate.dispose();
    super.dispose();
  }
  Future<void> load()async{
    final n=++version;
    setState((){loading=true;error=null;});
    try{
      final w=await widget.repository.workspace(
        schoolId:widget.schoolId,campusId:widget.campusId);
      if(!mounted||n!=version)return;
      setState((){
        workspace=w;loading=false;
        if(!w.categories.any((c)=>c.id==catId&&c.active)){
          final active=w.categories.where((c)=>c.active).toList();
          catId=active.isEmpty?null:active.first.id;
        }
      });
    }catch(e){
      if(!mounted||n!=version)return;
      setState((){
        loading=false;workspace=null;
        error='Expenses unavailable: '+e.toString();
      });
    }
  }
  Future<void> saveCategory()async{
    final w=workspace;
    if(w==null||writing||!w.isOwner)return;
    final code=catCode.text.trim().toUpperCase();
    if(!RegExp(r'^[A-Z][A-Z0-9_]{1,29}$').hasMatch(code)||
       catName.text.trim().length<2){
      setState(()=>error='Use an uppercase category code and a descriptive name.');
      return;
    }
    catOp??=FeeOperationId.create();
    setState((){writing=true;error=null;notice=null;});
    try{
      await widget.repository.createCategory(
        schoolId:w.schoolId,code:code,
        name:catName.text.trim(),kind:catKind,operationId:catOp!);
      if(!mounted)return;
      catOp=null;catCode.clear();catName.clear();
      notice='Expense category added with its matching ledger account.';
      await load();
    }catch(e){
      if(mounted)setState(()=>error='Category not confirmed: '+e.toString()+
        '. Retry exactly the same details.');
    }finally{
      if(mounted)setState(()=>writing=false);
    }
  }
  Future<void> saveAccount()async{
    final w=workspace;
    if(w==null||writing||!w.isOwner)return;
    if(accName.text.trim().length<2||
       (accMask.text.trim().isNotEmpty&&accMask.text.trim().length<4)){
      setState(()=>error='Provide an account name and optional masked reference of 4+ characters.');
      return;
    }
    accOp??=FeeOperationId.create();
    setState((){writing=true;error=null;notice=null;});
    try{
      await widget.repository.createAccount(
        schoolId:w.schoolId,campusId:w.campusId,
        name:accName.text.trim(),kind:accKind,
        maskedReference:accMask.text.trim().isEmpty?null:accMask.text.trim(),
        operationId:accOp!);
      if(!mounted)return;
      accOp=null;accName.clear();accMask.clear();
      notice='Campus '+accKind+' payment account configured.';
      await load();
    }catch(e){
      if(mounted)setState(()=>error='Account not confirmed: '+e.toString()+
        '. Retry with the same details.');
    }finally{if(mounted)setState(()=>writing=false);}
  }
  Future<void> sendRequest()async{
    final w=workspace;
    if(w==null||writing||!w.canCreate)return;
    final amount=FeeMoney.parseMinor(reqAmount.text);
    if(catId==null||amount==null||amount<=0||
      reqDate.text.trim().length!=10||
      DateTime.tryParse(reqDate.text.trim())==null||
      reqPurpose.text.trim().length<4){
      setState(()=>error='Select a category and enter amount, date, and purpose (at least 4 characters).');
      return;
    }
    reqOp ??= FeeOperationId.create();
    setState((){writing=true;error=null;notice=null;});
    try{
      await widget.repository.request(
        schoolId:w.schoolId,campusId:w.campusId,categoryId:catId!,
        amountMinor:amount,expenseDate:reqDate.text.trim(),
        purpose:reqPurpose.text.trim(),operationId:reqOp!);
      if(!mounted)return;
      reqOp=null;reqAmount.clear();reqPurpose.clear();
      notice='Expense recorded successfully. Payment and attachments are optional.';
      await load();
    }catch(e){
      if(mounted)setState(()=>error='Expense not confirmed: '+e.toString()+
        '. Retry unchanged details to avoid duplicates.');
    }finally{if(mounted)setState(()=>writing=false);}
  }

  Future<void> pay(ExpenseWorkspace w,ExpenseRequest request)async{
    final saved=await Navigator.push<bool>(context,MaterialPageRoute(
      builder:(_)=>ExpensePayPage(
        repository:widget.repository,workspace:w,request:request)));
    if(saved==true&&mounted){
      notice='Expense payment posted and ledger updated.';
      await load();
    }
  }
  Future<void> viewEvidence(ExpenseWorkspace w,ExpenseRequest r)async{
    final service=widget.evidenceRepository ??
      (widget.repository is SupabaseExpenseRepository
        ? SupabaseExpenseEvidenceRepository(
            (widget.repository as SupabaseExpenseRepository).client)
        : null);
    if(service==null)return;
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>ExpenseEvidencePage(
        repository:service,workspace:w,request:r)));
  }
  String money(int amount,String currency)=>currency+' '+FeeMoney.showMinor(amount);

  @override Widget build(BuildContext context){
    final w=workspace;
    final requests=(w?.requests??const <ExpenseRequest>[]).where((r)=>
      status=='all'||r.status==status||(status=='paid'&&
      (r.status=='approved'||r.status=='recorded')&&r.remainingMinor==0)).toList();
    return RefreshIndicator(onRefresh:load,child:ListView(
      key:const Key('expense-management-page'),
      padding:const EdgeInsets.all(14),children:[
        Text('Expense Management',style:Theme.of(context).textTheme.headlineSmall),
        const Text('Record expenses directly. Payments and attachments are optional.'),
        const SizedBox(height:8),
        if(loading||writing)const LinearProgressIndicator(),
        if(error!=null)Text(error!,style:TextStyle(
          color:Theme.of(context).colorScheme.error)),
        if(notice!=null)Text(notice!),
        if(w!=null)...[
          const SizedBox(height:8),
          if(w.isOwner)...[
            Card.outlined(child:ExpansionTile(
              key:const Key('expense-owner-setup'),
              title:const Text('Owner: Expense Categories & Payment Accounts'),
              subtitle:Text(w.categories.length.toString()+' categories • '+
                w.accounts.length.toString()+' accounts'),
              children:[Padding(padding:const EdgeInsets.all(12),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('Add Expense Category',
                    style:Theme.of(context).textTheme.titleMedium),
                  const Text('Operating costs map to expense accounts. '
                    'Stock procurement and capital assets map to assets.'),
                  TextField(key:const Key('expense-category-code'),
                    controller:catCode,enabled:catOp==null,
                    decoration:const InputDecoration(
                      labelText:'Code (e.g. ELECTRICITY)',
                      border:OutlineInputBorder())),
                  const SizedBox(height:8),
                  TextField(key:const Key('expense-category-name'),
                    controller:catName,enabled:catOp==null,
                    decoration:const InputDecoration(
                      labelText:'Category Name',border:OutlineInputBorder())),
                  const SizedBox(height:8),
                  DropdownButtonFormField<String>(
                    key:const Key('expense-category-kind'),
                    value:catKind,isExpanded:true,
                    decoration:const InputDecoration(
                      border:OutlineInputBorder(),labelText:'Accounting Treatment'),
                    items:const [
                      DropdownMenuItem(value:'operating',child:Text('Operating Expense')),
                      DropdownMenuItem(value:'inventory_procurement',
                        child:Text('Inventory Purchase (Asset)')),
                      DropdownMenuItem(value:'capital_asset',
                        child:Text('Capital Equipment (Asset)')),
                    ],onChanged:catOp!=null?null:(v)=>setState((){
                      if(v!=null)catKind=v;
                    })),
                  const SizedBox(height:8),
                  FilledButton.icon(key:const Key('expense-create-category'),
                    onPressed:writing?null:saveCategory,
                    icon:const Icon(Icons.category_outlined),
                    label:Text(catOp==null?'Create Category':'Retry Same Category')),
                  const Divider(height:26),
                  Text('Add Campus Cash or Bank Account',
                    style:Theme.of(context).textTheme.titleMedium),
                  TextField(key:const Key('expense-account-name'),
                    controller:accName,enabled:accOp==null,
                    decoration:const InputDecoration(
                      border:OutlineInputBorder(),labelText:'Account Display Name')),
                  const SizedBox(height:8),
                  DropdownButtonFormField<String>(
                    key:const Key('expense-account-kind'),value:accKind,
                    decoration:const InputDecoration(
                      border:OutlineInputBorder(),labelText:'Account Type'),
                    items:const [
                      DropdownMenuItem(value:'cash',child:Text('Cash Box')),
                      DropdownMenuItem(value:'bank',child:Text('Bank Account')),
                    ],onChanged:accOp!=null?null:(v)=>setState((){
                      if(v!=null)accKind=v;
                    })),
                  const SizedBox(height:8),
                  TextField(key:const Key('expense-account-masked'),
                    controller:accMask,enabled:accOp==null,
                    decoration:const InputDecoration(
                      border:OutlineInputBorder(),
                      labelText:'Masked Account Reference (optional)',
                      helperText:'Only last digits; do not store full banking credentials')),
                  const SizedBox(height:8),
                  FilledButton.icon(key:const Key('expense-create-account'),
                    onPressed:writing?null:saveAccount,
                    icon:const Icon(Icons.account_balance_wallet_outlined),
                    label:Text(accOp==null?'Create Payment Account':'Retry Same Account')),
                ]))])),
            const SizedBox(height:10),
          ],
          if(w.canCreate)Card.outlined(child:ExpansionTile(
            key:const Key('expense-request-form'),
            title:const Text('Add Expense'),
            subtitle:const Text('No Owner or Principal approval required'),
            children:[Padding(padding:const EdgeInsets.all(12),
              child:Column(children:[
                if(w.categories.where((c)=>c.active).isEmpty)
                  const Text('Owner must configure an expense category first.'),
                if(catId!=null)DropdownButtonFormField<String>(
                  key:const Key('expense-request-category'),
                  value:catId,isExpanded:true,
                  decoration:const InputDecoration(
                    border:OutlineInputBorder(),labelText:'Expense Category'),
                  items:[for(final c in w.categories)
                    if(c.active)DropdownMenuItem(value:c.id,
                      child:Text(c.name+' • '+c.kind,
                        overflow:TextOverflow.ellipsis))],
                  onChanged:reqOp!=null?null:(v)=>setState(()=>catId=v)),
                const SizedBox(height:8),
                TextField(key:const Key('expense-request-amount'),
                  controller:reqAmount,enabled:reqOp==null,
                  keyboardType:const TextInputType.numberWithOptions(decimal:true),
                  decoration:InputDecoration(border:const OutlineInputBorder(),
                    labelText:'Expense Amount ('+w.currency+')')),
                const SizedBox(height:8),
                TextField(key:const Key('expense-request-date'),
                  controller:reqDate,enabled:reqOp==null,
                  decoration:const InputDecoration(
                    border:OutlineInputBorder(),labelText:'Expense Date (YYYY-MM-DD)')),
                const SizedBox(height:8),
                TextField(key:const Key('expense-request-purpose'),
                  controller:reqPurpose,enabled:reqOp==null,
                  maxLines:3,maxLength:1000,
                  decoration:const InputDecoration(
                    border:OutlineInputBorder(),labelText:'Expense Description')),
                FilledButton.icon(key:const Key('expense-submit-request'),
                  onPressed:writing||catId==null?null:sendRequest,
                  icon:const Icon(Icons.send_outlined),
                  label:Text(reqOp==null?'Save Expense':'Retry Same Expense')),
              ]))])),
          const SizedBox(height:10),
          Wrap(spacing:8,runSpacing:8,
            crossAxisAlignment:WrapCrossAlignment.center,children:[
              Text('Recorded Expenses',style:Theme.of(context).textTheme.titleLarge),
              SizedBox(width:230,child:DropdownButtonFormField<String>(
                key:const Key('expense-status-filter'),value:status,
                isExpanded:true,
                decoration:const InputDecoration(
                  border:OutlineInputBorder(),labelText:'Status',isDense:true),
                items:const [
                  DropdownMenuItem(value:'all',child:Text('All')),
                  DropdownMenuItem(value:'recorded',child:Text('Recorded')),
                  DropdownMenuItem(value:'approved',child:Text('Approved (legacy)')),
                  DropdownMenuItem(value:'pending',child:Text('Pending (legacy)')),
                  DropdownMenuItem(value:'rejected',child:Text('Rejected (legacy)')),
                  DropdownMenuItem(value:'paid',child:Text('Fully Paid')),
                ],onChanged:(v)=>setState(()=>status=v??'all'))),
              IconButton(onPressed:loading?null:load,
                tooltip:'Refresh Expenses',icon:const Icon(Icons.refresh)),
            ]),
          if(requests.isEmpty)
            const Text('No matching expenses recorded in this campus.'),
          for(final r in requests)
            Card.outlined(key:Key('expense-row-'+r.id),
              child:Padding(padding:const EdgeInsets.all(12),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(r.category+' • '+r.status.toUpperCase(),
                    style:Theme.of(context).textTheme.titleMedium),
                  Text(r.purpose),
                  Text('Date: '+r.expenseDate+' • '+r.kind),
                  Text('Amount '+money(r.amountMinor,w.currency)+
                    ' • Paid '+money(r.paidMinor,w.currency)+
                    ' • Remaining '+money(r.remainingMinor,w.currency)),
                  if(r.rejectionReason!=null)
                    Text('Rejected: '+r.rejectionReason!),
                  for(final p in r.payments)
                    ListTile(dense:true,
                      title:Text('Payment '+money(p.amountMinor,w.currency)),
                      subtitle:Text(p.paidOn+
                        (p.reference==null?'':' • '+p.reference!))),
                  if(widget.evidenceRepository!=null||
                    widget.repository is SupabaseExpenseRepository)
                    OutlinedButton.icon(
                      key:Key('expense-evidence-${r.id}'),
                      onPressed:writing?null:()=>viewEvidence(w,r),
                      icon:const Icon(Icons.attach_file),
                      label:const Text('Attachments (optional)')),
                  if((r.status=='recorded'||r.status=='approved')&&
                      r.remainingMinor>0&&w.canPay)
                    FilledButton.icon(key:Key('expense-pay-'+r.id),
                      onPressed:writing?null:()=>pay(w,r),
                      icon:const Icon(Icons.payments_outlined),
                      label:const Text('Post Cash / Bank Payment')),
                ]))),
          const SizedBox(height:10),
          const Text('Saving an expense records its description and amount. '
            'Only posted cash or bank payments change the cash movement report. '
            'An invoice or receipt is never mandatory.'),
        ],
      ]));
  }
}
