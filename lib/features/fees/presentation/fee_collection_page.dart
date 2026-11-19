import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fee_monthly_repository.dart';
import '../data/fee_setup_repository.dart';
import '../data/fee_payment_repository.dart';
import '../data/fee_billing_repository.dart';
import '../data/fee_cashbook_repository.dart';
import 'fee_cashbook_page.dart';
import 'fee_detailed_ledger_page.dart';
import 'fee_category_generation_page.dart';
import 'fee_scoped_generation_page.dart';
import 'individual_fee_page.dart';
import 'fee_other_people_page.dart';

String feeDisplay(int minor, String currency) =>
  currency + ' ' + FeeMoney.showMinor(minor);
String feeFrequency(String value) => switch (value) {
  'monthly' => 'Monthly',
  'yearly' => 'Yearly',
  'one_time' => 'One-time',
  'manual' => 'Manual / On demand',
  _ => value,
};

class FeeCollectionPage extends StatefulWidget {
  const FeeCollectionPage({super.key,required this.repository,
    required this.schoolId,required this.campusId,this.yearId,
    this.billingRepository,this.cashbookRepository});
  final FeePaymentRepository repository;
  final FeeBillingRepository? billingRepository;
  final FeeCashbookRepository? cashbookRepository;
  final String schoolId,campusId;
  final String? yearId;
  @override State<FeeCollectionPage> createState()=>_FeeCollectionPageState();
}

class _FeeCollectionPageState extends State<FeeCollectionPage> {
  FeePaymentWorkspace? data;
  String? error,yearId,classId,sectionId,categoryId;
  String frequency='all',query='';
  bool loading=false;
  int request=0;

