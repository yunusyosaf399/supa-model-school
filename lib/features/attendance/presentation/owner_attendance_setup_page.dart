import 'package:flutter/material.dart';

import '../../auth/data/owner_auth_gateway.dart';
import '../data/attendance_repository.dart';

/// Owner-only attendance policy and class-teacher assignment workspace.
/// Teacher credentials are created separately in Owner > User Management.
class OwnerAttendanceSetupPage extends StatefulWidget {
  const OwnerAttendanceSetupPage({
    super.key,required this.owner,required this.repository,
    this.selectedCampusId,
  });
  final OwnerAccess owner;
  final AttendanceRepository repository;
  final String? selectedCampusId;

  @override
  State<OwnerAttendanceSetupPage> createState()=>_OwnerAttendanceSetupPageState();
}

class _OwnerAttendanceSetupPageState extends State<OwnerAttendanceSetupPage> {
  OwnerAttendanceSnapshot? _data;
  String? _error,_notice;
  bool _busy=false;
  int _request=0;
  final _selections=<String,String>{};

  String? get _campusId {
    for(final campus in widget.owner.campuses) {
      if(campus.id==widget.selectedCampusId)return campus.id;
    }
    return widget.owner.campuses.isEmpty?null:widget.owner.campuses.first.id;
  }

  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted)_load();
    });
  }
  @override void didUpdateWidget(covariant OwnerAttendanceSetupPage old) {
    super.didUpdateWidget(old);
    if(old.selectedCampusId!=widget.selectedCampusId||
      old.owner.schoolId!=widget.owner.schoolId||
      old.owner.activeYearId!=widget.owner.activeYearId) {
      _data=null;_selections.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if(mounted)_load();
      });
    }
  }

  Future<void> _load() async {
    final campus=_campusId,year=widget.owner.activeYearId;
    if(campus==null||year==null){
      setState(()=>_error='Configure an active campus and academic year.');
      return;
    }
    final request=++_request;
    setState(() {_busy=true;_error=null;});
    try{
      final result=await widget.repository.ownerSetup(
        schoolId:widget.owner.schoolId,campusId:campus,yearId:year);
      if(!mounted||request!=_request)return;
      setState((){
        _data=result;_busy=false;
        _selections.clear();
        for(final s in result.sections) {
          if(s.teacherId!=null)_selections[s.sectionId]=s.teacherId!;
        }
      });
    }catch(error){
      if(!mounted||request!=_request)return;
      setState((){_error='Attendance setup unavailable: '+error.toString();
        _busy=false;});
    }
  }

  Future<void> _save(Future<void> Function() action,String notice) async{
    if(_busy)return;
    setState((){_busy=true;_error=null;_notice=null;});
    try {
      await action();
      if(!mounted)return;
      _notice=notice;
      await _load();
    }catch(error){
      if(!mounted)return;
      setState((){
        _busy=false;
        _error='Change not confirmed: '+error.toString();
      });
    }
  }

  Future<DateTime?> _pickDate(OwnerAttendanceSnapshot data) async{
    final today=DateTime.parse(data.today);
    final end=DateTime.tryParse(widget.owner.activeYearEndsOn??'')??
      today.add(const Duration(days:90));
    if(end.isBefore(today))return null;
    return showDatePicker(context:context,initialDate:today,
      firstDate:today,lastDate:end);
  }
  String _date(DateTime value)=>
    value.year.toString().padLeft(4,'0')+'-'+
    value.month.toString().padLeft(2,'0')+'-'+
    value.day.toString().padLeft(2,'0');

  Future<void> _activate(OwnerAttendanceSnapshot data) async {
    final picked=await _pickDate(data);
    if(picked==null||!mounted)return;
    final confirmed=await showDialog<bool>(context:context,
      builder:(dialog)=>AlertDialog(
        title:const Text('Activate Attendance Policy'),
        content:Text('Activate the draft attendance policy from '+
          _date(picked)+' in '+data.timezone+'. Only verified assigned '
          'Teachers can submit actual attendance, before the deadline.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Cancel')),
          FilledButton(key:const Key('owner-confirm-attendance-activation'),
            onPressed:()=>Navigator.pop(dialog,true),
            child:const Text('Activate')),
        ]));
    if(confirmed!=true||!mounted)return;
    await _save(() => widget.repository.activatePolicy(
      schoolId:data.schoolId,campusId:data.campusId,
      yearId:data.yearId,effectiveDate:_date(picked)),
      'Attendance policy activated.');
  }

  Future<void> _addDay(OwnerAttendanceSnapshot data) async {
    final picked=await _pickDate(data);
    if(picked==null||!mounted)return;
    final kind=await showDialog<String>(context:context,builder:(dialog)=>
      SimpleDialog(title:Text('Set '+_date(picked)+' as a school day'),
        children:[
          SimpleDialogOption(
            key:const Key('owner-day-instructional'),
            onPressed:()=>Navigator.pop(dialog,'instructional'),
            child:const Text('Instructional day')),
          SimpleDialogOption(
            onPressed:()=>Navigator.pop(dialog,'exam'),
            child:const Text('Examination day')),
        ]));
    if(kind==null||!mounted)return;
    await _save(()=>widget.repository.createSchoolDay(
      schoolId:data.schoolId,campusId:data.campusId,yearId:data.yearId,
      date:_date(picked),kind:kind),
      'Approved school calendar date saved.');
  }

  Future<void> _link(OwnerAttendanceSnapshot data,
      AttendanceTeacher teacher) async {
    final options=data.employees.where((e)=>
      e.linkedUserId==null||e.linkedUserId==teacher.id).toList();
    if(options.isEmpty)return;
    final employee=await showDialog<AttendanceEmployee>(
      context:context,builder:(dialog)=>SimpleDialog(
        title:Text('Link HR employee to '+teacher.name),
        children:[
          const Padding(padding:EdgeInsets.symmetric(horizontal:18,vertical:8),
            child:Text('Linking a SAMPLE employee to a real Teacher login '
              'should only be used for controlled testing.')),
          for(final e in options)
            SimpleDialogOption(
              onPressed:()=>Navigator.pop(dialog,e),
              child:Text(e.name+' • '+e.number)),
        ]));
    if(employee==null||!mounted)return;
    await _save(()=>widget.repository.linkEmployee(
      schoolId:data.schoolId,campusId:data.campusId,
      teacherId:teacher.id,employeeId:employee.id),
      'Teacher account linked to the selected employee.');
  }

  Widget _sectionCard(OwnerAttendanceSnapshot data,AttendanceSection sec) {
    final selected=_selections[sec.sectionId];
    return Card.outlined(
      key:Key('owner-attendance-section-'+sec.sectionId),
      child:Padding(padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(sec.className+' • Section '+sec.sectionName,
            style:Theme.of(context).textTheme.titleMedium),
          Text(sec.students.toString()+' enrolled students'),
          const SizedBox(height:8),
          DropdownButtonFormField<String>(
            key:Key('owner-attendance-teacher-'+sec.sectionId),
            value:selected,
            isExpanded:true,
            decoration:const InputDecoration(
              labelText:'First-period class Teacher',
              border:OutlineInputBorder()),
            items:[
              for(final teacher in data.teachers)
                DropdownMenuItem(value:teacher.id,
                  child:Text(teacher.name,overflow:TextOverflow.ellipsis)),
            ],
            onChanged:_busy||data.teachers.isEmpty?null:(id){
              if(id!=null)setState(()=>_selections[sec.sectionId]=id);
            },
          ),
          const SizedBox(height:8),
          Align(alignment:Alignment.centerRight,child:FilledButton(
            key:Key('owner-save-teacher-'+sec.sectionId),
            onPressed:_busy||selected==null||
              selected==sec.teacherId?null:()=>_save(
              ()=>widget.repository.assignTeacher(
                schoolId:data.schoolId,campusId:data.campusId,
                yearId:data.yearId,classId:sec.classId,
                sectionId:sec.sectionId,teacherId:selected),
              'Class Teacher assigned successfully.'),
            child:const Text('Save Assignment'))),
        ])),
    );
  }

  @override Widget build(BuildContext context) {
    final data=_data;
    return LayoutBuilder(builder:(context,bounds)=>RefreshIndicator(
      onRefresh:_load,
      child:ListView(key:const Key('owner-attendance-setup-page'),
        padding:EdgeInsets.all(bounds.maxWidth>=800?24:12),children:[
        Wrap(alignment:WrapAlignment.spaceBetween,
          crossAxisAlignment:WrapCrossAlignment.center,
          spacing:8,runSpacing:8,children:[
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Attendance Setup',
              style:Theme.of(context).textTheme.headlineSmall),
            const Text('Owner • Live Supabase'),
          ]),
          IconButton(key:const Key('owner-attendance-refresh'),
            onPressed:_busy?null:_load,
            icon:const Icon(Icons.refresh)),
        ]),
        if(_busy)const LinearProgressIndicator(),
        if(_error!=null)ListTile(
          leading:const Icon(Icons.error_outline),
          title:Text(_error!),
          trailing:TextButton(onPressed:_busy?null:_load,
            child:const Text('Retry'))),
        if(_notice!=null)Text(_notice!,
          style:TextStyle(color:Theme.of(context).colorScheme.primary)),
        if(data!=null)...[
          const SizedBox(height:12),
          Card.outlined(child:Padding(padding:const EdgeInsets.all(14),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Attendance policy',
                style:Theme.of(context).textTheme.titleMedium),
              Text('Status: '+(data.policy?.status??'Not configured')),
              Text('Effective from: '+(data.policy?.from??'Not set')),
              Text('First period deadline: '+
                (data.policy?.deadline??'Not set')+' ('+data.timezone+')'),
              const SizedBox(height:6),
              if(data.policy?.status=='draft')
                FilledButton.icon(
                  key:const Key('owner-activate-attendance'),
                  onPressed:_busy?null:()=>_activate(data),
                  icon:const Icon(Icons.verified_outlined),
                  label:const Text('Approve and Activate Policy')),
            ]))),
          const SizedBox(height:8),
          OutlinedButton.icon(
            key:const Key('owner-add-attendance-day'),
            onPressed:_busy?null:()=>_addDay(data),
            icon:const Icon(Icons.event_available_outlined),
            label:const Text('Add Instructional / Exam Day')),
          const SizedBox(height:8),
          Text('School calendar',
            style:Theme.of(context).textTheme.titleMedium),
          if(data.days.isEmpty)
            const Text('No school days configured in the next three weeks.'),
          for(final day in data.days)
            ListTile(dense:true,title:Text(day.date+' • '+day.kind),
              subtitle:Text(day.title??'')),
          const Divider(),
          Text('Teacher Accounts ('+data.teachers.length.toString()+')',
            style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:8),
          if(data.teachers.isEmpty)
            const Card.outlined(child:Padding(
              padding:EdgeInsets.all(16),
              child:Text('No active Teacher accounts. Use Settings → '
                'User Management to create a Teacher with an Owner-set '
                'password. Then grant Attendance Read and Record permissions '
                'in the Owner permission panel.'),
            )),
          for(final teacher in data.teachers)
            Card.outlined(child:ListTile(
              title:Text(teacher.name),
              subtitle:Text(teacher.email+
                (teacher.employeeNo==null?' • HR profile not linked':
                  ' • '+teacher.employeeNo!)),
              trailing:teacher.employeeNo==null
                ? TextButton(
                  onPressed:_busy?null:()=>_link(data,teacher),
                  child:const Text('Link Employee')):null,
            )),
          const SizedBox(height:12),
          Text('Class and Section Teacher Assignments',
            style:Theme.of(context).textTheme.titleLarge),
          Text('Each section can have one primary first-period Teacher. '
            'No attendance marks are generated during assignment.',
            style:Theme.of(context).textTheme.bodySmall),
          const SizedBox(height:10),
          LayoutBuilder(builder:(context,size){
            final cols=size.maxWidth>=1000?3:
              size.maxWidth>=600?2:1;
            const gap=9.0;
            final width=(size.maxWidth-gap*(cols-1))/cols;
            return Wrap(spacing:gap,runSpacing:gap,children:[
              for(final sec in data.sections)
                SizedBox(width:width,child:_sectionCard(data,sec)),
            ]);
          }),
        ],
      ]),
    ));
  }
}
