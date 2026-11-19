import 'package:flutter/material.dart';

import '../data/fee_billing_repository.dart';
import '../data/fee_monthly_repository.dart';
import '../data/fee_payment_repository.dart';
import '../data/fee_setup_repository.dart';

/// An explicit one-student bill, distinct from recurring class generation.
/// Individual uniform purchases are valid more than once: each confirmation
/// has its own server-idempotent operation and immutable fee charge.
class IndividualFeePage extends StatefulWidget {
  const IndividualFeePage({super.key,required this.workspace,
    required this.repository,this.initialStudentId});
  final FeePaymentWorkspace workspace;
  final FeeBillingRepository repository;
  final String? initialStudentId;

  @override
  State<IndividualFeePage> createState()=>_IndividualFeePageState();
}

class _IndividualFeePageState extends State<IndividualFeePage> {
  final search=TextEditingController();
  final amount=TextEditingController();
  final description=TextEditingController();
  late final TextEditingController chargeDate;
  late final TextEditingController dueDate;
  String? studentId,categoryId,error,operationId;
  String priceMode='custom';
  IndividualFeeResult? completed;
  bool saving=false;

  static String dateString(DateTime date)=>
    '${date.year.toString().padLeft(4,'0')}-'
    '${date.month.toString().padLeft(2,'0')}-'
    '${date.day.toString().padLeft(2,'0')}';

  @override
  void initState(){
    super.initState();
    final today=dateString(DateTime.now());
    chargeDate=TextEditingController(text:today);
    dueDate=TextEditingController(text:today);
    if(widget.workspace.students.any((s)=>s.id==widget.initialStudentId)) {
      studentId=widget.initialStudentId;
    }
    final categories=widget.workspace.categories.where((c)=>c.active).toList();
    if(categories.isNotEmpty) {
      categoryId=categories.first.id;
      for(final c in categories) {
        if(c.name.toLowerCase().contains('uniform')) {
          categoryId=c.id;
          break;
        }
      }
    }
  }

  @override
  void dispose(){
    search.dispose();amount.dispose();description.dispose();
    chargeDate.dispose();dueDate.dispose();super.dispose();
  }

