import 'package:flutter/material.dart';

import '../data/exam_repository.dart';

/// Responsive, live-only exam/test management; navigation shell remains unchanged.
/// Every operation is verified again inside the Supabase DB21 RPC.
class ExamManagementPage extends StatefulWidget {
  const ExamManagementPage({
    super.key, required this.repository, required this.schoolId,
    required this.campusId, this.yearId, this.canCreate = true,
    this.canUpdate = true,
  });
  final ExamRepository repository;
  final String schoolId, campusId;
  final String? yearId;
  final bool canCreate, canUpdate;

  @override
  State<ExamManagementPage> createState() => _ExamManagementPageState();
}

class _ExamManagementPageState extends State<ExamManagementPage> {
  final _subjectName = TextEditingController();
  final _examTitle = TextEditingController();
  final _maximum = TextEditingController(text: '100');
  final _passing = TextEditingController(text: '40');
  ExamSnapshot? _data;
  String? _classId, _sectionId, _subjectId;
  String _kind = 'exam';
  DateTime _date = DateTime.now();
  bool _busy = false, _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void didUpdateWidget(covariant ExamManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId ||
        oldWidget.campusId != widget.campusId ||
        oldWidget.yearId != widget.yearId) {
      _classId = null;
      _sectionId = null;
      _subjectId = null;
      _data = null;
      _refresh();
    }
  }

  @override
  void dispose() {
    _request++;
    _subjectName.dispose();
    _examTitle.dispose();
    _maximum.dispose();
    _passing.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ticket = ++_request;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.repository.snapshot(
        schoolId: widget.schoolId, campusId: widget.campusId,
        yearId: widget.yearId,
      );
      if (!mounted || ticket != _request) return;
      setState(() {
        _data = data;
        if (!data.classes.any((c) => c.id == _classId)) {
          _classId = data.classes.isEmpty ? null : data.classes.first.id;
          _subjectId = null;
          _sectionId = null;
        }
        if (!data.subjects.any((s) =>
            s.id == _subjectId && s.classId == _classId)) {
          _subjectId = null;
        }
        if (!data.classes.any((c) => c.id == _classId &&
            c.sections.any((s) => s.id == _sectionId))) {
          _sectionId = null;
        }
      });
    } catch (error) {
      if (!mounted || ticket != _request) return;
      setState(() => _error = 'Unable to load exams. Check access or network. $error');
    } finally {
      if (mounted && ticket == _request) setState(() => _loading = false);
    }
  }

  String _dateText(DateTime date) => date.toIso8601String().substring(0, 10);

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addSubject() async {
    final data = _data;
    if (_busy || data == null || _classId == null ||
        _subjectName.text.trim().length < 2) {
      _message('Select a class and enter a subject name.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.createSubject(
        schoolId: widget.schoolId, campusId: widget.campusId,
        yearId: data.yearId, classId: _classId!,
        name: _subjectName.text.trim(),
      );
      _subjectName.clear();
      _message('Subject saved in Supabase.');
      await _refresh();
    } catch (error) {
      _message('Unable to add subject: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createExam() async {
    final data = _data;
    final maximum = double.tryParse(_maximum.text.trim());
    final passing = double.tryParse(_passing.text.trim());
    if (_busy || data == null || _classId == null || _subjectId == null ||
        _examTitle.text.trim().length < 2 ||
        maximum == null || !maximum.isFinite || maximum <= 0 ||
        maximum > 10000 || passing == null || !passing.isFinite ||
        passing < 0 || passing > maximum) {
      _message('Select class and subject, title, and valid maximum/passing marks.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.createExam(
        schoolId: widget.schoolId, campusId: widget.campusId,
        yearId: data.yearId, classId: _classId!,
        sectionId: _sectionId, subjectId: _subjectId!,
        kind: _kind, title: _examTitle.text.trim(), date: _dateText(_date),
        maxMarks: maximum, passMarks: passing,
      );
      _examTitle.clear();
      _message('Exam/test created successfully.');
      await _refresh();
    } catch (error) {
      _message('Unable to create assessment: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;
    final selectedClass = data == null ? null : [
      for (final c in data.classes)
        if (c.id == _classId) c,
    ].firstOrNull;
    final subjects = data?.subjects
      .where((s) => s.classId == _classId).toList() ?? <ExamSubject>[];
    final header = Row(children: [
      const Icon(Icons.fact_check_outlined, size: 29),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Examinations & Tests',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800)),
          Text(data == null ? 'Live school records' :
            'Academic year: ${data.yearLabel} • Real Supabase records',
            style: theme.textTheme.bodySmall),
        ],
      )),
      IconButton(
        tooltip: 'Refresh',
        onPressed: _loading ? null : _refresh,
        icon: const Icon(Icons.refresh),
      ),
    ]);
    return ListView(
      key: const Key('exam-management-page'),
      padding: const EdgeInsets.all(16),
      children: [
        header,
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Card(child: Padding(padding: const EdgeInsets.all(14),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))),
        if (!_loading && data != null) ...[
          if (widget.canCreate) Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('1. Subject & Class', style: theme.textTheme.titleMedium),
              const SizedBox(height: 9),
              DropdownButtonFormField<String>(
                key: ValueKey('exam-class-${_classId ?? 'none'}'),
                initialValue: _classId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Class'),
                items: [for (final c in data.classes)
                  DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: _busy ? null : (id) => setState(() {
                  _classId = id; _subjectId = null; _sectionId = null;
                }),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 9, runSpacing: 9,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: 250, child: TextField(
                    key: const Key('exam-new-subject'),
                    controller: _subjectName,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'New subject (e.g. Mathematics)'),
                  )),
                  FilledButton.tonalIcon(
                    key: const Key('exam-add-subject'),
                    onPressed: _busy || _classId == null ? null : _addSubject,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Subject'),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text('2. Schedule a new exam or class test',
                style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('exam-subject-${_classId ?? 'none'}-${_subjectId ?? 'none'}'),
                initialValue: _subjectId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Subject'),
                items: [for (final s in subjects)
                  DropdownMenuItem(value: s.id, child: Text(s.name))],
                onChanged: _busy ? null : (id) =>
                  setState(() => _subjectId = id),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                key: ValueKey('exam-section-${_classId ?? 'none'}-${_sectionId ?? 'all'}'),
                initialValue: _sectionId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Section'),
                items: [
                  const DropdownMenuItem<String?>(value: null,
                    child: Text('All sections in class')),
                  for (final s in selectedClass?.sections ?? <ExamSection>[])
                    DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: _busy ? null : (id) =>
                  setState(() => _sectionId = id),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const Key('exam-kind'),
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Assessment type'),
                items: const [
                  DropdownMenuItem(value: 'exam', child: Text('Examination')),
                  DropdownMenuItem(value: 'test', child: Text('Class Test')),
                  DropdownMenuItem(value: 'quiz', child: Text('Quiz')),
                ],
                onChanged: _busy ? null : (id) {
                  if (id != null) setState(() => _kind = id);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('exam-title'),
                controller: _examTitle,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Title', hintText: 'e.g. Mid Term Mathematics'),
              ),
              Wrap(spacing: 12, runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const Key('exam-pick-date'),
                    icon: const Icon(Icons.event),
                    label: Text('Date: ${_dateText(_date)}'),
                    onPressed: _busy ? null : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100));
                      if (picked != null && mounted) setState(() => _date = picked);
                    },
                  ),
                  SizedBox(width: 150, child: TextField(
                    key: const Key('exam-max-marks'),
                    controller: _maximum,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Total marks'),
                  )),
                  SizedBox(width: 150, child: TextField(
                    key: const Key('exam-pass-marks'),
                    controller: _passing,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Passing marks'),
                  )),
                  FilledButton.icon(
                    key: const Key('exam-create'),
                    onPressed: _busy ? null : _createExam,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_busy ? 'Saving...' : 'Create Exam/Test'),
                  ),
                ],
              ),
            ]),
          )),
          const SizedBox(height: 8),
          Text('Exams & Date Sheet (${data.exams.length})',
            style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          if (data.exams.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(18),
              child: Text('No exams or tests have been scheduled yet.'))),
          for (final exam in data.exams)
            Card(child: ListTile(
              key: Key('exam-record-${exam.id}'),
              leading: Icon(exam.kind == 'exam'
                ? Icons.school_outlined : Icons.fact_check_outlined),
              title: Text(exam.title),
              subtitle: Text(
                '${_className(data, exam.classId)} • '
                '${_subjectNameFor(data, exam.subjectId)} • ${exam.date}\n'
                '${exam.kind.toUpperCase()} • ${exam.maxMarks.toStringAsFixed(2)} marks • '
                '${exam.entered} marks entered'),
              isThreeLine: true,
              trailing: Chip(label: Text(exam.published ? 'Published' : 'Draft')),
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => ExamMarksPage(
                    repository: widget.repository, exam: exam,
                    canUpdate: widget.canUpdate,
                  )));
                if (mounted) _refresh();
              },
            )),
        ],
      ],
    );
  }

  String _className(ExamSnapshot data, String id) =>
    [for(final item in data.classes) if(item.id == id) item.name].firstOrNull
      ?? 'Unknown class';
  String _subjectNameFor(ExamSnapshot data, String id) =>
    [for(final item in data.subjects) if(item.id == id) item.name].firstOrNull
      ?? 'Unknown subject';
}

