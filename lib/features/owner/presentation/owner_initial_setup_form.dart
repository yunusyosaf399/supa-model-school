import 'package:flutter/material.dart';

import '../../auth/data/owner_auth_gateway.dart';

/// One-time initial configuration. The backend is the source of truth;
/// this form never changes database tables directly.
class OwnerInitialSetupForm extends StatefulWidget {
  const OwnerInitialSetupForm({
    super.key,
    required this.owner,
    required this.onSave,
    required this.onSaved,
  });

  final OwnerAccess owner;
  final Future<OwnerAccess> Function(OwnerInitialSetupRequest) onSave;
  final ValueChanged<OwnerAccess> onSaved;

  @override
  State<OwnerInitialSetupForm> createState() => _OwnerInitialSetupFormState();
}

class _OwnerInitialSetupFormState extends State<OwnerInitialSetupForm> {
  static const currencies = <String>[
    'PKR', 'SAR', 'AED', 'USD', 'EUR', 'GBP', 'INR', 'BDT',
    'NGN', 'GHS', 'KES', 'CAD', 'AUD', 'OTHER'
  ];
  static const timezones = <String>[
    'Asia/Karachi', 'Asia/Riyadh', 'Asia/Dubai', 'Europe/Berlin',
    'Europe/Vienna', 'Europe/London', 'Africa/Lagos', 'Africa/Accra',
    'America/New_York', 'UTC', 'OTHER'
  ];

  final _key = GlobalKey<FormState>();
  late final TextEditingController _school;
  late final TextEditingController _campus;
  final _customCurrency = TextEditingController();
  final _customTimezone = TextEditingController();
  final _year = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();

  String? _currency;
  String? _timezone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _school = TextEditingController(text: widget.owner.schoolName);
    _campus = TextEditingController(
      text: widget.owner.campuses.first.name.contains('Setup Pending')
          ? '' : widget.owner.campuses.first.name,
    );
    final c = widget.owner.currencyCode;
    if (c != 'XXX') {
      _currency = currencies.contains(c) ? c : 'OTHER';
      if (_currency == 'OTHER') _customCurrency.text = c;
    }
    final t = widget.owner.timezoneName;
    if (t != 'Etc/UTC') {
      _timezone = timezones.contains(t) ? t : 'OTHER';
      if (_timezone == 'OTHER') _customTimezone.text = t;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _school, _campus, _customCurrency, _customTimezone,
      _year, _start, _end,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(TextEditingController controller) async {
    final existing = DateTime.tryParse(controller.text);
    final date = await showDatePicker(
      context: context,
      initialDate: existing ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => controller.text = _dateIso(date));
    }
  }

  Widget _dateField(String title, String key, TextEditingController controller) {
    return TextFormField(
      key: Key(key),
      controller: controller,
      readOnly: true,
      onTap: () => _pickDate(controller),
      decoration: InputDecoration(
        labelText: title,
        hintText: 'Choose a date',
        suffixIcon: IconButton(
          tooltip: 'Choose $title',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () => _pickDate(controller),
        ),
      ),
      validator: (v) => v == null || DateTime.tryParse(v) == null
          ? 'Choose $title' : null,
    );
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    final start = DateTime.tryParse(_start.text);
    final end = DateTime.tryParse(_end.text);
    if (start == null || end == null ||
        !end.isAfter(start) || end.difference(start).inDays > 550) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Academic year end date must follow the start '
            'and be within 550 days.'),
      ));
      return;
    }

    final currency = _currency == 'OTHER'
        ? _customCurrency.text.trim().toUpperCase() : _currency!;
    final timezone = _timezone == 'OTHER'
        ? _customTimezone.text.trim() : _timezone!;

    final campus = widget.owner.campuses.first;
    final request = OwnerInitialSetupRequest(
      schoolId: widget.owner.schoolId,
      campusId: campus.id,
      schoolName: _school.text.trim(),
      campusName: _campus.text.trim(),
      currencyCode: currency,
      timezoneName: timezone,
      yearLabel: _year.text.trim(),
      yearStartsOn: _start.text,
      yearEndsOn: _end.text,
      expectedSchoolRevision: widget.owner.schoolRevision,
      expectedCampusRevision: campus.revision,
    );
    setState(() => _saving = true);
    try {
      final updated = await widget.onSave(request);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('School setup saved and verified.')),
      );
      widget.onSaved(updated);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Setup was not saved. Verify the details and '
            'try again. If the form is stale, sign out and reload.'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Complete Initial School Setup',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            const Text('Enter real school details. Nothing is saved '
                'until you select Save Setup. This initial setup can only '
                'be completed once; future changes will use a separate '
                'audited Settings workflow.'),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('setup-school-name'),
              controller: _school,
              decoration: const InputDecoration(labelText: 'School name'),
              validator: (s) => s == null || s.trim().length < 2
                  ? 'Enter your school name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('setup-campus-name'),
              controller: _campus,
              decoration: const InputDecoration(
                labelText: 'First campus name',
                hintText: 'Enter actual campus name',
              ),
              validator: (s) => s == null || s.trim().length < 2
                  ? 'Enter your campus name' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('setup-currency'),
              initialValue: _currency,
              decoration: const InputDecoration(labelText: 'School currency'),
              isExpanded: true,
              items: [
                for (final code in currencies)
                  DropdownMenuItem(
                    value: code,
                    child: Text(code == 'OTHER' ? 'Other ISO code' : code),
                  ),
              ],
              onChanged: (v) => setState(() => _currency = v),
              validator: (v) => v == null ? 'Choose a currency' : null,
            ),
            if (_currency == 'OTHER') ...[
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('setup-other-currency'),
                controller: _customCurrency,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'ISO 4217 currency code (3 letters)',
                ),
                validator: (s) {
                  final code = (s ?? '').trim().toUpperCase();
                  return RegExp(r'^[A-Z]{3}$').hasMatch(code) && code != 'XXX'
                      ? null : 'Enter a valid currency code';
                },
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('setup-timezone'),
              initialValue: _timezone,
              decoration: const InputDecoration(
                labelText: 'School timezone',
              ),
              isExpanded: true,
              items: [
                for (final zone in timezones)
                  DropdownMenuItem(
                    value: zone,
                    child: Text(zone == 'OTHER' ? 'Other IANA timezone' : zone),
                  ),
              ],
              onChanged: (v) => setState(() => _timezone = v),
              validator: (v) => v == null ? 'Choose a timezone' : null,
            ),
            if (_timezone == 'OTHER') ...[
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('setup-other-timezone'),
                controller: _customTimezone,
                decoration: const InputDecoration(
                  labelText: 'IANA timezone (e.g. Asia/Karachi)',
                ),
                validator: (s) => s == null || s.trim().length < 2
                    ? 'Enter a timezone' : null,
              ),
            ],
            const SizedBox(height: 20),
            Text('Academic year',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('setup-year-label'),
              controller: _year,
              decoration: const InputDecoration(
                labelText: 'Academic year name',
                hintText: 'e.g. 2026-2027',
              ),
              validator: (s) => s == null ||
                  s.trim().length < 4 || s.trim().length > 30
                      ? 'Enter an academic year name' : null,
            ),
            const SizedBox(height: 12),
            _dateField('Start date', 'setup-year-start', _start),
            const SizedBox(height: 12),
            _dateField('End date', 'setup-year-end', _end),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('save-school-setup'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Setup'),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: saving school setup does not activate fees, attendance '
              'or admissions. Those modules still require their own '
              'validated database workflows.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