  Future<void> save()async {
    if(saving||completed!=null)return;
    final student=widget.workspace.students.where((s)=>s.id==studentId);
    final category=widget.workspace.categories.where((c)=>c.id==categoryId);
    final amt=priceMode=='custom'?FeeMoney.parseMinor(amount.text):null;
    final start=DateTime.tryParse(chargeDate.text.trim());
    final due=DateTime.tryParse(dueDate.text.trim());
    if(student.isEmpty||category.isEmpty||description.text.trim().length<4||
       (priceMode=='custom'&&(amt==null||amt<=0))||
       start==null||due==null||due.isBefore(start)||
       dateString(start)!=chargeDate.text.trim()||
       dateString(due)!=dueDate.text.trim()){
      setState(()=>error='Select a student and category, enter a valid amount, '
          'description and YYYY-MM-DD dates (due date cannot be earlier).');
      return;
    }
    if(operationId==null) {
      final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>
        AlertDialog(
          title:const Text('Review individual fee'),
          content:Text(
            'Student: ${student.first.name} (${student.first.registration})\n'
            'Category: ${category.first.name}\n'
            'Price: ${priceMode=='standard'?'Class rate calculated by school':
              widget.workspace.currency+' '+FeeMoney.showMinor(amt!)}\n'
            'Charge date: ${chargeDate.text.trim()}\n'
            'Due date: ${dueDate.text.trim()}\n'
            'Description: ${description.text.trim()}\n\n'
            'Only this student will be billed. Class rates stay unchanged. '
            'A separate uniform purchase can be billed later.'),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx,false),
              child:const Text('Edit')),
            FilledButton(key:const Key('individual-fee-confirm'),
              onPressed:()=>Navigator.pop(ctx,true),
              child:const Text('Add Fee')),
          ],
        ));
      if(!mounted||confirmed!=true)return;
      operationId=FeeOperationId.create();
    }
    setState((){saving=true;error=null;});
    try {
      final result=await widget.repository.addIndividualCharge(
        schoolId:widget.workspace.schoolId,
        campusId:widget.workspace.campusId,
        yearId:widget.workspace.yearId,
        studentId:studentId!,categoryId:categoryId!,
        chargeOn:chargeDate.text.trim(),dueOn:dueDate.text.trim(),
        priceMode:priceMode,amountMinor:amt,
        description:description.text.trim(),operationId:operationId!);
      if(!mounted)return;
      setState((){saving=false;completed=result;});
    }catch(e){
      if(!mounted)return;
      setState((){
        saving=false;
        error='Fee not confirmed: $e. Retry with the same details and operation '
          'ID, or return to the ledger to check whether it was saved.';
      });
    }
  }

  @override
  Widget build(BuildContext context){
    final w=widget.workspace;
    final locked=operationId!=null;
    final matched=w.students.where((s){
      final q=search.text.trim().toLowerCase();
      return q.isEmpty || s.name.toLowerCase().contains(q)
        || s.registration.toLowerCase().contains(q);
    }).toList();
    final categories=w.categories.where((c)=>c.active).toList();
    return Scaffold(
      appBar:AppBar(title:const Text('Add Individual Student Fee')),
      body:ListView(
        key:const Key('individual-fee-page'),
        padding:const EdgeInsets.all(16),children:[
        Text('Charge one student',style:Theme.of(context).textTheme.headlineSmall),
        const Text('Uniform, books, certificates, fines and other fee '
          'categories may have different amounts for each student. '
          'This does not change fees for classmates.'),
        const SizedBox(height:14),
        if(saving)const LinearProgressIndicator(),
        if(error!=null)Padding(
          padding:const EdgeInsets.only(bottom:12),
          child:Text(error!,style:TextStyle(
            color:Theme.of(context).colorScheme.error))),
        if(completed!=null)...[
          Card.outlined(child:ListTile(
            key:const Key('individual-fee-saved'),
            leading:const Icon(Icons.check_circle_outline),
            title:Text('Fee saved: ${completed!.category}'),
            subtitle:Text('Gross ${feeText(completed!.grossMinor,w.currency)} • '
              'Discount ${feeText(completed!.discountMinor,w.currency)} • '
              'Due ${feeText(completed!.netMinor,w.currency)}\n'
              'Charge ID: ${completed!.chargeId}'))),
          FilledButton(key:const Key('individual-fee-return'),
            onPressed:()=>Navigator.pop(context,true),
            child:const Text('Return to Student Fee Ledger')),
        ]else...[
          if(!locked)TextField(
            key:const Key('individual-fee-search'),
            controller:search,
            decoration:const InputDecoration(border:OutlineInputBorder(),
              labelText:'Search student name or admission number',
              prefixIcon:Icon(Icons.search)),
            onChanged:(_)=>setState((){})),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(
            key:const Key('individual-fee-student'),
            value:matched.any((s)=>s.id==studentId)?studentId:null,
            isExpanded:true,
            decoration:const InputDecoration(border:OutlineInputBorder(),
              labelText:'Student'),
            items:[
              for(final s in locked
                  ?w.students.where((s)=>s.id==studentId)
                  :matched.take(100))
                DropdownMenuItem(value:s.id,child:Text(
                  '${s.name} • ${s.registration} • ${s.className}',
                  overflow:TextOverflow.ellipsis)),
            ],
            onChanged:locked?null:(v)=>setState(()=>studentId=v)),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(
            key:const Key('individual-fee-category'),
            value:categoryId,isExpanded:true,
            decoration:const InputDecoration(border:OutlineInputBorder(),
              labelText:'Fee category'),
            items:[
              for(final c in categories)
                DropdownMenuItem(value:c.id,child:Text(
                  '${c.name} • ${c.frequency}',overflow:TextOverflow.ellipsis)),
            ],
            onChanged:locked?null:(v)=>setState(()=>categoryId=v)),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(
            key:const Key('individual-fee-pricing'),
            value:priceMode,isExpanded:true,
            decoration:const InputDecoration(border:OutlineInputBorder(),
              labelText:'Price source'),
            items:const [
              DropdownMenuItem(value:'custom',
                child:Text('Custom amount for this student only')),
              DropdownMenuItem(value:'standard',
                child:Text('Use configured class standard rate')),
            ],onChanged:locked?null:(v)=>setState(()=>priceMode=v??'custom')),
          if(priceMode=='custom')...[
            const SizedBox(height:10),
            TextField(
              key:const Key('individual-fee-amount'),
              controller:amount,enabled:!locked,
              keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:InputDecoration(border:const OutlineInputBorder(),
                labelText:'Fee amount (${w.currency})',
                helperText:'Total for this charge; enter a new charge for '
                  'another uniform purchase')),
          ],
          const SizedBox(height:10),
          TextField(
            key:const Key('individual-fee-description'),
            controller:description,enabled:!locked,
            maxLines:2,
            decoration:const InputDecoration(border:OutlineInputBorder(),
              labelText:'Description / reason / uniform items',
              helperText:'Example: Uniform trousers, size M, 2 pieces. '
                'Required for the audit trail.')),
          const SizedBox(height:10),
          Wrap(spacing:10,runSpacing:10,children:[
            SizedBox(width:220,child:TextField(
              key:const Key('individual-fee-charge-date'),
              controller:chargeDate,enabled:!locked,
              decoration:const InputDecoration(border:OutlineInputBorder(),
                labelText:'Charge date (YYYY-MM-DD)'))),
            SizedBox(width:220,child:TextField(
              key:const Key('individual-fee-due-date'),
              controller:dueDate,enabled:!locked,
              decoration:const InputDecoration(border:OutlineInputBorder(),
                labelText:'Due date (YYYY-MM-DD)'))),
          ]),
          const SizedBox(height:10),
          const Text('Saving creates an individual charge only. Payment '
            'collection is separate. Repeated legitimate uniform purchases '
            'use separate records; changing a class plan is not required.'),
          const SizedBox(height:16),
          FilledButton.icon(
            key:const Key('individual-fee-save'),
            onPressed:saving?null:save,
            icon:const Icon(Icons.person_add_alt_1),
            label:Text(locked?'Retry Same Charge':'Review & Add Fee')),
        ],
      ]),
    );
  }

  String feeText(int minor,String currency)=>
    '$currency ${FeeMoney.showMinor(minor)}';
}
