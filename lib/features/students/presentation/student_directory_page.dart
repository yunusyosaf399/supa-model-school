import 'package:flutter/material.dart';

import '../models/student_directory.dart';
import '../data/student_directory_repository.dart';
import '../../auth/data/owner_auth_gateway.dart';

/// Read-only student directory preview.
///
/// This page accepts only an authorized projection. In real use the server
/// and/or the assigned-campus local database must enforce access BEFORE
/// giving records to this widget. UI filters are NOT an authorization layer.
class StudentDirectoryPage extends StatefulWidget {
  const StudentDirectoryPage({
    super.key,
    required this.onNewAdmission,
    this.projection = StudentDirectoryDemo.projection,
    this.owner,
    this.selectedCampusId,
    this.repository,
  });

  final VoidCallback onNewAdmission;
  final StudentDirectoryProjection projection;
  final OwnerAccess? owner;
  final String? selectedCampusId;
  final StudentDirectoryRepository? repository;

  @override
  State<StudentDirectoryPage> createState() => _StudentDirectoryPageState();
}

class _StudentDirectoryPageState extends State<StudentDirectoryPage> {
  final TextEditingController _search = TextEditingController();
  String _campusId = 'all';
  String _classId = 'all';
  String _status = 'all';
  StudentDirectoryProjection _projection = StudentDirectoryDemo.projection;
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _projection = widget.owner == null ? widget.projection : _empty();
    if (widget.owner != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  StudentDirectoryProjection _empty() => const StudentDirectoryProjection(
    authorizedCampusIds: <String>{},
    records: <StudentSummary>[],
  );

  @override
  void didUpdateWidget(covariant StudentDirectoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner?.userId != widget.owner?.userId ||
        oldWidget.selectedCampusId != widget.selectedCampusId ||
        oldWidget.repository != widget.repository) {
      ++_request;
      _projection = widget.owner == null ? widget.projection : _empty();
      _campusId = 'all';
      _classId = 'all';
      _status = 'all';
      if (widget.owner != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refresh();
        });
      }
    }
  }

  Future<void> _refresh() async {
    final owner = widget.owner;
    if (owner == null) return;
    final repo = widget.repository;
    final campus = widget.selectedCampusId != null &&
            owner.campuses.any((c) => c.id == widget.selectedCampusId)
        ? widget.selectedCampusId
        : (owner.campuses.isEmpty ? null : owner.campuses.first.id);
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _projection = _empty();
    });
    if (repo == null || campus == null) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = 'Student directory is not configured.';
        });
      }
      return;
    }
    try {
      final value = await repo.load(schoolId: owner.schoolId, campusId: campus);
      if (!mounted || request != _request) return;
      setState(() {
        _projection = value;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load authorized students. Check network and permissions.';
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  StudentDirectoryFilters get _filters => StudentDirectoryFilters(
        searchText: _search.text,
        campusId: _campusId == 'all' ? null : _campusId,
        classId: _classId == 'all' ? null : _classId,
        status: _status == 'all'
            ? null
            : StudentStatus.values.byName(_status),
      );

  void _clearFilters() {
    _search.clear();
    setState(() {
      _campusId = 'all';
      _classId = 'all';
      _status = 'all';
    });
  }

  void _openPreview(StudentSummary student) {
    // The record comes from the already-scoped visible list, never from a
    // global/unfiltered lookup by UUID.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudentProfilePreviewPage(
          student: student,
          isLive: widget.owner != null,
          onUpdate: widget.owner == null || widget.repository == null
              ? null : (name, status) async {
                  await widget.repository!.updateProfile(
                    schoolId: widget.owner!.schoolId,
                    campusId: student.campusId,
                    student: student,
                    name: name,
                    status: status,
                  );
                  if (mounted) await _refresh();
                },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authorized = _projection.authorizedRecords;
    final visible = _projection.filter(_filters);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        return ListView(
          key: const Key('student-directory'),
          padding: EdgeInsets.all(wide ? 24 : 12),
          children: [
            _heading(wide),
            if (_loading) const LinearProgressIndicator(key: Key('student-loading')),
            if (_error != null) ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(_error!),
              trailing: TextButton(onPressed: _refresh, child: const Text('Retry')),
            ),
            const SizedBox(height: 12),
            if (widget.owner == null) Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'DEMO MODE — fictional students only. '
                        'No school database, authentication or offline sync '
                        'is connected. Filters are a UI preview.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _filterPanel(wide),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${visible.length} of ${authorized.length} students',
                    key: const Key('student-result-count'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('clear-student-filters'),
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Clear filters'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              _emptyState()
            else if (wide)
              _desktopTable(visible)
            else
              ...visible.map(_mobileCard),
          ],
        );
      },
    );
  }

  Widget _heading(bool wide) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Student Directory',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(widget.owner == null ? 'Campus-scoped list • synthetic preview records' : 'Live campus-scoped school records'),
      ],
    );
    final addButton = FilledButton.icon(
      key: const Key('open-admission-wizard'),
      onPressed: widget.onNewAdmission,
      icon: const Icon(Icons.person_add_alt_1_outlined),
      label: Text(widget.owner == null ? 'New admission (preview)' : 'New admission'),
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [title, const SizedBox(height: 12), addButton],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 12),
        addButton,
      ],
    );
  }

  Widget _filterPanel(bool wide) {
    final campuses = _projection.campuses;
    final classOptions = _projection.classesForCampus(
        _campusId == 'all' ? null : _campusId);
    final campusField = _dropdown(
      key: ValueKey('campus-field-$_campusId'),
      label: 'Campus',
      selected: _campusId,
      values: {'all': 'All authorized campuses', ...campuses},
      changed: (v) => setState(() {
        _campusId = v;
        // Class choices are scoped to the selected campus.
        _classId = 'all';
      }),
    );
    final classField = _dropdown(
      key: ValueKey('class-field-$_campusId-$_classId'),
      label: 'Class',
      selected: _classId,
      values: {'all': 'All classes', ...classOptions},
      changed: (v) => setState(() => _classId = v),
    );
    final statusField = _dropdown(
      key: ValueKey('status-field-$_status'),
      label: 'Status',
      selected: _status,
      values: {
        'all': 'All statuses',
        for (final status in StudentStatus.values)
          status.name: status.label,
      },
      changed: (v) => setState(() => _status = v),
    );
    final searchField = TextField(
      key: const Key('student-directory-search'),
      controller: _search,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'Search name or registration number',
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _search.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close),
              ),
      ),
    );
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: wide
            ? Column(
                children: [
                  searchField,
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: campusField),
                      const SizedBox(width: 12),
                      Expanded(child: classField),
                      const SizedBox(width: 12),
                      Expanded(child: statusField),
                    ],
                  ),
                ],
              )
            : Column(
                children: [
                  searchField,
                  const SizedBox(height: 12),
                  campusField,
                  const SizedBox(height: 12),
                  classField,
                  const SizedBox(height: 12),
                  statusField,
                ],
              ),
      ),
    );
  }

  Widget _dropdown({
    required Key key,
    required String label,
    required String selected,
    required Map<String, String> values,
    required ValueChanged<String> changed,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final item in values.entries)
          DropdownMenuItem<String>(
            value: item.key,
            child: Text(item.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) changed(v);
      },
    );
  }

  Widget _emptyState() => Card.outlined(
        key: const Key('student-empty-results'),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Column(
            children: [
              Icon(Icons.search_off_outlined, size: 44),
              SizedBox(height: 12),
              Text('No students match these filters.'),
              SizedBox(height: 6),
              Text('Try clearing the search or selecting another class.'),
            ],
          ),
        ),
      );

  Widget _desktopTable(List<StudentSummary> students) {
    return Card.outlined(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          key: const Key('student-desktop-table'),
          columns: const [
            DataColumn(label: Text('Student')),
            DataColumn(label: Text('Registration')),
            DataColumn(label: Text('Campus')),
            DataColumn(label: Text('Class / Section')),
            DataColumn(label: Text('Academic year')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Profile')),
          ],
          rows: [
            for (final student in students)
              DataRow(
                cells: [
                  DataCell(Text(student.fullName)),
                  DataCell(Text(student.registrationNo)),
                  DataCell(Text(student.campusName)),
                  DataCell(Text(
                      '${student.className} – ${student.sectionName}')),
                  DataCell(Text(student.academicYear)),
                  DataCell(_statusChip(student.status)),
                  DataCell(
                    TextButton(
                      key: Key('view-student-${student.id}'),
                      onPressed: () => _openPreview(student),
                      child: const Text('View'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _mobileCard(StudentSummary student) {
    return Card.outlined(
      key: Key('student-card-${student.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ListTile(
          title: Text(student.fullName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${student.registrationNo} • '
                  '${student.className}-${student.sectionName}'),
              Text('${student.campusName} • ${student.academicYear}'),
              Align(
                alignment: Alignment.centerLeft,
                child: _statusChip(student.status),
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openPreview(student),
        ),
      ),
    );
  }

  Widget _statusChip(StudentStatus status) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text(status.label),
      );
}

/// A live Owner-editable student profile. Other modules remain unavailable
/// until their own secured workflows are implemented.
class StudentProfilePreviewPage extends StatelessWidget {
  const StudentProfilePreviewPage({
    super.key, required this.student, this.isLive = false, this.onUpdate,
  });
  final StudentSummary student;
  final bool isLive;
  final Future<void> Function(String, StudentStatus)? onUpdate;

  Future<void> _editStudent(BuildContext context) async {
    final save = onUpdate;
    if (save == null) return;
    final name = TextEditingController(text: student.fullName);
    var status = student.status == StudentStatus.active
        ? StudentStatus.active : StudentStatus.inactive;
    var saving = false;
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Edit Student'),
          content: SizedBox(width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                key: const Key('edit-student-name'),
                controller: name,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<StudentStatus>(
                key: const Key('edit-student-status'),
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: StudentStatus.active,
                    child: Text('Active')),
                  DropdownMenuItem(value: StudentStatus.inactive,
                    child: Text('Inactive')),
                ],
                onChanged: saving ? null : (value) {
                  if (value != null) refresh(() => status = value);
                },
              ),
              if (saving) const LinearProgressIndicator(),
              if (errorText != null)
                Text(errorText!, style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error)),
            ]),
          ),
          actions: [
            TextButton(onPressed: saving ? null :
              () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
            FilledButton(
              key: const Key('save-student-profile'),
              onPressed: saving ? null : () async {
                refresh(() { saving = true; errorText = null; });
                try {
                  await save(name.text.trim(), status);
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (context.mounted) Navigator.pop(context);
                } catch (_) {
                  if (dialogContext.mounted) refresh(() {
                    errorText = 'Update not saved. Check network, school '
                      'permissions and record revision.';
                    saving = false;
                  });
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
    // Text field is no longer referenced after the modal route is removed.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLive
        ? 'Student Profile' : 'Student Profile (preview)')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(isLive
                    ? (onUpdate == null
                      ? 'Live student summary. Detailed modules are not yet connected.'
                      : 'Live student record. Update name and active status. '
                        'Guardian details, fees and attendance will be '
                        'connected through their own authorized workflows.')
                    : 'FICTIONAL PREVIEW — not a real pupil, not a saved record. '
                      'Guardian documents, fee balance and attendance are unavailable '
                      'until authorized backend integration.'),
                ),
              ),
              const SizedBox(height: 12),
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (onUpdate != null) Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          key: const Key('edit-student-profile'),
                          onPressed: () => _editStudent(context),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit Student'),
                        ),
                      ),
                      Text(student.fullName,
                        key: const Key('student-preview-name'),
                        style: Theme.of(context).textTheme.headlineSmall),
                      const Divider(height: 24),
                      _field('Registration number', student.registrationNo),
                      _field('Campus', student.campusName),
                      _field('Academic year', student.academicYear),
                      _field('Class', student.className),
                      _field('Section', student.sectionName),
                      _field('Status', student.status.label),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      SizedBox(width: 170,
        child: Text(label, style: const TextStyle(
          fontWeight: FontWeight.w600))),
      Expanded(child: Text(value)),
    ]),
  );
}
