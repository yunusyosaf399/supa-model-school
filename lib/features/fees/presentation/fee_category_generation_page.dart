import 'package:flutter/material.dart';
import '../data/fee_billing_repository.dart';
import '../data/fee_monthly_repository.dart';
import '../data/fee_payment_repository.dart';
import '../data/fee_setup_repository.dart';

class FeeCategoryGenerationPage extends StatefulWidget {
  const FeeCategoryGenerationPage({super.key,required this.workspace,
    required this.repository,this.initialStudentId,this.initialMonth});
  final FeePaymentWorkspace workspace;
  final FeeBillingRepository repository;
  final String? initialStudentId,initialMonth;
  @override State<FeeCategoryGenerationPage> createState()=>
    _FeeCategoryGenerationPageState();
}
class _FeeCategoryGenerationPageState extends State<FeeCategoryGenerationPage>{
  final month=TextEditingController(text:FeeMonth.normalize(DateTime.now()).substring(0,7));
  final custom=TextEditingController();
  String scope='campus';
  String? targetId,categoryId,error,notice,operationId;
  bool includeOptional=false,useCustom=false,busy=false,done=false;
  bool batch=false;
  final selectedCategoryIds=<String>{};

  @override void initState(){
    super.initState();
    if(widget.initialMonth!=null&&widget.initialMonth!.length>=7){
      month.text=widget.initialMonth!.substring(0,7);
    }
    if(widget.initialStudentId!=null){
      scope='student';targetId=widget.initialStudentId;
    }
    final cats=widget.workspace.categories.where((c)=>c.active).toList();
    if(cats.isNotEmpty)categoryId=cats.first.id;
    selectedCategoryIds.addAll(cats.map((c)=>c.id));
  }
  @override void dispose(){month.dispose();custom.dispose();super.dispose();}

