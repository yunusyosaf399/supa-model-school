import 'package:flutter/material.dart';
import '../../auth/data/owner_auth_gateway.dart';
import '../data/fee_setup_repository.dart';

/// Live Owner-only fee master data. No demonstration amounts or payment writes.
class FeeSetupPage extends StatefulWidget {
  const FeeSetupPage({super.key, required this.owner, required this.repository,
    this.selectedCampusId});
  final OwnerAccess owner;
  final FeeSetupRepository repository;
  final String? selectedCampusId;
  @override
  State<FeeSetupPage> createState() => _FeeSetupPageState();
}

class _FeeSetupPageState extends State<FeeSetupPage> {
  FeeSetupSnapshot? _data;
  bool _loading = false;
  String? _error;
  int _request = 0;

  String get _campusId => widget.owner.campuses.any(
    (c) => c.id == widget.selectedCampusId)
      ? widget.selectedCampusId! : widget.owner.campuses.first.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant FeeSetupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCampusId != widget.selectedCampusId ||
        oldWidget.owner.activeYearId != widget.owner.activeYearId ||
        oldWidget.owner.schoolId != widget.owner.schoolId) {
      _data = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final year = widget.owner.activeYearId;
    if (year == null || widget.owner.campuses.isEmpty) {
      setState(() {
        _error = 'Configure the active academic year and campus first.';
        _loading = false;
        _data = null;
      });
      return;
    }
    final sequence = ++_request;
    setState(() { _error = null; _loading = true; _data = null; });
    try {
      final snapshot = await widget.repository.load(
        schoolId: widget.owner.schoolId, campusId: _campusId,
        academicYearId: year);
      if (!mounted || sequence != _request) return;
      setState(() { _data = snapshot; _loading = false; });
    } catch (error) {
      if (!mounted || sequence != _request) return;
      setState(() { _loading = false; _error = 'Could not load fees: $error'; });
    }
  }

  Future<void> _addCategory() async {
    final name = TextEditingController(), code = TextEditingController();
    String frequency = 'monthly';
    bool discountable = true, busy = false;
    String? error;
    await showDialog<void>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (dialogContext, update) => AlertDialog(
        title: const Text('Add Fee Category'),
        content: SizedBox(width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('fee-category-name'), controller: name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Name',
                hintText: 'Tuition Fee')),
            TextField(key: const Key('fee-category-code'), controller: code,
              maxLength: 30,
              decoration: const InputDecoration(labelText: 'Unique Code',
                hintText: 'TUITION')),
            DropdownButtonFormField<String>(
              key: const Key('fee-category-frequency'),
              initialValue: frequency,
              decoration: const InputDecoration(labelText: 'Billing Frequency'),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                DropdownMenuItem(value: 'one_time', child: Text('One Time')),
                DropdownMenuItem(value: 'manual', child: Text('Manual')),
              ],
              onChanged: busy ? null : (value) {
                if (value != null) update(() => frequency = value);
              }),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: discountable, title: const Text('Discount eligible'),
              onChanged: busy ? null : (value) {
                if (value != null) update(() => discountable = value);
              }),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!, style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
          FilledButton(key: const Key('save-fee-category'),
            onPressed: busy ? null : () async {
              final normalized = code.text.trim().toUpperCase();
              if (name.text.trim().length < 2 ||
                  !RegExp(r'^[A-Z][A-Z0-9_]{1,29}$').hasMatch(normalized)) {
                update(() => error = 'Enter a name and valid unique code.');
                return;
              }
              update(() { busy = true; error = null; });
              try {
                await widget.repository.createCategory(
                  schoolId: widget.owner.schoolId, code: normalized,
                  name: name.text, frequency: frequency,
                  discountable: discountable);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                await _load();
              } catch (exception) {
                if (dialogContext.mounted) update(() {
                  busy = false; error = 'Save failed: $exception';
                });
              }
            },
            child: const Text('Save Category')),
        ],
      )));
  }

  Future<void> _configure(ClassFeeSummary schoolClass) async {
    final data = _data;
    if (data == null) return;
    final cats = data.categories.where((c) => c.active).toList();
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add a fee category before configuring a class.')));
      return;
    }
    final old = {
      for (final line in schoolClass.plan?.lines ?? const <FeePlanLine>[])
        line.categoryId: line,
    };
    final chosen = old.keys.toSet();
    final optional = <String>{
      for (final line in old.values) if (line.optional) line.categoryId,
    };
    final amounts = {
      for (final cat in cats) cat.id: TextEditingController(
        text: old[cat.id] == null ? '' :
          FeeMoney.showMinor(old[cat.id]!.amountMinor)),
    };
    final planName = TextEditingController(text: schoolClass.plan?.name ??
      schoolClass.name + ' Fees ' + data.yearLabel);
    bool busy = false;
    String? error;
    await showDialog<void>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (dialogContext, update) => AlertDialog(
        title: Text('Configure ' + schoolClass.name),
        content: SizedBox(width: 580,
          height: MediaQuery.sizeOf(dialogContext).height * .58,
          child: Column(children: [
            TextField(controller: planName, maxLength: 120,
              key: const Key('fee-plan-name'),
              decoration: const InputDecoration(labelText: 'Plan Name')),
            const Text('Choose categories and enter amounts. Saving creates '
              'a new active version, retaining the previous plan for audit. '
              'Student charges are not generated by this action.'),
            const SizedBox(height: 8),
            Expanded(child: ListView(children: [
              for (final cat in cats) Card.outlined(
                child: Padding(padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    CheckboxListTile(
                      key: Key('fee-category-select-' + cat.code),
                      contentPadding: EdgeInsets.zero,
                      title: Text(cat.name),
                      subtitle: Text(cat.frequency + ' • ' + cat.code),
                      value: chosen.contains(cat.id),
                      onChanged: busy ? null : (v) => update(() {
                        if (v == true) { chosen.add(cat.id); }
                        else { chosen.remove(cat.id); }
                      })),
                    if (chosen.contains(cat.id)) ...[
                      TextField(
                        key: Key('fee-amount-' + cat.code),
                        controller: amounts[cat.id],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount (' + data.currency + ')',
                          hintText: '1000.00')),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Optional fee'),
                        value: optional.contains(cat.id),
                        onChanged: busy ? null : (v) => update(() {
                          if (v == true) { optional.add(cat.id); }
                          else { optional.remove(cat.id); }
                        })),
                    ],
                  ]),
                )),
            ])),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!, style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
          FilledButton(key: const Key('save-class-fee-plan'),
            onPressed: busy ? null : () async {
              final lines = <FeePlanLine>[];
              for (final cat in cats) {
                if (!chosen.contains(cat.id)) continue;
                final minor = FeeMoney.parseMinor(amounts[cat.id]!.text);
                if (minor == null) {
                  update(() => error = 'Invalid amount for ' + cat.name +
                    '. Use at most two decimal places.');
                  return;
                }
                lines.add(FeePlanLine(categoryId: cat.id,
                  amountMinor: minor, optional: optional.contains(cat.id)));
              }
              if (lines.isEmpty || planName.text.trim().length < 2) {
                update(() => error = 'Enter a plan name and select a fee.');
                return;
              }
              update(() { busy = true; error = null; });
              try {
                await widget.repository.saveClassPlan(
                  schoolId: widget.owner.schoolId,
                  campusId: data.campusId, academicYearId: data.yearId,
                  classId: schoolClass.id, name: planName.text, items: lines);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                await _load();
              } catch (exception) {
                if (dialogContext.mounted) update(() {
                  busy = false; error = 'Plan not saved: $exception';
                });
              }
            }, child: const Text('Save Fee Plan')),
        ],
      )));
  }

  String _total(ClassFeeSummary schoolClass, String frequency) {
    final data = _data;
    final plan = schoolClass.plan;
    if (data == null || plan == null) return 'Not configured';
    final lookup = {for (final c in data.categories) c.id: c};
    final amount = plan.lines.where((line) => !line.optional &&
      lookup[line.categoryId]?.frequency == frequency)
      .fold<int>(0, (sum, line) => sum + line.amountMinor);
    return data.currency + ' ' + FeeMoney.showMinor(amount);
  }

  Widget _classCard(ClassFeeSummary schoolClass) {
    final plan = schoolClass.plan;
    return Card.outlined(
      key: Key('fee-class-' + schoolClass.id),
      child: Padding(padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.school_outlined),
            const SizedBox(width: 9),
            Expanded(child: Text(schoolClass.name,
              style: Theme.of(context).textTheme.titleMedium)),
            if (plan != null) const Chip(label: Text('Active')),
          ]),
          const SizedBox(height: 10),
          Text('Monthly standard fees',
            style: Theme.of(context).textTheme.bodySmall),
          Text(_total(schoolClass,'monthly'),
            style: Theme.of(context).textTheme.titleLarge),
          Text('One-time: ' + _total(schoolClass,'one_time')),
          const SizedBox(height: 6),
          Text(plan == null ? 'No plan configured' :
            'Version ' + plan.version.toString() +
            ' • Effective ' + plan.effectiveFrom,
            style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: Key('fee-configure-' + schoolClass.id),
            onPressed: () => _configure(schoolClass),
            icon: const Icon(Icons.edit_outlined),
            label: Text(plan == null ? 'Configure Fees' : 'Update Fee Plan')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return LayoutBuilder(builder: (context, bounds) => RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('live-fee-setup-page'),
        padding: EdgeInsets.all(bounds.maxWidth >= 850 ? 24 : 12),
        children: [
          Wrap(alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10, runSpacing: 10, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Fees & Finance',
                  style: Theme.of(context).textTheme.headlineSmall),
                Text('Class Fee Setup • ' + (data?.yearLabel ??
                    widget.owner.activeYearLabel ?? 'No active year')),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(key: const Key('fee-refresh'),
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh fees from Supabase'),
                FilledButton.icon(key: const Key('fee-add-category'),
                  onPressed: _loading ? null : _addCategory,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Category')),
              ]),
            ]),
          const SizedBox(height: 14),
          const Card(child: Padding(padding: EdgeInsets.all(12),
            child: Text('Live Supabase fee configuration. Payment collection, '
              'individual discounts, invoices and outstanding balances '
              'are separate upcoming integrations.'))),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(_error!),
            trailing: TextButton(onPressed: _load, child: const Text('Retry'))),
          if (data != null) ...[
            const SizedBox(height: 12),
            Text('Fee Categories (' + data.categories.length.toString() + ')',
              style: Theme.of(context).textTheme.titleLarge),
            if (data.categories.isEmpty)
              const Padding(padding: EdgeInsets.all(8),
                child: Text('No categories yet. Add Tuition, Transport, '
                  'Exams, Books or other school fees.')),
            if (data.categories.isNotEmpty)
              Wrap(spacing: 8, children: [
                for (final c in data.categories)
                  Chip(label: Text(c.name + ' • ' + c.frequency)),
              ]),
            const SizedBox(height: 16),
            Text('Class Fee Plans (' + data.classes.length.toString() + ')',
              style: Theme.of(context).textTheme.titleLarge),
            if (data.classes.isEmpty)
              const Text('No classes found in this campus/year. '
                'Configure the Academic Structure first.'),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, size) {
              final columns = size.maxWidth >= 1050 ? 3
                : size.maxWidth >= 600 ? 2 : 1;
              const gap = 10.0;
              final width = (size.maxWidth - gap*(columns-1))/columns;
              return Wrap(spacing: gap, runSpacing: gap, children: [
                for (final c in data.classes)
                  SizedBox(width: width, child: _classCard(c)),
              ]);
            }),
          ],
        ],
      ),
    ));
  }
}
