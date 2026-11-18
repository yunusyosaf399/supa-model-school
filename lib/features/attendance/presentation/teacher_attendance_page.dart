import 'package:flutter/material.dart';

import '../data/attendance_repository.dart';

/// Teacher-only, online-only first-period attendance workspace. Every mark is
/// explicitly chosen; the app never defaults unmarked students to 'present'.
class TeacherAttendancePage extends StatefulWidget {
  const TeacherAttendancePage({
    super.key,required this.repository,
  });
  final AttendanceRepository repository;

  @override State<TeacherAttendancePage> createState()=>
    _TeacherAttendancePageState();
}
class _TeacherAttendancePageState extends State<TeacherAttendancePage> {
  TeacherAttendanceSnapshot? _data;
  String? _error;
  bool _loading=false;
  int _request=0;

  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted)_load();
    });
  }
  Future<void> _load() async{
    final request=++_request;
    setState((){_loading=true;_error=null;});
    try {
      final x=await widget.repository.today();
      if(!mounted||request!=_request)return;
      setState((){
        _data=x;
        _loading=false;
      });
    }catch(e) {
      if(!mounted||request!=_request)return;
      setState((){
        _error='Teacher attendance unavailable: '+e.toString();
        _loading=false;
      });
    }
  }

  Future<void> _take(TeacherAttendanceSection section) async {
    await Navigator.push<void>(context,MaterialPageRoute<void>(
      builder:(_)=>TeacherRegisterPage(
        repository:widget.repository,section:section)));
    if(mounted)await _load();
  }

  @override Widget build(BuildContext context){
    final data=_data;
    return Scaffold(
      appBar:AppBar(title:const Text('Teacher Attendance'),
        actions:[
          IconButton(key:const Key('teacher-attendance-refresh'),
            onPressed:_loading?null:_load,icon:const Icon(Icons.refresh)),
        ]),
      body:RefreshIndicator(onRefresh:_load,child:ListView(
        key:const Key('teacher-attendance-live-page'),
        padding:const EdgeInsets.all(14),
        children:[
          if(_loading)const LinearProgressIndicator(),
          if(_error!=null)ListTile(
            leading:const Icon(Icons.error_outline),
            title:Text(_error!),
            trailing:TextButton(onPressed:_loading?null:_load,
              child:const Text('Retry'))),
          if(data!=null)...[
            Text('First-period attendance • '+data.today,
              style:Theme.of(context).textTheme.titleLarge),
            Text('School time zone: '+data.timezone),
            const SizedBox(height:8),
            Card.outlined(child:Padding(padding:const EdgeInsets.all(12),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Text(data.policyActive
                    ? 'Attendance policy active'
                    : 'Attendance policy is not active today.'),
                  Text(data.schoolDay
                    ? 'Approved instructional/exam day'
                    : 'Today is not an approved school day.'),
                  Text('Submission deadline: '+(data.deadline??'Not set')),
                  if(!data.canSubmit)
                    const Text('Submitting attendance is not available '
                      'at this time. Please contact school administration.'),
                ]))),
            const SizedBox(height:12),
            Text('Assigned Sections ('+data.sections.length.toString()+')',
              style:Theme.of(context).textTheme.titleLarge),
            if(data.sections.isEmpty)
              const Padding(padding:EdgeInsets.all(16),
                child:Text('No active section has been assigned. '
                  'Ask the Owner to assign you in Attendance Setup.')),
            for(final section in data.sections)
              Card.outlined(
                key:Key('teacher-attendance-section-'+section.assignmentId),
                child:Padding(padding:const EdgeInsets.all(14),
                  child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      Text(section.className+' • Section '+section.sectionName,
                        style:Theme.of(context).textTheme.titleMedium),
                      Text(section.students.length.toString()+' students'),
                      Text('Register: '+(section.registerStatus??'Not started')),
                      const SizedBox(height:8),
                      if(section.registerStatus=='submitted'||
                         section.registerStatus=='locked')
                        OutlinedButton(
                          key:Key('teacher-attendance-view-'+section.assignmentId),
                          onPressed:()=>_take(section),
                          child:const Text('View Submitted Marks'))
                      else
                        FilledButton.icon(
                          key:Key('teacher-attendance-take-'+section.assignmentId),
                          onPressed:data.canSubmit&&section.students.isNotEmpty
                            ?()=>_take(section):null,
                          icon:const Icon(Icons.fact_check_outlined),
                          label:const Text('Take Attendance')),
                    ]))),
          ],
        ],
      )),
    );
  }
}

class TeacherRegisterPage extends StatefulWidget {
  const TeacherRegisterPage({
    super.key,required this.repository,required this.section,
  });
  final AttendanceRepository repository;
  final TeacherAttendanceSection section;

  @override State<TeacherRegisterPage> createState()=>_TeacherRegisterPageState();
}

class _TeacherRegisterPageState extends State<TeacherRegisterPage> {
  final Map<String,String> _marks={};
  final Map<String,TextEditingController> _reasons={};
  late final String _operationId;
  List<AttendanceMarkDraft>? _lockedSubmission;
  String? _registerId,_error;
  bool _busy=false,_submitted=false;

  bool get _readOnly=>_submitted||
    widget.section.registerStatus=='submitted'||
    widget.section.registerStatus=='locked';

  @override void initState(){
    super.initState();
    _operationId=attendanceOperationId();
    for(final student in widget.section.students){
      if(student.mark!=null)_marks[student.enrollmentId]=student.mark!;
      _reasons[student.enrollmentId]=TextEditingController();
    }
  }

