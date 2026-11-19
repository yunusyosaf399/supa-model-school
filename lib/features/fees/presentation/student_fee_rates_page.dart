import 'package:flutter/material.dart';

import '../data/fee_monthly_repository.dart';
import '../data/fee_setup_repository.dart';

/// Owner-only effective-dated rates. Saving rates never changes posted fees.
class StudentFeeRatesPage extends StatefulWidget {
  const StudentFeeRatesPage({super.key,required this.repository,
    required this.plans,required this.schoolId,required this.campusId,
    required this.yearId,required this.yearLabel});
  final FeeSetupRepository repository;
  final FeeSetupSnapshot plans;
  final String schoolId,campusId,yearId,yearLabel;
  @override State<StudentFeeRatesPage> createState()=>_StudentFeeRatesPageState();
}

class _StudentFeeRatesPageState extends State<StudentFeeRatesPage>{
  final search=TextEditingController();
  final amount=TextEditingController();
  final startMonth=TextEditingController(
    text:FeeMonth.normalize(DateTime.now()).substring(0,7));
  final endMonth=TextEditingController();
  final reason=TextEditingController();
  StudentFeeRatesSnapshot? snapshot;
  String? studentId,categoryId,error,notice,operationId;
  String kind='override';
  bool busy=false,loading=false;
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)load();});
  }
  @override void dispose(){
    search.dispose();amount.dispose();startMonth.dispose();
    endMonth.dispose();reason.dispose();super.dispose();
  }
  Future<void> load()async{
    setState((){loading=true;error=null;});
    try{
      final r=await widget.repository.loadStudentRates(
        schoolId:widget.schoolId,campusId:widget.campusId,yearId:widget.yearId);
      if(!mounted)return;
      setState((){
        loading=false;snapshot=r;
        if(!r.students.any((s)=>s.id==studentId))studentId=null;
        if(!r.categories.any((c)=>c.id==categoryId)){
          categoryId=r.categories.isNotEmpty?r.categories.first.id:null;
        }
      });
    }catch(e){
      if(!mounted)return;
      setState((){loading=false;error='Cannot load student rates: '+e.toString();});
    }
  }
  static String? monthDate(String text){
    final t=text.trim();
    if(!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(t))return null;
    return t+'-01';
  }
  FeePlanLine? get classPlanLine {
    final current=snapshot;
    if(current==null)return null;
    final students=current.students.where((s)=>s.id==studentId);
    if(students.isEmpty)return null;
    final classes=widget.plans.classes.where(
      (c)=>c.id==students.first.classId);
    if(classes.isEmpty)return null;
    for(final line in classes.first.plan?.lines??const <FeePlanLine>[]){
      if(line.categoryId==categoryId)return line;
    }
    return null;
  }
  Future<void> save()async{
    if(busy||loading)return;
    final s=snapshot;
    final from=monthDate(startMonth.text);
    final until=endMonth.text.trim().isEmpty?null:monthDate(endMonth.text);
    final value=kind=='override'?FeeMoney.parseMinor(amount.text):null;
    if(s==null||studentId==null||categoryId==null||
       from==null||(endMonth.text.trim().isNotEmpty&&until==null)||
       (until!=null&&until.compareTo(from)<0)||
       (kind=='standard'&&until!=null)||
       (kind=='override'&&(value==null||value<=0))||
       reason.text.trim().length<4||reason.text.trim().length>500){
      setState(()=>error='Select a student, category, valid month and '
        'positive amount when needed, and a reason of 4–500 characters.');
      return;
    }
    final student=s.students.firstWhere((x)=>x.id==studentId);
    final category=s.categories.firstWhere((x)=>x.id==categoryId);
    if(operationId==null){
      final yes=await showDialog<bool>(context:context,builder:(ctx)=>
        AlertDialog(title:const Text('Confirm student rate'),
          content:SingleChildScrollView(child:Text(
            'Student: '+student.name+' ('+student.registration+')\n'
            'Category: '+category.name+'\n'
            'Action: '+kind+'\n'
            'Amount: '+(value==null?'Class rate / Exempt':
                s.currency+' '+FeeMoney.showMinor(value))+'\n'
            'From: '+from+'\n'
            'Until: '+(until??'No end date')+'\n'
            'Reason: '+reason.text.trim()+'\n\n'
            'Only future unbilled periods are affected. '
            'Existing invoices and payments remain unchanged.')),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx,false),
              child:const Text('Edit')),
            FilledButton(key:const Key('student-rate-confirm'),
              onPressed:()=>Navigator.pop(ctx,true),
              child:const Text('Save Rate')),
          ]));
      if(!mounted||yes!=true)return;
      operationId=FeeOperationId.create();
    }
    setState((){busy=true;error=null;});
    try{
      await widget.repository.saveStudentRate(
        schoolId:widget.schoolId,campusId:widget.campusId,
        yearId:widget.yearId,studentId:student.id,
        categoryId:category.id,kind:kind,amountMinor:value,
        startMonth:from,endMonth:until,reason:reason.text.trim(),
        operationId:operationId!);
      if(!mounted)return;
      setState((){
        busy=false;operationId=null;
        notice='Saved '+category.name+' rate for '+student.name+
          ', effective '+startMonth.text.trim()+'.';
      });
      await load();
    }catch(e){
      if(!mounted)return;
      setState((){
        busy=false;
        error='Save not confirmed: '+e.toString()+
          '. Retry the same request ID or check the saved rules.';
      });
    }
  }
  @override Widget build(BuildContext context){
    final s=snapshot;
    final locked=operationId!=null;
    final visible=(s?.students??const <StudentFeeRateStudent>[]).where((item){
      final q=search.text.trim().toLowerCase();
      return q.isEmpty||item.name.toLowerCase().contains(q)||
        item.registration.toLowerCase().contains(q);
    }).toList();
    final rules=(s?.rules??const <StudentFeeRateRule>[]).where(
      (r)=>r.studentId==studentId&&r.categoryId==categoryId).toList();
    final current=rules.where((r)=>r.active).toList();
    final line=classPlanLine;
    return Scaffold(
      appBar:AppBar(title:const Text('Individual Recurring Fee Rates')),
      body:RefreshIndicator(onRefresh:load,
        child:ListView(key:const Key('student-fee-rates-page'),
          padding:const EdgeInsets.all(16),children:[
          Text('Student-specific recurring rates',
            style:Theme.of(context).textTheme.headlineSmall),
          Text('Owner setup • '+widget.yearLabel+' • '+widget.plans.currency),
          const SizedBox(height:8),
          const Text('Set a different monthly/yearly rate, exempt a student, '
            'or restore the class standard. Individual uniform purchases '
            'remain in Add Individual Fee. Posted charges never change.'),
          const SizedBox(height:12),
          if(loading)const LinearProgressIndicator(),
          if(error!=null)Padding(
            padding:const EdgeInsets.symmetric(vertical:8),
            child:Text(error!,style:TextStyle(
              color:Theme.of(context).colorScheme.error))),
          if(notice!=null)Card.outlined(child:ListTile(
            key:const Key('student-rate-saved'),
            leading:const Icon(Icons.check_circle_outline),
            title:Text(notice!))),
          if(s!=null)...[
            TextField(key:const Key('student-rate-search'),
              controller:search,enabled:!locked,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Search student',
                prefixIcon:Icon(Icons.search)),
              onChanged:(_)=>setState((){})),
            const SizedBox(height:10),
            DropdownButtonFormField<String>(
              key:const Key('student-rate-student'),
              value:visible.any((x)=>x.id==studentId)?studentId:null,
              isExpanded:true,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Student'),
              items:[
                for(final st in visible.take(100))
                  DropdownMenuItem(value:st.id,
                    child:Text(st.name+' • '+st.registration+' • '
                      +st.className,overflow:TextOverflow.ellipsis)),
              ],
              onChanged:locked?null:(x)=>setState(()=>studentId=x)),
            const SizedBox(height:10),
            DropdownButtonFormField<String>(
              key:const Key('student-rate-category'),
              value:categoryId,isExpanded:true,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Recurring fee category'),
              items:[
                for(final cat in s.categories)
                  DropdownMenuItem(value:cat.id,child:Text(
                    cat.name+' • '+cat.frequency,
                    overflow:TextOverflow.ellipsis)),
              ],
              onChanged:locked?null:(x)=>setState(()=>categoryId=x)),
            const SizedBox(height:10),
            Card.outlined(child:ListTile(
              title:const Text('Configured class price'),
              subtitle:Text(line==null?'No class fee configured. '
                'A student rate can still be assigned.'
                :(line.optional?'Optional':'Required')+' class fee'),
              trailing:Text(line==null?'—':
                s.currency+' '+FeeMoney.showMinor(line.amountMinor)))),
            if(current.isNotEmpty)
              Card.outlined(child:ListTile(
                key:const Key('student-rate-current'),
                title:const Text('Latest saved student rule'),
                subtitle:Text(current.first.kind+' • from '+
                  current.first.startMonth+
                  (current.first.endMonth==null?'':' to '+
                    current.first.endMonth!)+'\n'+current.first.reason),
                trailing:Text(current.first.amountMinor==null?'—':
                  s.currency+' '+
                  FeeMoney.showMinor(current.first.amountMinor!)))),
            const SizedBox(height:10),
            DropdownButtonFormField<String>(
              key:const Key('student-rate-kind'),
              value:kind,isExpanded:true,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Rate action'),
              items:const [
                DropdownMenuItem(value:'override',
                  child:Text('Set individual rate')),
                DropdownMenuItem(value:'exempt',
                  child:Text('Exempt from this fee')),
                DropdownMenuItem(value:'standard',
                  child:Text('Restore class standard rate')),
              ],onChanged:locked?null:(x)=>setState((){
                kind=x??'override';
                if(x=='standard')endMonth.clear();
              })),
            if(kind=='override')...[
              const SizedBox(height:10),
              TextField(key:const Key('student-rate-amount'),
                controller:amount,enabled:!locked,
                keyboardType:const TextInputType.numberWithOptions(decimal:true),
                decoration:InputDecoration(border:const OutlineInputBorder(),
                  labelText:'Student amount ('+s.currency+')',
                  helperText:'Applies automatically to future billing.')),
            ],
            const SizedBox(height:10),
            Wrap(spacing:10,runSpacing:10,children:[
              SizedBox(width:220,child:TextField(
                key:const Key('student-rate-start'),
                controller:startMonth,enabled:!locked,
                decoration:const InputDecoration(
                  border:OutlineInputBorder(),
                  labelText:'From month (YYYY-MM)'))),
              if(kind!='standard')
                SizedBox(width:220,child:TextField(
                  key:const Key('student-rate-end'),
                  controller:endMonth,enabled:!locked,
                  decoration:const InputDecoration(
                    border:OutlineInputBorder(),
                    labelText:'Until month (optional)'))),
            ]),
            const SizedBox(height:10),
            TextField(key:const Key('student-rate-reason'),
              controller:reason,enabled:!locked,maxLines:2,maxLength:500,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Reason / remarks')),
            const SizedBox(height:12),
            FilledButton.icon(key:const Key('student-rate-save'),
              onPressed:busy||loading?null:save,
              icon:const Icon(Icons.tune_outlined),
              label:Text(locked?'Retry Same Rate Change':'Review & Save Rate')),
            if(rules.length>1)...[
              const SizedBox(height:16),
              ExpansionTile(title:const Text('Rate change history'),
                children:[
                  for(final r in rules)
                    ListTile(
                      title:Text(r.kind=='override'&&r.amountMinor!=null
                        ?s.currency+' '+FeeMoney.showMinor(r.amountMinor!)
                        :r.kind),
                      subtitle:Text('From '+r.startMonth+' • '+r.reason)),
                ]),
            ],
          ],
        ]),
      ),
    );
  }
}
