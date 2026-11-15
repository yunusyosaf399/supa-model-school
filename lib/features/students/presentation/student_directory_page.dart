import 'package:flutter/material.dart';

import '../models/student_directory.dart';

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
  });

  final VoidCallback onNewAdmission;
  final StudentDirectoryProjection projection;

  @override
  State<StudentDirectoryPage> createState() => _StudentDirectoryPageState();
}

class _StudentDirectoryPageState extends State<StudentDirectoryPage> {
  final TextEditingController _search = TextEditingController();
  String _campusId = 'all';
  String _classId = 'all';
  String _status = 'all';

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
        builder: (_) => StudentProfilePreviewPage(student: student),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authorized = widget.projection.authorizedRecords;
    final visible = widget.projection.filter(_filters);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        return ListView(
          key: const Key('student-directory'),
          padding: EdgeInsets.all(wide ? 24 : 12),
          children: [
            _heading(wide),
            const SizedBox(height: 12),
            Card(
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
                    '${visible.length} of ${authorized.length} sample students',
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
        const Text('Campus-scoped list • synthetic preview records'),
      ],
    );
    final addButton = FilledButton.icon(
      key: const Key('open-admission-wizard'),
      onPressed: widget.onNewAdmission,
      icon: const Icon(Icons.person_add_alt_1_outlined),
      label: const Text('New admission (preview)'),
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
    final campuses = widget.projection.campuses;
    final classOptions = widget.projection.classesForCampus(
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
              Text('No sample students match these filters.'),
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

/// A deliberately read-only profile shell. No guardians, finances, documents,
/// history or sensitive PII are loaded or claimed from a real school.
class StudentProfilePreviewPage extends StatelessWidget {
  const StudentProfilePreviewPage({super.key, required this.student});

  final StudentSummary student;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Profile (preview)')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'FICTIONAL PREVIEW — not a real pupil, not a saved record. '
                    'Guardian documents, fee balance and attendance are '
                    'unavailable until authorized backend integration.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
        child: Row(
          children: [
            SizedBox(
              width: 170,
              child: Text(label, style: const TextStyle(
                fontWeight: FontWeight.w600,
              )),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