  @override void initState(){
    super.initState();
    yearId=widget.yearId;
    WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)load();});
  }
  @override void didUpdateWidget(covariant FeeCollectionPage old){
    super.didUpdateWidget(old);
    if(old.schoolId!=widget.schoolId||old.campusId!=widget.campusId||
       old.yearId!=widget.yearId){
      yearId=widget.yearId;classId=null;sectionId=null;categoryId=null;
      data=null;
      WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)load();});
    }
  }
  Future<void> load() async {
    final seq=++request;
    setState(() {loading=true;error=null;});
    try{
      final result=await widget.repository.workspace(
        schoolId:widget.schoolId,campusId:widget.campusId,yearId:yearId);
      if(!mounted||seq!=request)return;
      setState((){
        data=result;yearId=result.yearId;loading=false;
      });
    }catch(e){
      if(!mounted||seq!=request)return;
      setState((){loading=false;error='Fee data unavailable: '+e.toString();});
    }
  }
  void changeYear(String? next){
    if(next==null||next==yearId)return;
    setState((){
      yearId=next;classId=null;sectionId=null;categoryId=null;data=null;
    });
    load();
  }

  List<FeePaymentCharge> charges(FeePaymentStudent s)=>s.charges.where(
    (c)=>(frequency=='all'||c.frequency==frequency)&&
      (categoryId==null||c.categoryId==categoryId)).toList();

  bool matches(FeePaymentStudent s){
    final q=query.trim().toLowerCase();
    return (classId==null||s.classId==classId)&&
      (sectionId==null||s.sectionId==sectionId)&&
      (q.isEmpty||s.name.toLowerCase().contains(q)||
        s.registration.toLowerCase().contains(q))&&
      ((frequency=='all'&&categoryId==null)||charges(s).isNotEmpty);
  }

  Future<void> openStatement(
      FeePaymentWorkspace workspace,FeePaymentStudent student) async {
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>FeeDetailedLedgerPage(
        repository:widget.repository,workspace:workspace,student:student)));
    if(mounted)await load();
  }

  Future<void> quickPay(FeePaymentWorkspace workspace,FeePaymentStudent s) async{
    final saved=await Navigator.push<bool>(context,MaterialPageRoute(
      builder:(_)=>QuickPayPage(repository:widget.repository,
        workspace:workspace,student:s)));
    if(saved==true&&mounted)await load();
  }

  Future<void> generateFee(FeePaymentWorkspace workspace,
      {String? studentId}) async {
    final billing=widget.billingRepository;
    if(!workspace.canCollect||billing==null)return;
    final saved=await Navigator.push<bool>(context,MaterialPageRoute(
      builder:(_)=>FeeCategoryGenerationPage(
        workspace:workspace,repository:billing,
        initialStudentId:studentId)));
    if(saved==true&&mounted)await load();
  }

  Future<void> addIndividual(FeePaymentWorkspace workspace,
      {String? studentId}) async {
    final billing=widget.billingRepository;
    if(!workspace.canCollect||billing==null)return;
    final saved=await Navigator.push<bool>(context,MaterialPageRoute(
      builder:(_)=>IndividualFeePage(
        workspace:workspace,repository:billing,
        initialStudentId:studentId)));
    if(saved==true&&mounted)await load();
  }


  Future<void> scopedFees(FeePaymentWorkspace workspace) async {
    final billing=widget.billingRepository;
    if(!workspace.canCollect||billing==null)return;
    final saved=await Navigator.push<bool>(context,MaterialPageRoute(
      builder:(_)=>FeeScopedGenerationPage(
        workspace:workspace,repository:billing)));
    if(saved==true&&mounted)await load();
  }

  Future<void> otherPayers(FeePaymentWorkspace workspace) async {
    final billing=widget.billingRepository;
    if(billing==null)return;
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>FeeOtherPeoplePage(repository:billing,
        schoolId:workspace.schoolId,campusId:workspace.campusId,
        yearId:workspace.yearId)));
    if(mounted)await load();
  }

  Future<void> openCashbook(FeePaymentWorkspace workspace) async {
    final cashbook=widget.cashbookRepository;
    if(cashbook==null)return;
    await Navigator.push<void>(context,MaterialPageRoute(
      builder:(_)=>Scaffold(
        appBar:AppBar(title:const Text('Fee Collection Reports')),
        body:FeeCashbookPage(repository:cashbook,
          schoolId:workspace.schoolId,yearId:workspace.yearId,
          initialCampusId:workspace.campusId))));
    if(mounted)await load();
  }

  Widget filterSelect(String label,String key,String? value,
    List<DropdownMenuItem<String>> items,ValueChanged<String?> onChanged)=>
    SizedBox(width:205,child:DropdownButtonFormField<String>(
      key:Key(key),value:value,isExpanded:true,
      decoration:InputDecoration(labelText:label,
        border:const OutlineInputBorder(),isDense:true),
      items:items,onChanged:loading?null:onChanged));

  @override Widget build(BuildContext context){
    final w=data;
    final students=(w?.students??const <FeePaymentStudent>[])
      .where(matches).toList();
    final categories=w?.categories??const <FeePaymentCategory>[];
    final classNames=<String,String>{
      for(final s in w?.students??const <FeePaymentStudent>[])
        s.classId:s.className};
    final sections=<String,String>{
      for(final s in w?.students??const <FeePaymentStudent>[])
        if(s.sectionId!=null&&(classId==null||s.classId==classId))
          s.sectionId!:s.sectionName??'Unknown'};
    final total=students.fold<int>(0,(sum,s)=>sum+
      charges(s).fold<int>(0,(acc,c)=>acc+c.outstandingMinor));
    return RefreshIndicator(onRefresh:load,child:ListView(
      key:const Key('fee-collection-live-page'),
      padding:const EdgeInsets.all(14),children:[
        Wrap(spacing:8,runSpacing:6,alignment:WrapAlignment.spaceBetween,
          crossAxisAlignment:WrapCrossAlignment.center,children:[
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Fee Collection & Categories',
              style:Theme.of(context).textTheme.headlineSmall),
            const Text('Live posted balances • Quick Pay'),
          ]),
          IconButton(key:const Key('fee-collection-refresh'),
            onPressed:loading?null:load,icon:const Icon(Icons.refresh)),
        ]),
        if(loading)const LinearProgressIndicator(),
        if(error!=null)ListTile(leading:const Icon(Icons.error_outline),
          title:Text(error!),trailing:TextButton(onPressed:load,
            child:const Text('Retry'))),
        if(w!=null)...[
          const SizedBox(height:12),
          Card.outlined(child:Padding(padding:const EdgeInsets.all(12),
            child:Wrap(spacing:18,runSpacing:6,children:[
              Text('Students: '+students.length.toString()),
              Text('Outstanding: '+feeDisplay(total,w.currency)),
              Text(w.canCollect?'View and collect':'View only'),
            ]))),
          const SizedBox(height:10),
          if(widget.billingRepository!=null)
            Wrap(spacing:8,runSpacing:8,children:[
              if(w.canCollect)FilledButton.icon(
                key:const Key('fee-generate-category-open'),
                onPressed:()=>generateFee(w),
                icon:const Icon(Icons.post_add_outlined),
                label:const Text('Generate Category Fees')),
              if(w.canCollect)OutlinedButton.icon(
                key:const Key('fee-generate-scoped-open'),
                onPressed:()=>scopedFees(w),
                icon:const Icon(Icons.groups_outlined),
                label:const Text('Section / Selected Students')),
              if(w.canCollect)FilledButton.icon(
                key:const Key('fee-add-individual-open'),
                onPressed:()=>addIndividual(w),
                icon:const Icon(Icons.person_add_alt_1),
                label:const Text('Add Fee to One Student')),
              OutlinedButton.icon(
                key:const Key('fee-other-payers-open'),
                onPressed:()=>otherPayers(w),
                icon:const Icon(Icons.person_search_outlined),
                label:const Text('Other Payers')),
              if(widget.cashbookRepository!=null)OutlinedButton.icon(
                key:const Key('fee-open-cashbook'),
                onPressed:()=>openCashbook(w),
                icon:const Icon(Icons.summarize_outlined),
                label:const Text('Collection Reports')),
            ]),
          const SizedBox(height:10),
          TextField(key:const Key('fee-collection-search'),
            decoration:const InputDecoration(border:OutlineInputBorder(),
              prefixIcon:Icon(Icons.search),
              labelText:'Student name or registration'),
            onChanged:(v)=>setState(()=>query=v)),
          const SizedBox(height:10),
          Wrap(spacing:9,runSpacing:9,children:[
            filterSelect('Year','fee-filter-year',yearId,[
              for(final y in w.years)DropdownMenuItem(value:y.id,
                child:Text(y.label))],changeYear),
            filterSelect('Class','fee-filter-class',classId,[
              const DropdownMenuItem(value:'all',child:Text('All classes')),
              for(final c in classNames.entries)
                DropdownMenuItem(value:c.key,child:Text(c.value)),
            ],(v)=>setState((){
              classId=v=='all'?null:v;sectionId=null;
            })),
            filterSelect('Section','fee-filter-section',sectionId,[
              const DropdownMenuItem(value:'all',child:Text('All sections')),
              for(final s in sections.entries)
                DropdownMenuItem(value:s.key,child:Text(s.value)),
            ],(v)=>setState(()=>sectionId=v=='all'?null:v)),
            filterSelect('Frequency','fee-filter-frequency',frequency,[
              const DropdownMenuItem(value:'all',child:Text('All frequencies')),
              for(final f in const ['monthly','yearly','one_time','manual'])
                DropdownMenuItem(value:f,child:Text(feeFrequency(f))),
            ],(v)=>setState((){
              frequency=v??'all';categoryId=null;
            })),
            filterSelect('Category','fee-filter-category',categoryId,[
              const DropdownMenuItem(value:'all',child:Text('All categories')),
              for(final c in categories)
                if(frequency=='all'||frequency==c.frequency)
                  DropdownMenuItem(value:c.id,
                    child:Text(c.name,overflow:TextOverflow.ellipsis)),
            ],(v)=>setState(()=>categoryId=v=='all'?null:v)),
          ]),
          const SizedBox(height:16),
          Text('Categories by Frequency',
            style:Theme.of(context).textTheme.titleLarge),
          for(final f in const ['monthly','yearly','one_time','manual'])
            Card.outlined(child:ExpansionTile(
              key:Key('fee-group-'+f),
              title:Text(feeFrequency(f)),
              subtitle:Text(categories.where((c)=>c.frequency==f)
                .length.toString()+' configured categories'),
              children:[
                for(final c in categories.where((cat)=>cat.frequency==f))
                  ListTile(
                    title:Text(c.name),subtitle:Text(c.code+
                      (c.active?' • Active':' • Inactive')),
                    trailing:Text(feeDisplay(students.fold<int>(0,(acc,s)=>
                      acc+s.charges.where((ch)=>ch.categoryId==c.id)
                        .fold<int>(0,(a,ch)=>a+ch.outstandingMinor)),
                      w.currency)),
                  ),
              ])),
          const SizedBox(height:12),
          Text('Student Fee Accounts',
            style:Theme.of(context).textTheme.titleLarge),
          if(students.isEmpty)
            const Padding(padding:EdgeInsets.all(16),
              child:Text('No matching student or posted charge.')),
          LayoutBuilder(builder:(context,size){
            const gap=10.0;
            final columns=size.maxWidth>=1050?3:size.maxWidth>=680?2:1;
            final width=(size.maxWidth-gap*(columns-1))/columns;
            return Wrap(spacing:gap,runSpacing:gap,children:[
              for(final s in students)
                SizedBox(width:width,child:Card.outlined(
                  key:Key('fee-student-'+s.registration),
                  child:Padding(padding:const EdgeInsets.all(12),
                    child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                      children:[
                        Text(s.name,style:Theme.of(context).textTheme.titleMedium),
                        Text(s.registration),
                        Text(s.className+' • '+(s.sectionName??'No section')),
                        const SizedBox(height:6),
                        Text('Due: '+feeDisplay(charges(s).fold<int>(0,
                          (a,c)=>a+c.outstandingMinor),w.currency)),
                        if(widget.billingRepository!=null&&w.canCollect)
                          TextButton.icon(
                            key:Key('fee-generate-student-'+s.registration),
                            onPressed:()=>generateFee(w,studentId:s.id),
                            icon:const Icon(Icons.add_circle_outline),
                            label:const Text('Generate Fee')),
                        Align(alignment:Alignment.centerRight,
                          child:FilledButton.icon(
                            key:Key('fee-quickpay-'+s.registration),
                            onPressed:w.canCollect&&s.outstandingMinor>0
                              ?()=>quickPay(w,s):null,
                            icon:const Icon(Icons.payments_outlined),
                            label:const Text('Quick Pay'))),
                        OutlinedButton.icon(
                          key:Key('fee-detailed-statement-${s.registration}'),
                          onPressed:()=>openStatement(w,s),
                          icon:const Icon(Icons.article_outlined),
                          label:const Text('Detailed Statement')),
                        if(widget.billingRepository!=null&&w.canCollect)
                          OutlinedButton.icon(
                            key:Key('fee-add-individual-${s.registration}'),
                            onPressed:()=>addIndividual(w,studentId:s.id),
                            icon:const Icon(Icons.receipt_long_outlined),
                            label:const Text('Add Individual Fee')),
                        ExpansionTile(
                          key:Key('fee-charge-lines-${s.registration}'),
                          tilePadding:EdgeInsets.zero,
                          title:const Text('Category-wise fee records'),
                          subtitle:Text('${s.charges.length} posted charges'),
                          children:[
                            for(final c in s.charges)
                              ListTile(
                                dense:true,
                                title:Text(c.categoryName+' • '+feeFrequency(c.frequency)),
                                subtitle:Text('Billing: '+c.month+' • Due: '+c.dueOn+
                                  '\\nBilled: '+feeDisplay(c.netMinor,w.currency)+
                                  ' • Collected: '+feeDisplay(c.paidMinor,w.currency)),
                                trailing:Text(feeDisplay(c.outstandingMinor,w.currency),
                                  style:TextStyle(color:c.outstandingMinor>0
                                    ?Theme.of(context).colorScheme.error:null)),
                              ),
                          ]),
                      ])))),
            ]);
          }),
        ],
      ]));
  }
}