/// Separate marks editor; published results are locked and read-only.
class ExamMarksPage extends StatefulWidget {
  const ExamMarksPage({
    super.key, required this.repository, required this.exam,
    required this.canUpdate,
  });
  final ExamRepository repository;
  final ExamRecord exam;
  final bool canUpdate;

  @override
  State<ExamMarksPage> createState() => _ExamMarksPageState();
}

class _ExamMarksPageState extends State<ExamMarksPage> {
  ExamRoster? _roster;
  final Map<String, TextEditingController> _scores = {};
  final Map<String, bool> _absences = {};
  String? _error;
  bool _busy = false, _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _scores.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final roster = await widget.repository.roster(widget.exam.id);
      if (!mounted) return;
      for (final controller in _scores.values) {
        controller.dispose();
      }
      _scores.clear();
      _absences.clear();
      for (final student in roster.students) {
        _scores[student.enrollmentId] =
          TextEditingController(text: student.score?.toStringAsFixed(2) ?? '');
        _absences[student.enrollmentId] = student.absent;
      }
      setState(() => _roster = roster);
    } catch (error) {
      if (mounted) setState(() => _error = 'Unable to load student marks: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save(ExamStudentMark student) async {
    if (_busy || _roster?.published == true || !widget.canUpdate) return;
    final absent = _absences[student.enrollmentId] ?? false;
    final input = _scores[student.enrollmentId]!.text.trim();
    final score = absent ? null : double.tryParse(input);
    if (!absent && (score == null || !score.isFinite ||
        score < 0 || score > widget.exam.maxMarks)) {
      _message('Enter marks between 0 and ${widget.exam.maxMarks}, or tick Absent.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.saveMark(
        examId: widget.exam.id, enrollmentId: student.enrollmentId,
        score: score, absent: absent,
      );
      _message('Mark saved.');
      await _load();
    } catch (error) {
      _message('Unable to save mark: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final roster = _roster;
    if (_busy || roster == null || roster.published ||
        roster.students.isEmpty || roster.entered != roster.students.length) {
      _message('Enter marks or Absent for every eligible student first.');
      return;
    }
    final confirmed = await showDialog<bool>(context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Publish exam results?'),
        content: const Text('Published marks become read-only. '
          'Check every student before confirming.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Publish')),
        ],
      ));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.publish(widget.exam.id);
      _message('Results published and locked.');
      await _load();
    } catch (error) {
      _message('Unable to publish: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = _roster;
    final published = roster?.published ?? widget.exam.published;
    return Scaffold(
      appBar: AppBar(title: Text(widget.exam.title)),
      body: Padding(padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Marks & Results', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text('${widget.exam.date} • Total ${widget.exam.maxMarks} • '
            'Pass ${widget.exam.passMarks}'),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (roster != null && !_loading) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 9, runSpacing: 6, children: [
              Chip(label: Text('${roster.entered}/${roster.students.length} entered')),
              Chip(label: Text(published ? 'Published' : 'Draft')),
              if (widget.canUpdate && !published)
                FilledButton.icon(
                  key: const Key('exam-publish'),
                  onPressed: _busy ? null : _publish,
                  icon: const Icon(Icons.publish_outlined),
                  label: const Text('Publish Results'),
                ),
            ]),
            const SizedBox(height: 10),
            Expanded(child: roster.students.isEmpty
              ? const Center(child: Text('No eligible students in this class/section.'))
              : ListView.builder(
                  itemCount: roster.students.length,
                  itemBuilder: (context, index) {
                    final student = roster.students[index];
                    final absent = _absences[student.enrollmentId] ?? false;
                    final locked = published || !widget.canUpdate || _busy;
                    final status = !student.entered ? 'Pending' :
                      student.absent ? 'Absent' :
                      (student.score ?? -1) >= widget.exam.passMarks
                        ? 'Pass' : 'Fail';
                    return Card(child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(student.name,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('Reg: ${student.registrationNo} • '
                            'Roll: ${student.rollNo ?? '—'} • $status'),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(width: 130, child: TextField(
                                key: Key('exam-score-${student.enrollmentId}'),
                                controller: _scores[student.enrollmentId],
                                enabled: !locked && !absent,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Marks'),
                              )),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Checkbox(
                                  value: absent,
                                  onChanged: locked ? null : (value) =>
                                    setState(() => _absences[student.enrollmentId] =
                                      value ?? false),
                                ),
                                const Text('Absent'),
                              ]),
                              if (!published && widget.canUpdate)
                                OutlinedButton(
                                  key: Key('exam-save-${student.enrollmentId}'),
                                  onPressed: locked ? null : () => _save(student),
                                  child: const Text('Save'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ));
                  },
                )),
          ],
        ]),
      ),
    );
  }
}
