import 'package:flutter/material.dart';

import '../../auth/data/owner_auth_gateway.dart';
import '../data/academic_structure_repository.dart';

/// Windows / Android responsive Owner academic-structure manager.
/// Real records only: no sample classes are mixed with live school records.
class AcademicStructurePage extends StatefulWidget {
  const AcademicStructurePage({
    super.key,
    required this.owner,
    required this.repository,
  });

  final OwnerAccess owner;
  final AcademicStructureRepository repository;

  @override
  State<AcademicStructurePage> createState() =>
      _AcademicStructurePageState();
}

class _AcademicStructurePageState extends State<AcademicStructurePage> {
  final _formKey = GlobalKey<FormState>();
  final _className = TextEditingController();
  final _sections = TextEditingController(text: 'A');
  final _sortOrder = TextEditingController(text: '0');
  List<SchoolClassRecord> _classes = const [];
  late String _campusId;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _campusId = widget.owner.campuses.first.id;
    if (_ready) _refresh();
  }

  bool get _ready =>
      widget.owner.setupComplete && widget.owner.activeYearId != null;

  @override
  void dispose() {
    _className.dispose();
    _sections.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!_ready) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.repository.listClasses(
        campusId: _campusId,
        academicYearId: widget.owner.activeYearId!,
      );
      if (!mounted) return;
      setState(() => _classes = results);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _classes = const [];
        _error = 'Unable to load classes. Check network and Owner access.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateSections(String? value) {
    final names = (value ?? '').split(',').map((s) => s.trim()).toList();
    if (names.length < 1 || names.length > 12 ||
        names.any((s) => s.isEmpty || s.length > 50)) {
      return 'Enter 1–12 sections separated by commas (1–50 characters each).';
    }
    final unique = names.map((s) => s.toLowerCase()).toSet();
    if (unique.length != names.length) {
      return 'Section names must be unique, ignoring case.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_ready || _saving || !_formKey.currentState!.validate()) return;
    final names = _sections.text.split(',').map((s) => s.trim()).toList();
    final sort = int.tryParse(_sortOrder.text.trim());
    if (sort == null) return;

    setState(() => _saving = true);
    try {
      await widget.repository.createClassWithSections(
        schoolId: widget.owner.schoolId,
        campusId: _campusId,
        academicYearId: widget.owner.activeYearId!,
        className: _className.text.trim(),
        sortOrder: sort,
        sectionNames: names,
      );
      if (!mounted) return;
      _className.clear();
      _sections.text = 'A';
      _sortOrder.text = '0';
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Class and sections created successfully.'),
      ));
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to save class. Check for duplicate names, '
            'school setup status, network connection or permissions.'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('academic-structure-page'),
      padding: const EdgeInsets.all(18),
      children: [
        Text('Classes & Sections',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            )),
        const SizedBox(height: 6),
        Text('School: ${widget.owner.schoolName}'),
        const SizedBox(height: 8),
        if (!_ready)
          const Card(child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('Complete the Owner school setup and create '
                'the active academic year before adding classes.'),
          ))
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Academic year: ${widget.owner.activeYearLabel}',
                    style: theme.textTheme.titleMedium),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const Key('academic-campus'),
                    isExpanded: true,
                    initialValue: _campusId,
                    decoration: const InputDecoration(labelText: 'Campus'),
                    items: [
                      for (final campus in widget.owner.campuses)
                        DropdownMenuItem(
                          value: campus.id,
                          child: Text(campus.name),
                        ),
                    ],
                    onChanged: _saving ? null : (id) {
                      if (id == null) return;
                      setState(() {
                        _campusId = id;
                        _classes = const [];
                      });
                      _refresh();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildCreateCard(theme),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text('Existing Classes',
                        style: theme.textTheme.titleLarge),
                    ),
                    IconButton(
                      key: const Key('refresh-classes'),
                      tooltip: 'Refresh classes',
                      onPressed: _loading ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ]),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(
                      color: theme.colorScheme.error)),
                  ],
                  if (!_loading && _error == null && _classes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No classes created for this campus '
                          'and academic year yet.'),
                    ),
                  for (final record in _classes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: ExpansionTile(
                        key: Key('class-${record.id}'),
                        leading: const Icon(Icons.school_outlined),
                        title: Text(record.name),
                        subtitle: Text('${record.sections.length} sections'
                            ' • Order ${record.sortOrder}'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  for (final section in record.sections)
                                    Chip(label: Text(section.name)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCreateCard(ThemeData theme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add Class & Sections', style: theme.textTheme.titleLarge),
            const SizedBox(height: 5),
            const Text('Example: Grade 1 with sections A, B, C. '
                'Create each class only once per campus and academic year.'),
            const SizedBox(height: 15),
            TextFormField(
              key: const Key('academic-class-name'),
              controller: _className,
              decoration: const InputDecoration(
                labelText: 'Class name',
                hintText: 'e.g. Grade 1',
              ),
              validator: (s) => s == null || s.trim().isEmpty ||
                  s.trim().length > 100
                    ? 'Enter a class name (1–100 characters).' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('academic-section-names'),
              controller: _sections,
              decoration: const InputDecoration(
                labelText: 'Section names (comma separated)',
                hintText: 'A, B, C',
              ),
              validator: _validateSections,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('academic-sort-order'),
              controller: _sortOrder,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Display order',
                hintText: '0',
              ),
              validator: (s) {
                final n = int.tryParse(s?.trim() ?? '');
                return n == null || n < 0 || n > 1000
                    ? 'Enter a number from 0 to 1000.' : null;
              },
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('academic-create-class'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.add),
              label: Text(_saving ? 'Creating...' : 'Create Class'),
            ),
            const SizedBox(height: 9),
            Text('Changes are saved only online after Owner authorization. '
                'This screen does not create admissions or record student data.',
              style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}