class QuickPayPage extends StatefulWidget {
  const QuickPayPage({super.key,required this.repository,
    required this.workspace,required this.student});
  final FeePaymentRepository repository;
  final FeePaymentWorkspace workspace;
  final FeePaymentStudent student;
  @override State<QuickPayPage> createState()=>_QuickPayPageState();
}

class _QuickPayPageState extends State<QuickPayPage> {
  final amount=TextEditingController(),bankRef=TextEditingController();
  final controllers=<String,TextEditingController>{};
  final selectedCategories=<String>{};
  final operationId=FeeOperationId.create();
  List<QuickPayAllocation>? frozen;
  String method='cash';
  String? error;
  bool review=false,busy=false,posted=false;
  QuickPayReceipt? receipt;

  List<FeePaymentCharge> get dues=>widget.student.charges.where(
    (c)=>c.outstandingMinor>0).toList();
  List<FeePaymentCharge> get selected=>dues.where(
    (c)=>selectedCategories.contains(c.categoryId)).toList();

  @override void initState(){
    super.initState();
    selectedCategories.addAll(dues.map((c)=>c.categoryId));
    amount.text=FeeMoney.showMinor(widget.student.outstandingMinor);
  }
  @override void dispose(){
    amount.dispose();bankRef.dispose();
    for(final c in controllers.values)c.dispose();
    super.dispose();
  }
  void prepare(){
    final money=FeeMoney.parseMinor(amount.text);
    if(money==null||money<=0){
      setState(()=>error='Enter a valid positive amount.');return;
    }
    if(method=='bank'&&bankRef.text.trim().length<3){
      setState(()=>error='Enter the verified bank reference.');return;
    }
    try{
      final plan=QuickPayPlanner.suggest(
        widget.student,selectedCategories,money);
      final perCharge={for(final a in plan)a.chargeId:a.amountMinor};
      for(final c in controllers.values)c.dispose();
      controllers.clear();
      for(final c in selected){
        controllers[c.id]=TextEditingController(
          text:FeeMoney.showMinor(perCharge[c.id]??0));
      }
      setState((){review=true;error=null;});
    }on FormatException catch(e){setState(()=>error=e.message);}
  }
  List<QuickPayAllocation> readLines(){
    final lines=<QuickPayAllocation>[];
    for(final c in selected){
      final money=FeeMoney.parseMinor(controllers[c.id]!.text);
      if(money==null||money<0){
        throw FormatException('Invalid amount for '+c.categoryName);
      }
      if(money>0)lines.add(
        QuickPayAllocation(chargeId:c.id,amountMinor:money));
    }
    final total=FeeMoney.parseMinor(amount.text);
    if(total==null)throw const FormatException('Invalid total amount');
    QuickPayPlanner.validate(widget.student,total,lines);
    return lines;
  }