  Future<void> generate() async{
    if(busy||done)return;
    final text=month.text.trim();
    if(!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(text)){
      setState(()=>error='Use YYYY-MM for billing month.');return;
    }
    final categories=widget.workspace.categories.where((c)=>c.active &&
      (!batch||selectedCategoryIds.contains(c.id))).toList();
    if((!batch&&categoryId==null)||(batch&&categories.isEmpty)||
       ((scope=='class'||scope=='student')&&targetId==null)){
      setState(()=>error='Choose a fee category and recipient.');return;
    }
    if(batch&&categories.length>40){
      setState(()=>error='Select no more than 40 categories.');return;
    }
    final amount=!batch&&useCustom?FeeMoney.parseMinor(custom.text):null;
    if(useCustom&&(amount==null||amount<=0)){
      setState(()=>error='Enter a valid positive individual fee.');return;
    }
    if(operationId==null){
      final selected=batch?categories:
        [widget.workspace.categories.firstWhere((c)=>c.id==categoryId)];
      final confirmed=await showDialog<bool>(context:context,builder:(d)=>
        AlertDialog(title:const Text('Confirm Bill Generation'),
          content:SingleChildScrollView(child:Text(
            'Categories ('+selected.length.toString()+'):\n'+
            selected.map((c)=>'• '+c.name+' ('+c.frequency+')').join('\n')+
            '\n\nScope: '+scope+'. Month: '+text+'.\n'+
            (amount==null?'Only effective class fee plans will be used. '
              'Classes without amounts are skipped.':
              'Specific fee: '+widget.workspace.currency+' '+
                FeeMoney.showMinor(amount)+'.')+
            '\nOptional fee items: '+(includeOptional?'included':'excluded')+
            '\n\nAll selected categories commit together. Existing invoices '
            'are never overwritten.')),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(d,false),
              child:const Text('Cancel')),
            FilledButton(key:const Key('fee-generate-confirm'),
              onPressed:()=>Navigator.pop(d,true),
              child:const Text('Generate Fees')),
          ]));
      if(confirmed!=true||!mounted)return;
      operationId=FeeOperationId.create();
    }
    setState((){busy=true;error=null;});
    try{
      if(batch){
        final result=await widget.repository.generateCategories(
          schoolId:widget.workspace.schoolId,
          campusId:widget.workspace.campusId,yearId:widget.workspace.yearId,
          month:text+'-01',
          categoryIds:categories.map((c)=>c.id).toList(),
          scope:scope,targetId:scope=='campus'?null:targetId,
          includeOptional:includeOptional,operationId:operationId!);
        if(!mounted)return;
        setState((){
          done=true;busy=false;
          notice='Generated '+result.added.toString()+
            ' charges across '+result.categories.length.toString()+
            ' categories. Already billed: '+result.skipped.toString()+
            '. Eligible charge entries: '+result.eligible.toString()+
            '.\n'+result.categories.map((c)=>c.name+': '+
              c.added.toString()+' new, '+c.skipped.toString()+
              ' already billed').join('\n');
        });
      }else{
        final result=await widget.repository.generateCategory(
          schoolId:widget.workspace.schoolId,
          campusId:widget.workspace.campusId,yearId:widget.workspace.yearId,
          month:text+'-01',categoryId:categoryId!,scope:scope,
          targetId:scope=='campus'?null:targetId,
          overrideMinor:amount,includeOptional:includeOptional,
          operationId:operationId!);
        if(!mounted)return;
        setState((){
          done=true;busy=false;
          notice='Generated '+result.added.toString()+' '+
            result.category+' charge(s). Already billed: '+
            result.skipped.toString()+'. Eligible: '+
            result.eligible.toString()+'.'+(result.added==0
              ?' Check active plans or enter an individual fee amount.':'');
        });
      }
    }catch(e){
      if(!mounted)return;
      setState((){
        busy=false;
        error='Generation not confirmed: '+e.toString()+
          '. Retry exactly these details, or exit and refresh before trying again.';
      });
    }
  }

  @override Widget build(BuildContext context){
    final w=widget.workspace;
    final classes=<String,String>{
      for(final s in w.students)s.classId:s.className,
    };
    return Scaffold(key:const Key('fee-generate-category-page'),
      appBar:AppBar(title:const Text('Generate Fees')),
      body:ListView(padding:const EdgeInsets.all(14),children:[
        Text('Generate Category Fees',
          style:Theme.of(context).textTheme.headlineSmall),
        Text('Academic year '+w.yearLabel+' • '+w.currency),
        const SizedBox(height:12),
        if(busy)const LinearProgressIndicator(),
        if(error!=null)Text(error!,
          style:TextStyle(color:Theme.of(context).colorScheme.error)),
        if(notice!=null)...[
          Card.outlined(child:Padding(padding:const EdgeInsets.all(14),
            child:Text(notice!))),
          FilledButton(key:const Key('fee-generation-finished'),
            onPressed:()=>Navigator.pop(context,true),
            child:const Text('Return to Fee Ledger')),
        ]else...[
          SwitchListTile(
            key:const Key('fee-generate-batch-mode'),
            value:batch,
            title:const Text('Generate multiple fee categories together'),
            subtitle:const Text('Tuition, transport, annual, one-time and '
              'manual plan items in one atomic billing operation'),
            onChanged:operationId!=null?null:(v)=>
              setState((){
                batch=v;useCustom=false;
              })),
          if(!batch)
            DropdownButtonFormField<String>(
              key:const Key('fee-generate-category'),value:categoryId,
              isExpanded:true,decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Fee Category'),
              items:[
                for(final c in w.categories)
                  if(c.active)DropdownMenuItem(value:c.id,
                    child:Text(c.name+' • '+c.frequency,
                      overflow:TextOverflow.ellipsis)),
              ],onChanged:operationId!=null?null:(v)=>
                setState(()=>categoryId=v))
          else Card.outlined(child:Column(children:[
            const ListTile(title:Text('Categories to bill'),
              subtitle:Text('Unconfigured categories are safely skipped. '
                'Optional items remain excluded unless selected below.')),
            for(final c in w.categories.where((c)=>c.active))
              CheckboxListTile(
                key:Key('fee-generate-batch-'+c.code),
                value:selectedCategoryIds.contains(c.id),
                title:Text(c.name),
                subtitle:Text(c.frequency),
                onChanged:operationId!=null?null:(v)=>setState((){
                  if(v==true)selectedCategoryIds.add(c.id);
                  else selectedCategoryIds.remove(c.id);
                })),
          ])),
          const SizedBox(height:10),
          TextField(key:const Key('fee-generate-month'),controller:month,
            enabled:operationId==null,
            decoration:const InputDecoration(border:OutlineInputBorder(),
              labelText:'Billing Month (YYYY-MM)',
              helperText:'Select a month within the year, not in the future')),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(
            key:const Key('fee-generate-scope'),value:scope,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Bill Recipients'),
            items:const [
              DropdownMenuItem(value:'campus',child:Text('Entire Campus')),
              DropdownMenuItem(value:'class',child:Text('One Class')),
              DropdownMenuItem(value:'student',child:Text('One Student')),
            ],onChanged:operationId!=null?null:(v)=>setState((){
              scope=v??'campus';targetId=null;useCustom=false;
            })),
          if(scope=='class')...[
            const SizedBox(height:10),
            DropdownButtonFormField<String>(
              key:const Key('fee-generate-class'),value:targetId,
              isExpanded:true,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Class'),
              items:[
                for(final c in classes.entries)
                  DropdownMenuItem(value:c.key,child:Text(c.value)),
              ],onChanged:operationId!=null?null:(v)=>
                setState(()=>targetId=v)),
          ],
          if(scope=='student')...[
            const SizedBox(height:10),
            DropdownButtonFormField<String>(
              key:const Key('fee-generate-student'),value:targetId,
              isExpanded:true,decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Student'),
              items:[
                for(final s in w.students)
                  DropdownMenuItem(value:s.id,child:Text(s.name+' • '+
                    s.registration,overflow:TextOverflow.ellipsis)),
              ],onChanged:operationId!=null?null:(v)=>
                setState(()=>targetId=v)),
            if(!batch)CheckboxListTile(key:const Key('fee-generate-custom-amount'),
              value:useCustom,
              title:const Text('Charge a specific amount'),
              subtitle:const Text('Use for individual Transport, Exam, '
                'Resources or other fees without a class plan amount'),
              onChanged:operationId!=null?null:(v)=>
                setState(()=>useCustom=v??false)),
            if(!batch&&useCustom)TextField(
              key:const Key('fee-generate-custom-value'),
              controller:custom,enabled:operationId==null,
              keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:InputDecoration(border:const OutlineInputBorder(),
                labelText:'Amount ('+w.currency+')')),
          ],
          CheckboxListTile(key:const Key('fee-generate-include-optional'),
            value:includeOptional,
            title:const Text('Include optional class fee items'),
            subtitle:const Text('Only select this for students who '
              'should receive the optional fee.'),
            onChanged:operationId!=null?null:(v)=>
              setState(()=>includeOptional=v??false)),
          const SizedBox(height:10),
          const Text('Plan-based bills use active class plans. Yearly '
            'categories are billed once per academic year; one-time '
            'fees once per student. Manual non-plan charges require '
            'individual billing. New charges appear in Quick Pay.'),
          const SizedBox(height:12),
          FilledButton.icon(key:const Key('fee-generate-process'),
            onPressed:busy?null:generate,
            icon:const Icon(Icons.receipt_long_outlined),
            label:Text(operationId==null?'Review & Generate':
              'Retry Same Generation')),
        ],
      ]));
  }
}
