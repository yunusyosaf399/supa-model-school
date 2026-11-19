import 'package:flutter/material.dart';

import '../data/fee_billing_repository.dart';
import '../data/fee_monthly_repository.dart';
import '../data/fee_payment_repository.dart';

/// Server-authorized atomic billing for ONE section or an explicit selection.
/// It uses existing class fee plans; per-student prices belong to the
/// separate Add Individual Fee workflow.
class FeeScopedGenerationPage extends StatefulWidget {
  const FeeScopedGenerationPage({super.key,required this.workspace,
    required this.repository,this.initialMonth});
  final FeePaymentWorkspace workspace;
  final FeeBillingRepository repository;
  final String? initialMonth;

  @override
  State<FeeScopedGenerationPage> createState()=>_FeeScopedGenerationPageState();
}

class _FeeScopedGenerationPageState extends State<FeeScopedGenerationPage> {
  late final TextEditingController month;
  final search=TextEditingController();
  String scope='section';
  String? classFilter,sectionId,error,operationId;
  bool includeOptional=false,saving=false;
  ScopedBillResult? result;
  final selectedCategoryIds=<String>{};
  final selectedStudentIds=<String>{};

  @override
  void initState(){
    super.initState();
    final initial=widget.initialMonth??FeeMonth.normalize(DateTime.now());
    month=TextEditingController(text:initial.substring(0,7));
    final cats=widget.workspace.categories.where((c)=>c.active).toList();
    if(cats.isNotEmpty)selectedCategoryIds.add(cats.first.id);
  }

  @override
  void dispose(){month.dispose();search.dispose();super.dispose();}