  Future<void> process() async{
    if(busy||posted)return;
    if(frozen==null){
      List<QuickPayAllocation> draft;
      try{draft=readLines();}
      on FormatException catch(e){
        setState(()=>error=e.message);return;
      }
      final yes=await showDialog<bool>(context:context,builder:(d)=>
        AlertDialog(title:const Text('Confirm Fee Collection'),
          content:Text('Post '+feeDisplay(FeeMoney.parseMinor(amount.text)!,
             widget.workspace.currency)+' for '+widget.student.name+
             ' using '+method.toUpperCase()+'? '
             'Posted receipt allocations are immutable.'),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(d,false),
              child:const Text('Edit Review')),
            FilledButton(key:const Key('quickpay-confirm-process'),
              onPressed:()=>Navigator.pop(d,true),
              child:const Text('Confirm Processing')),
          ]));
      if(yes!=true||!mounted)return;
      frozen=List.unmodifiable(draft);
    }
    setState((){busy=true;error=null;});
    try{
      final result=await widget.repository.collect(
        schoolId:widget.workspace.schoolId,
        campusId:widget.workspace.campusId,
        yearId:widget.workspace.yearId,
        studentId:widget.student.id,
        amountMinor:FeeMoney.parseMinor(amount.text)!,
        method:method,
        bankReference:method=='bank'?bankRef.text.trim():null,
        operationId:operationId,allocations:frozen!);
      if(!mounted)return;
      setState((){posted=true;receipt=result;busy=false;});
    }catch(e){
      if(!mounted)return;
      setState((){
        busy=false;
        error='Payment not confirmed: '+e.toString()+
          '. Retry exactly the same payment, or close and refresh '
          'before making any new payment.';
      });
    }
  }

  Widget selectionStep(){
    final categories=widget.workspace.categories.where((cat)=>
      dues.any((c)=>c.categoryId==cat.id)).toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Total due: '+feeDisplay(widget.student.outstandingMinor,
        widget.workspace.currency)),
      const SizedBox(height:10),
      TextField(key:const Key('quickpay-amount'),controller:amount,
        keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:InputDecoration(border:const OutlineInputBorder(),
          labelText:'Amount received ('+widget.workspace.currency+')')),
      const SizedBox(height:10),
      DropdownButtonFormField<String>(
        key:const Key('quickpay-method'),value:method,
        decoration:const InputDecoration(border:OutlineInputBorder(),
          labelText:'Payment Method'),
        items:const [
          DropdownMenuItem(value:'cash',child:Text('Cash')),
          DropdownMenuItem(value:'bank',child:Text('Bank Transfer')),
        ],
        onChanged:(v)=>setState((){if(v!=null)method=v;}),
      ),
      if(method=='bank')...[
        const SizedBox(height:10),
        TextField(key:const Key('quickpay-bank-ref'),
          controller:bankRef,decoration:const InputDecoration(
            border:OutlineInputBorder(),labelText:'Bank reference')),
      ],
      const SizedBox(height:12),
      Text('Choose fee categories',
        style:Theme.of(context).textTheme.titleMedium),
      for(final c in categories)
        CheckboxListTile(key:Key('quickpay-category-'+c.code),
          value:selectedCategories.contains(c.id),
          title:Text(c.name),subtitle:Text(feeFrequency(c.frequency)+
            ' • Due '+feeDisplay(dues.where((d)=>d.categoryId==c.id)
              .fold<int>(0,(a,d)=>a+d.outstandingMinor),
              widget.workspace.currency)),
          onChanged:(v)=>setState((){
            if(v==true)selectedCategories.add(c.id);
            else selectedCategories.remove(c.id);
          })),
      const SizedBox(height:10),
      FilledButton.icon(key:const Key('quickpay-preview'),
        onPressed:prepare,icon:const Icon(Icons.preview_outlined),
        label:const Text('Auto Allocate & Review')),
    ]);
  }

  Widget reviewStep(){
    var allocated=0;
    var valid=true;
    for(final c in selected){
      final parsed=FeeMoney.parseMinor(controllers[c.id]?.text??'');
      if(parsed==null||parsed<0||parsed>c.outstandingMinor)valid=false;
      else allocated+=parsed;
    }
    final received=FeeMoney.parseMinor(amount.text)??0;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Review payment: '+feeDisplay(received,
        widget.workspace.currency),
        style:Theme.of(context).textTheme.titleMedium),
      const Text('Edit each allocation before processing. '
        'Enter 0.00 to skip a posted charge.'),
      const SizedBox(height:8),
      for(final c in selected)
        Card.outlined(child:Padding(padding:const EdgeInsets.all(12),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(c.categoryName+' • '+feeFrequency(c.frequency),
              style:const TextStyle(fontWeight:FontWeight.bold)),
            Text('Due '+c.dueOn+' • Available '+
              feeDisplay(c.outstandingMinor,widget.workspace.currency)),
            const SizedBox(height:8),
            TextField(key:Key('quickpay-line-'+c.id),
              controller:controllers[c.id],enabled:frozen==null,
              keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:InputDecoration(border:const OutlineInputBorder(),
                labelText:'Allocate ('+widget.workspace.currency+')'),
              onChanged:(_)=>setState((){})),
          ]))),
      Text('Allocated: '+feeDisplay(allocated,widget.workspace.currency)),
      Text('Remaining: '+feeDisplay(received-allocated,
        widget.workspace.currency)),
      if(!valid||allocated!=received)const Text(
        'Allocation must match the payment without exceeding any charge.'),
      const SizedBox(height:10),
      Wrap(spacing:8,runSpacing:8,children:[
        OutlinedButton(onPressed:frozen!=null?null:
          ()=>setState(()=>review=false),child:const Text('Edit Selection')),
        FilledButton.icon(key:const Key('quickpay-process'),
          onPressed:busy||(frozen==null&&
             (!valid||allocated!=received))?null:process,
          icon:const Icon(Icons.verified_outlined),
          label:Text(frozen==null?'Process Fee Record':
            'Retry Same Processing')),
      ]),
    ]);
  }

  @override Widget build(BuildContext context){
    return Scaffold(key:const Key('quickpay-page'),
      appBar:AppBar(title:Text('Quick Pay • '+widget.student.name)),
      body:ListView(padding:const EdgeInsets.all(14),children:[
        Text(widget.student.registration+' • '+widget.student.className+
          ' • '+(widget.student.sectionName??'No section'),
          style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:12),
        if(busy)const LinearProgressIndicator(),
        if(error!=null)Text(error!,style:TextStyle(
          color:Theme.of(context).colorScheme.error)),
        if(receipt!=null)...[
          const Icon(Icons.check_circle_outline,size:48),
          Text('Payment recorded',
            style:Theme.of(context).textTheme.headlineSmall),
          SelectableText('Receipt: '+receipt!.number),
          Text('Collected '+feeDisplay(
            receipt!.amountMinor,widget.workspace.currency)),
          const Text('The receipt and allocations are saved in Supabase.'),
          TextButton.icon(onPressed:()=>Clipboard.setData(
            ClipboardData(text:receipt!.number)),
            icon:const Icon(Icons.copy_outlined),
            label:const Text('Copy Receipt')),
          FilledButton(key:const Key('quickpay-done'),
            onPressed:()=>Navigator.pop(context,true),
            child:const Text('Back to Ledger')),
        ]else if(review)reviewStep()else selectionStep(),
      ]));
  }
}