  @override void dispose(){
    for(final c in _reasons.values)c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if(_busy||_readOnly)return;
    List<AttendanceMarkDraft> payload;
    if(_lockedSubmission!=null) {
      payload=_lockedSubmission!;
    } else {
      payload=[];
      for(final s in widget.section.students){
        final value=_marks[s.enrollmentId];
        final reason=_reasons[s.enrollmentId]!.text.trim();
        if(value==null||
          ({'sick','leave','excused'}.contains(value)&&reason.length<4)) {
          setState(()=>_error='Mark every student. Sick, leave and '
            'excused statuses require a reason of at least four characters.');
          return;
        }
        payload.add(AttendanceMarkDraft(
          enrollmentId:s.enrollmentId,status:value,
          reason:reason.isEmpty?null:reason));
      }
    }

    if(_lockedSubmission==null){
      final confirmed=await showDialog<bool>(context:context,builder:(d)=>
        AlertDialog(
          title:const Text('Submit Attendance?'),
          content:Text('Submit '+payload.length.toString()+
            ' explicitly marked students. The confirmed attendance '
            'becomes immutable and cannot be edited from this screen.'),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(d,false),
              child:const Text('Cancel')),
            FilledButton(key:const Key('teacher-confirm-submit'),
              onPressed:()=>Navigator.pop(d,true),
              child:const Text('Submit to Supabase')),
          ],
        ));
      if(confirmed!=true||!mounted)return;
      _lockedSubmission=List.unmodifiable(payload);
    }

    setState((){_busy=true;_error=null;});
    try{
      _registerId??=await widget.repository.openRegister(
        assignmentId:widget.section.assignmentId);
      final result=await widget.repository.submit(
        registerId:_registerId!,
        operationId:_operationId,
        marks:_lockedSubmission!);
      if(!mounted)return;
      if(result.marked!=_lockedSubmission!.length){
        throw StateError('Incomplete submission confirmation');
      }
      setState((){
        _submitted=true;
        _busy=false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Attendance submitted successfully.')));
    }catch(e){
      if(!mounted)return;
      setState((){
        _error='Attendance not confirmed: '+e.toString()+
          '. Retry using the same marks, or exit and refresh.';
        _busy=false;
      });
    }
  }

  @override Widget build(BuildContext context) {
    final readonly=_readOnly||_lockedSubmission!=null;
    final unmarked=widget.section.students.where(
      (s)=>!_marks.containsKey(s.enrollmentId)).length;
    return Scaffold(
      appBar:AppBar(title:Text(widget.section.className+
        ' • '+widget.section.sectionName)),
      body:ListView(
        key:const Key('teacher-attendance-register-page'),
        padding:const EdgeInsets.all(12),
        children:[
          Text('First Period • '+widget.section.students.length.toString()+
            ' enrolled students',
            style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:5),
          if(_readOnly)
            const Text('Read-only: these attendance marks have been submitted.')
          else
            Text('Unmarked: '+unmarked.toString()+
              '. Every student requires an explicit mark.'),
          if(_lockedSubmission!=null&&!_readOnly)
            const Text('The submission details are locked for safe retry.'),
          if(_busy)const LinearProgressIndicator(),
          if(_error!=null)
            Padding(padding:const EdgeInsets.all(8),
              child:Text(_error!,
                style:TextStyle(color:Theme.of(context).colorScheme.error))),
          const SizedBox(height:12),
          for(final student in widget.section.students)
            Card.outlined(
              key:Key('teacher-mark-'+student.enrollmentId),
              child:Padding(padding:const EdgeInsets.all(12),
                child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                  children:[
                    Text(student.name,
                      style:Theme.of(context).textTheme.titleMedium),
                    Text(student.registration),
                    const SizedBox(height:7),
                    DropdownButtonFormField<String>(
                      key:Key('teacher-status-'+student.enrollmentId),
                      value:_marks[student.enrollmentId],
                      isExpanded:true,
                      decoration:const InputDecoration(
                        labelText:'Attendance Status',
                        border:OutlineInputBorder()),
                      items:const [
                        DropdownMenuItem(value:'present',child:Text('Present')),
                        DropdownMenuItem(value:'absent',child:Text('Absent')),
                        DropdownMenuItem(value:'late',child:Text('Late')),
                        DropdownMenuItem(value:'sick',child:Text('Sick')),
                        DropdownMenuItem(value:'leave',child:Text('On Leave')),
                        DropdownMenuItem(value:'excused',child:Text('Excused')),
                      ],
                      onChanged:readonly?null:(status){
                        if(status!=null)setState(
                          ()=>_marks[student.enrollmentId]=status);
                      }),
                    if({'sick','leave','excused'}.contains(
                          _marks[student.enrollmentId]))...[
                      const SizedBox(height:8),
                      TextField(
                        key:Key('teacher-reason-'+student.enrollmentId),
                        controller:_reasons[student.enrollmentId],
                        enabled:!readonly,
                        decoration:const InputDecoration(
                          labelText:'Reason (required)',
                          border:OutlineInputBorder())),
                    ],
                  ]))),
          const SizedBox(height:12),
          if(!_readOnly)
            FilledButton.icon(
              key:const Key('teacher-submit-attendance'),
              onPressed:_busy||widget.section.students.isEmpty
                ?null:_submit,
              icon:const Icon(Icons.cloud_upload_outlined),
              label:Text(_lockedSubmission==null
                ?'Review and Submit Attendance':'Retry Same Submission')),
          if(_readOnly)const Card.outlined(child:Padding(
            padding:EdgeInsets.all(12),
            child:Text('Submitted marks are permanent evidence. Any '
              'correction requires an authorized correction workflow.'))),
          const SizedBox(height:20),
        ],
      )),
    );
  }
}