  Future<void> generate()async{
    if(saving||result!=null)return;
    final m=month.text.trim();
    final categories=widget.workspace.categories.where(
      (c)=>c.active&&selectedCategoryIds.contains(c.id)).toList();
    if(!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(m)||
      categories.isEmpty||categories.length>20||
      (scope=='section'&&sectionId==null)||
      (scope=='selected'&&(selectedStudentIds.isEmpty||
         selectedStudentIds.length>120))){
      setState(()=>error='Choose a valid month, fee categories and '
        'one section or 1–120 individual students.');
      return;
    }
    if(operationId==null){
      final count=scope=='section'
        ?widget.workspace.students.where((s)=>s.sectionId==sectionId).length
        :selectedStudentIds.length;
      final yes=await showDialog<bool>(context:context,builder:(ctx)=>
        AlertDialog(
          title:const Text('Review fee generation'),
          content:SingleChildScrollView(child:Text(
            'Billing month: $m\n'
            'Scope: ${scope=='section'?'One Section':'Selected Students'}\n'
            'Students in preview: $count\n'
            'Categories: ${categories.map((c)=>c.name).join(', ')}\n'
            'Optional class items: ${includeOptional?'included':'excluded'}\n\n'
            'The school server checks the actual eligible students. '
            'Only configured class-plan amounts are used; individual '
            'custom prices are entered separately. Existing scheduled '
            'bills are not duplicated. All charges post together.')),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(ctx,false),
              child:const Text('Edit')),
            FilledButton(key:const Key('fee-scoped-confirm'),
              onPressed:()=>Navigator.pop(ctx,true),
              child:const Text('Generate Fees')),
          ]));
      if(!mounted||yes!=true)return;
      operationId=FeeOperationId.create();
    }
    setState((){saving=true;error=null;});
    try{
      final value=await widget.repository.generateScoped(
        schoolId:widget.workspace.schoolId,
        campusId:widget.workspace.campusId,
        yearId:widget.workspace.yearId,
        month:'$m-01',
        categoryIds:categories.map((c)=>c.id).toList(),
        scope:scope,sectionId:scope=='section'?sectionId:null,
        studentIds:scope=='selected'?selectedStudentIds.toList():[],
        includeOptional:includeOptional,operationId:operationId!);
      if(!mounted)return;
      setState((){saving=false;result=value;});
    }catch(e){
      if(!mounted)return;
      setState((){
        saving=false;
        error='Fees not confirmed: $e. Retry with the same request ID, or '
          'return to the ledger and refresh before creating a new request.';
      });
    }
  }

  @override
  Widget build(BuildContext context){
    final w=widget.workspace;
    final locked=operationId!=null;
    final classes=<String,String>{
      for(final s in w.students)s.classId:s.className,
    };
    final sections=<String,String>{};
    for(final s in w.students){
      if(s.sectionId!=null &&
        (classFilter==null||s.classId==classFilter)){
        sections[s.sectionId!]='${s.className} — ${s.sectionName??'Section'}';
      }
    }
    final visible=w.students.where((s){
      final q=search.text.trim().toLowerCase();
      return (classFilter==null||classFilter==s.classId) &&
        (q.isEmpty||s.name.toLowerCase().contains(q)||
          s.registration.toLowerCase().contains(q));
    }).toList()..sort((a,b)=>a.name.compareTo(b.name));
    final cats=w.categories.where((c)=>c.active).toList();

    return Scaffold(
      appBar:AppBar(title:const Text('Section / Selected Student Fees')),
      body:ListView(key:const Key('fee-scoped-generation-page'),
        padding:const EdgeInsets.all(16),children:[
        Text('Generate fees for a group',
          style:Theme.of(context).textTheme.headlineSmall),
        Text('Campus and year are locked to your current authorized '
          'workspace: ${w.yearLabel} • ${w.currency}.'),
        const SizedBox(height:12),
        if(saving)const LinearProgressIndicator(),
        if(error!=null)Text(error!,style:TextStyle(
          color:Theme.of(context).colorScheme.error)),
        if(result!=null)...[
          Card.outlined(child:Padding(
            padding:const EdgeInsets.all(12),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Fees generated successfully',
                style:Theme.of(context).textTheme.titleMedium),
              Text('${result!.students} students • ${result!.added} new fees'
                   ' • ${result!.skipped} already billed'),
              for(final c in result!.categories)
                Text('${c.name}: ${c.added} new, ${c.skipped} existing'),
            ]))),
          FilledButton(key:const Key('fee-scoped-finished'),
            onPressed:()=>Navigator.pop(context,true),
            child:const Text('Return to Fee Register')),
        ]else...[
          SegmentedButton<String>(
            key:const Key('fee-scoped-scope'),
            segments:const [
              ButtonSegment(value:'section',label:Text('One section'),
                icon:Icon(Icons.groups_outlined)),
              ButtonSegment(value:'selected',label:Text('Selected students'),
                icon:Icon(Icons.fact_check_outlined)),
            ],
            selected:{scope},
            onSelectionChanged:locked?null:(v)=>setState((){
              scope=v.first;sectionId=null;selectedStudentIds.clear();
            })),
          const SizedBox(height:12),
          TextField(key:const Key('fee-scoped-month'),
            controller:month,enabled:!locked,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Billing month (YYYY-MM)')),
          const SizedBox(height:12),
          DropdownButtonFormField<String>(
            key:const Key('fee-scoped-class-filter'),
            value:classFilter,isExpanded:true,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Filter by class'),
            items:[
              const DropdownMenuItem(value:'all',child:Text('All classes')),
              for(final c in classes.entries)
                DropdownMenuItem(value:c.key,child:Text(c.value,
                  overflow:TextOverflow.ellipsis)),
            ],
            onChanged:locked?null:(v)=>setState((){
              classFilter=v=='all'?null:v;
              sectionId=null;
            })),
          const SizedBox(height:12),
          if(scope=='section')...[
            DropdownButtonFormField<String>(
              key:const Key('fee-scoped-section'),
              value:sectionId,isExpanded:true,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Section to bill'),
              items:[
                for(final section in sections.entries)
                  DropdownMenuItem(value:section.key,
                    child:Text(section.value,overflow:TextOverflow.ellipsis)),
              ],
              onChanged:locked?null:(v)=>setState(()=>sectionId=v)),
            const SizedBox(height:8),
            Text(sectionId==null?'Select a section.':
              '${w.students.where((s)=>s.sectionId==sectionId).length} '
              'students in the current preview; server verifies eligibility.'),
          ]else...[
            TextField(key:const Key('fee-scoped-student-search'),
              controller:search,enabled:!locked,
              decoration:const InputDecoration(border:OutlineInputBorder(),
                prefixIcon:Icon(Icons.search),
                labelText:'Search students / admission numbers'),
              onChanged:(_)=>setState((){})),
            const SizedBox(height:8),
            Row(children:[
              Expanded(child:Text('${selectedStudentIds.length} students selected')),
              TextButton(
                key:const Key('fee-scoped-clear-students'),
                onPressed:locked?null:()=>setState(()=>selectedStudentIds.clear()),
                child:const Text('Clear')),
            ]),
            Card.outlined(child:Column(children:[
              for(final student in visible.take(50))
                CheckboxListTile(
                  key:Key('fee-scoped-student-${student.registration}'),
                  dense:true,
                  title:Text(student.name),
                  subtitle:Text('${student.registration} • '
                      '${student.className} • ${student.sectionName??''}'),
                  value:selectedStudentIds.contains(student.id),
                  onChanged:locked?null:(v)=>setState((){
                    if(v==true){
                      if(selectedStudentIds.length<120){
                        selectedStudentIds.add(student.id);
                      }
                    }else{selectedStudentIds.remove(student.id);}
                  })),
            ])),
            if(visible.length>50)
              const Text('Showing first 50 matching students. '
                'Search or filter to find the remaining students.'),
          ],
          const SizedBox(height:12),
          Text('Choose fee categories',
            style:Theme.of(context).textTheme.titleMedium),
          const Text('Only rates configured in each class fee plan will post. '
            'For an individual custom uniform price, use Add Individual Fee.'),
          Card.outlined(child:Column(children:[
            for(final c in cats)
              CheckboxListTile(
                key:Key('fee-scoped-category-${c.code}'),
                title:Text(c.name),
                subtitle:Text(c.frequency),
                value:selectedCategoryIds.contains(c.id),
                onChanged:locked?null:(v)=>setState((){
                  if(v==true){selectedCategoryIds.add(c.id);}
                  else{selectedCategoryIds.remove(c.id);}
                })),
          ])),
          CheckboxListTile(
            key:const Key('fee-scoped-include-optional'),
            value:includeOptional,
            title:const Text('Include optional class fee items'),
            onChanged:locked?null:(v)=>setState(()=>includeOptional=v??false)),
          const SizedBox(height:12),
          FilledButton.icon(
            key:const Key('fee-scoped-process'),
            onPressed:saving?null:generate,
            icon:const Icon(Icons.post_add_outlined),
            label:Text(locked?'Retry Same Operation':'Review & Generate')),
        ],
      ]),
    );
  }
}
