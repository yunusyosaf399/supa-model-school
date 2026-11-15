import 'package:flutter/material.dart';

import '../models/admission_draft.dart';

/// First-stage admissions UI for Windows and Android.
///
/// This screen intentionally does NOT call Supabase, upload identity documents
/// or store data in SQLite. Until DB01/DB02 migrations, permissions, and offline
/// sync pass, any data entered here lives in memory and is discarded on exit.
class AdmissionWizardPage extends StatefulWidget {
  const AdmissionWizardPage({super.key});

  @override
  State<AdmissionWizardPage> createState() => _AdmissionWizardPageState();
}

class _AdmissionWizardPageState extends State<AdmissionWizardPage> {
  final AdmissionDraft _draft = AdmissionDraft();
  int _step = 0;
  int _nextGuardianId = 2;
  String? _error;
  bool _allowExit = false;

  static const _sampleCampuses = <String, String>{
    'sample-campus-a': 'Campus A (sample)',
    'sample-campus-b': 'Campus B (sample)',
  };
  static const _sampleYears = <String, String>{
    'sample-year-2026': '2026–2027 (sample)',
    'sample-year-2027': '2027–2028 (sample)',
  };
  static const _sampleClasses = <String, String>{
    'grade-1': 'Grade 1 (sample)',
    'grade-5': 'Grade 5 (sample)',
    'grade-10': 'Grade 10 (sample)',
  };
  static const _sampleSections = <String, String>{
    'section-a': 'Section A (sample)',
    'section-b': 'Section B (sample)',
  };

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Select date';
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
  }

  Future<void> _chooseBirthDate() async {
    final today = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _draft.dateOfBirth ?? DateTime(2015, 1, 1),
      firstDate: DateTime(1980),
      lastDate: today,
      helpText: 'Student date of birth',
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _draft.dateOfBirth = chosen;
      _error = null;
    });
  }

  Future<void> _chooseDocumentDeadline() async {
    final today = DateTime.now();
    final currentDay = DateTime(today.year, today.month, today.day);
    final chosen = await showDatePicker(
      context: context,
      initialDate: _draft.missingDocumentsDueOn ??
          currentDay.add(const Duration(days: 60)),
      firstDate: currentDay,
      lastDate: DateTime(today.year + 3, today.month, today.day),
      helpText: 'Deadline for outstanding certificates',
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _draft.missingDocumentsDueOn = chosen;
      _error = null;
    });
  }

  void _next() {
    final error = _draft.validateStep(AdmissionStep.values[_step]);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_step < AdmissionStep.values.length - 1) {
      setState(() {
        _step += 1;
        _error = null;
      });
    }
  }

  void _previous() {
    if (_step == 0) return;
    setState(() {
      _step -= 1;
      _error = null;
    });
  }

  Future<void> _confirmExit() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard admission preview?'),
        content: const Text(
          'This form is not connected to the school database. '
          'The information entered will be lost when you leave.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continue editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard preview'),
          ),
        ],
      ),
    );
    if (!mounted || discard != true) return;
    setState(() => _allowExit = true);
    // PopScope must rebuild with canPop=true before popping the route.
    // Otherwise a second interception can reopen the confirmation dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Student Admission'),
          leading: IconButton(
            tooltip: 'Leave admission preview',
            onPressed: _confirmExit,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('Preview • Not saved')),
            ),
          ],
        ),
        body: SafeArea(
          child: wide
              ? Row(
                  children: [
                    SizedBox(width: 240, child: _stepNavigation(wide: true)),
                    const VerticalDivider(width: 1),
                    Expanded(child: _formScroll()),
                  ],
                )
              : Column(
                  children: [
                    _stepNavigation(wide: false),
                    const Divider(height: 1),
                    Expanded(child: _formScroll()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _stepNavigation({required bool wide}) {
    final items = List.generate(AdmissionStep.values.length, (i) {
      final step = AdmissionStep.values[i];
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: wide
            ? ListTile(
                key: Key('step-tab-$i'),
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('${i + 1}'),
                ),
                title: Text(step.label),
                selected: _step == i,
                enabled: i <= _step,
                onTap: i > _step
                    ? null
                    : () => setState(() {
                          _step = i;
                          _error = null;
                        }),
              )
            : ChoiceChip(
                key: Key('step-chip-$i'),
                label: Text('${i + 1}. ${step.label}'),
                selected: _step == i,
                onSelected: i > _step
                    ? null
                    : (_) => setState(() {
                          _step = i;
                          _error = null;
                        }),
              ),
      );
    });

    if (wide) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Admission stages',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...items,
        ],
      );
    }

    return Column(
      children: [
        LinearProgressIndicator(
          value: (_step + 1) / AdmissionStep.values.length,
          minHeight: 3,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(8),
          child: Row(children: items),
        ),
      ],
    );
  }

  Widget _formScroll() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                          'UI demonstration only. Sample campus/class choices '
                          'are not real school records. No information is saved, '
                          'uploaded or submitted.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${_step + 1}. ${AdmissionStep.values[_step].label}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (_error != null) ...[
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      key: const Key('admission-validation-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: _stepContent(),
                ),
              ),
              const SizedBox(height: 16),
              _actions(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepContent() => switch (AdmissionStep.values[_step]) {
        AdmissionStep.student => _studentFields(),
        AdmissionStep.guardians => _guardianFields(),
        AdmissionStep.academic => _academicFields(),
        AdmissionStep.documents => _documentFields(),
        AdmissionStep.fees => _feeFields(),
        AdmissionStep.review => _reviewFields(),
      };

  Widget _studentFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Student identity', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('student-name'),
          initialValue: _draft.studentName,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Student full name *',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => _draft.studentName = value,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('date-of-birth'),
          onPressed: _chooseBirthDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('Date of birth *: ${_dateLabel(_draft.dateOfBirth)}'),
        ),
        const SizedBox(height: 16),
        _choice(
          label: 'Gender (optional)',
          current: _draft.gender,
          choices: const {
            'unspecified': 'Prefer not to say',
            'male': 'Male',
            'female': 'Female',
            'other': 'Other',
          },
          onChanged: (value) => setState(() => _draft.gender = value!),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('previous-school'),
          initialValue: _draft.previousSchool,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Previous school (if applicable)',
            helperText: 'Determines whether a transfer/leaving certificate is required.',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _draft.previousSchool = value,
        ),
      ],
    );
  }

  Widget _guardianFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Parent or guardian contacts',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Exactly one primary guardian is required for submission. '
            'A guardian may later be linked to several siblings.'),
        const SizedBox(height: 14),
        for (var i = 0; i < _draft.guardians.length; i++)
          _guardianCard(i, _draft.guardians[i]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: _draft.guardians.length >= 8
                ? null
                : () => setState(() => _draft.guardians.add(
                      GuardianDraft(localId: _nextGuardianId++),
                    )),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add another guardian'),
          ),
        ),
      ],
    );
  }

  Widget _guardianCard(int index, GuardianDraft guardian) {
    return Card.outlined(
      key: ValueKey('guardian-${guardian.localId}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Guardian ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                if (_draft.guardians.length > 1)
                  IconButton(
                    key: Key('remove-guardian-${guardian.localId}'),
                    tooltip: 'Remove guardian',
                    onPressed: () => setState(() => _draft.guardians.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            TextFormField(
              key: Key('guardian-name-${guardian.localId}'),
              initialValue: guardian.fullName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name *',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => guardian.fullName = v,
            ),
            const SizedBox(height: 12),
            _choice(
              label: 'Relationship',
              current: guardian.relationship,
              choices: const {
                'father': 'Father',
                'mother': 'Mother',
                'guardian': 'Guardian',
                'other': 'Other',
              },
              onChanged: (v) => setState(() => guardian.relationship = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: Key('guardian-phone-${guardian.localId}'),
              initialValue: guardian.phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: guardian.isPrimary
                    ? 'Primary guardian phone *'
                    : 'Phone number',
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => guardian.phone = v,
            ),
            CheckboxListTile(
              title: const Text('Primary contact'),
              contentPadding: EdgeInsets.zero,
              value: guardian.isPrimary,
              onChanged: (selected) => setState(() {
                if (selected ?? false) {
                  for (final g in _draft.guardians) {
                    g.isPrimary = identical(g, guardian);
                  }
                } else {
                  guardian.isPrimary = false;
                }
              }),
            ),
            CheckboxListTile(
              title: const Text('Legal guardian'),
              contentPadding: EdgeInsets.zero,
              value: guardian.isLegalGuardian,
              onChanged: (selected) =>
                  setState(() => guardian.isLegalGuardian = selected ?? false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _academicFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Class and campus allocation',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Only sample choices are available until the school '
            'database and campus permissions are connected.'),
        const SizedBox(height: 16),
        _choice(
          label: 'Campus *',
          current: _draft.campusId,
          choices: _sampleCampuses,
          onChanged: (value) => setState(() {
            _draft.campusId = value;
            _draft.classId = null;
            _draft.sectionId = null;
          }),
        ),
        const SizedBox(height: 16),
        _choice(
          label: 'Academic year *',
          current: _draft.academicYearId,
          choices: _sampleYears,
          onChanged: (v) => setState(() => _draft.academicYearId = v),
        ),
        const SizedBox(height: 16),
        _choice(
          key: ValueKey('class-choice-${_draft.campusId}'),
          label: 'Class *',
          current: _draft.classId,
          choices: _sampleClasses,
          onChanged: (v) => setState(() {
            _draft.classId = v;
            _draft.sectionId = null;
          }),
        ),
        const SizedBox(height: 16),
        _choice(
          key: ValueKey('section-choice-${_draft.classId}'),
          label: 'Section (optional)',
          current: _draft.sectionId,
          choices: _sampleSections,
          onChanged: (v) => setState(() => _draft.sectionId = v),
        ),
        const SizedBox(height: 12),
        const Text('The permanent registration number is generated by the '
            'trusted server after approval; it is not entered manually.'),
      ],
    );
  }

  Widget _documentFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Required certificates',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Files cannot be uploaded or verified in this preview. '
            'All required certificates must be treated as outstanding.'),
        const SizedBox(height: 12),
        for (final name in _draft.requiredDocumentNames)
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(name),
            subtitle: const Text('Not uploaded or verified'),
            trailing: const Chip(label: Text('Outstanding')),
          ),
        const Divider(height: 24),
        const Text('Conditional documentation',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('School policy allows conditional admission with a deadline. '
            'A late document does not automatically cancel enrollment.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('document-deadline'),
          onPressed: _chooseDocumentDeadline,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text('Document deadline *: '
              '${_dateLabel(_draft.missingDocumentsDueOn)}'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('conditional-reason'),
          initialValue: _draft.conditionalReason,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason for conditional admission *',
            border: OutlineInputBorder(),
            helperText: 'Saved in the server audit trail when the backend is ready.',
          ),
          onChanged: (v) => _draft.conditionalReason = v,
        ),
        const SizedBox(height: 10),
        const Text('Verification and deadline extensions will require '
            'authorized server operations and separate audit records.'),
      ],
    );
  }

  Widget _feeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Fee preferences (no financial posting)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('Tuition and other fee amounts will come from approved '
            'campus/class plans. This screen does not collect money.'),
        const SizedBox(height: 16),
        _choice(
          label: 'Admission fee status',
          current: _draft.admissionFeeStatus,
          choices: const {
            'not_recorded': 'Not recorded / skip',
            'unpaid': 'Unpaid',
            'paid': 'Paid (verification required)',
          },
          onChanged: (v) => setState(() => _draft.admissionFeeStatus = v!),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Uses school transport'),
          value: _draft.usesTransport,
          onChanged: (v) => setState(() => _draft.usesTransport = v),
        ),
        if (_draft.usesTransport) ...[
          TextFormField(
            initialValue: _draft.transportNotes,
            decoration: const InputDecoration(
              labelText: 'Transport notes',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _draft.transportNotes = v,
          ),
          const SizedBox(height: 12),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Request a fee discount'),
          subtitle: const Text('Requires an authorized discount rule later'),
          value: _draft.requestsDiscount,
          onChanged: (v) => setState(() => _draft.requestsDiscount = v),
        ),
        if (_draft.requestsDiscount)
          TextFormField(
            initialValue: _draft.discountNotes,
            decoration: const InputDecoration(
              labelText: 'Discount request notes',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _draft.discountNotes = v,
          ),
        const SizedBox(height: 12),
        const Text('Paid/unpaid is informational in this preview. '
            'No payment receipt or school ledger entry is created.'),
      ],
    );
  }

  Widget _reviewFields() {
    final warning = _draft.validateStep(AdmissionStep.review);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Review admission information',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (warning != null) ...[
          Text('Additional information required: $warning',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
        ],
        _summaryRow('Student', _draft.studentName),
        _summaryRow('Birth date', _dateLabel(_draft.dateOfBirth)),
        _summaryRow('Previous school',
            _draft.previousSchool.trim().isEmpty
                ? 'Not applicable'
                : _draft.previousSchool),
        _summaryRow('Guardians', _draft.guardians
            .map((g) => '${g.fullName} (${g.relationship}'
                '${g.isPrimary ? ', primary' : ''})')
            .join(', ')),
        _summaryRow('Campus', _sampleCampuses[_draft.campusId] ?? 'Not selected'),
        _summaryRow('Year', _sampleYears[_draft.academicYearId] ?? 'Not selected'),
        _summaryRow('Class', _sampleClasses[_draft.classId] ?? 'Not selected'),
        _summaryRow('Section',
            _sampleSections[_draft.sectionId] ?? 'Unassigned'),
        _summaryRow('Document state', 'Conditional — awaiting verification'),
        _summaryRow('Document deadline', _dateLabel(_draft.missingDocumentsDueOn)),
        _summaryRow('Admission fee', _draft.admissionFeeStatus),
        _summaryRow('Transport', _draft.usesTransport ? 'Requested' : 'Not requested'),
        const SizedBox(height: 18),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('The application has NOT been saved or forwarded for '
                'approval. Connect Supabase Auth, school lookup, private document '
                'Storage and the audited admission endpoint before enabling submission.'),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 155,
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value.isEmpty ? 'Not provided' : value)),
          ],
        ),
      );

  Widget _choice({
    Key? key,
    required String label,
    required String? current,
    required Map<String, String> choices,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final entry in choices.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: onChanged,
    );
  }

  Widget _actions() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _step == 0 ? null : _previous,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Back'),
        ),
        const Spacer(),
        if (_step < AdmissionStep.values.length - 1)
          FilledButton.icon(
            key: const Key('wizard-next'),
            onPressed: _next,
            icon: const Icon(Icons.chevron_right),
            iconAlignment: IconAlignment.end,
            label: const Text('Next'),
          )
        else
          const FilledButton.icon(
            key: Key('wizard-submit-disabled'),
            onPressed: null,
            icon: Icon(Icons.lock_outline),
            label: Text('Submit unavailable'),
          ),
      ],
    );
  }
}
