import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/data/owner_auth_gateway.dart';
import '../data/fee_setup_repository.dart';
import '../data/fee_monthly_repository.dart';
import 'fee_setup_page.dart';

/// Shared Owner finance navigation, identical for Windows and Android.
class FeeFinancePage extends StatelessWidget {
  const FeeFinancePage({
    super.key, required this.owner,
    required this.setupRepository, required this.monthlyRepository,
    this.selectedCampusId,
  });

  final OwnerAccess owner;
  final FeeSetupRepository setupRepository;
  final FeeMonthlyRepository monthlyRepository;
  final String? selectedCampusId;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(children: [
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: const TabBar(
          key: Key('fee-finance-tabs'),
          tabs: [
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Monthly Billing'),
            Tab(icon: Icon(Icons.tune_outlined), text: 'Fee Setup'),
          ],
        ),
      ),
      Expanded(child: TabBarView(children: [
        FeeMonthlyPage(
          owner: owner,
          repository: monthlyRepository,
          selectedCampusId: selectedCampusId,
        ),
        FeeSetupPage(
          owner: owner,
          repository: setupRepository,
          selectedCampusId: selectedCampusId,
        ),
      ])),
    ]),
  );
}

class FeeMonthlyPage extends StatefulWidget {
  const FeeMonthlyPage({
    super.key, required this.owner,
    required this.repository, this.selectedCampusId,
  });
  final OwnerAccess owner;
  final FeeMonthlyRepository repository;
  final String? selectedCampusId;

  @override
  State<FeeMonthlyPage> createState() => _FeeMonthlyPageState();
}

class _FeeMonthlyPageState extends State<FeeMonthlyPage> {
  FeeMonthlyLedger? _ledger;
  String? _error, _notice;
  bool _busy = false;
  int _request = 0;
  String _filter = '';
  late String _month;
  String? _pendingGenerationOp, _pendingGenerationScope;

  @override
  void initState() {
    super.initState();
    _month = _monthChoices().last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant FeeMonthlyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner.schoolId != widget.owner.schoolId ||
        oldWidget.owner.activeYearId != widget.owner.activeYearId ||
        oldWidget.selectedCampusId != widget.selectedCampusId) {
      _month = _monthChoices().last;
      _pendingGenerationOp = null;
      _pendingGenerationScope = null;
      _ledger = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  String get _campusId {
    final campuses = widget.owner.campuses;
    if (campuses.any((campus) => campus.id == widget.selectedCampusId)) {
      return widget.selectedCampusId!;
    }
    return campuses.first.id;
  }

  List<String> _monthChoices() {
    final now = DateTime.now();
    final start = DateTime.tryParse(widget.owner.activeYearStartsOn ?? '') ??
        DateTime(now.year, now.month);
    final finish = DateTime.tryParse(widget.owner.activeYearEndsOn ?? '') ?? now;
    var current = DateTime(start.year, start.month);
    final last = finish.isBefore(now) ? finish : now;
    final months = <String>[];
    while (!current.isAfter(DateTime(last.year, last.month)) &&
        months.length < 36) {
      months.add(FeeMonth.normalize(current));
      current = DateTime(current.year, current.month + 1);
    }
    if (months.isEmpty) months.add(FeeMonth.normalize(now));
    return months;
  }

  Future<void> _load() async {
    final yearId = widget.owner.activeYearId;
    if (yearId == null || widget.owner.campuses.isEmpty) {
      setState(() {
        _ledger = null;
        _error = 'Configure a campus and active academic year first.';
      });
      return;
    }
    final request = ++_request;
    final month = _month, campusId = _campusId;
    setState(() { _busy = true; _error = null; _ledger = null; });
    try {
      final data = await widget.repository.load(
        schoolId: widget.owner.schoolId, campusId: campusId,
        yearId: yearId, month: month,
      );
      if (!mounted || request != _request) return;
      setState(() { _ledger = data; _busy = false; });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = 'Live monthly fees unavailable: $error';
        _busy = false;
      });
    }
  }

  void _chooseMonth(String? month) {
    if (month == null || month == _month) return;
    setState(() {
      _month = month;
      _pendingGenerationOp = null;
      _pendingGenerationScope = null;
      _notice = null;
    });
    _load();
  }

  Future<void> _generate() async {
    final data = _ledger;
    if (_busy || data == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate Monthly Bills?'),
        content: Text('Post class fees for ' + FeeMonth.label(_month) +
          ' in this campus. Existing scheduled charges will NOT be '
          'duplicated. Posted bills cannot be deleted or edited. '
          'Only configured mandatory monthly fee items are included.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirm-generate-bills'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate Bills')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final scope = data.campusId + '/' + data.yearId + '/' + data.month;
    if (_pendingGenerationScope != scope || _pendingGenerationOp == null) {
      _pendingGenerationScope = scope;
      _pendingGenerationOp = FeeOperationId.create();
    }
    setState(() { _busy = true; _error = null; });
    try {
      final result = await widget.repository.generate(
        schoolId: widget.owner.schoolId, campusId: data.campusId,
        yearId: data.yearId, month: data.month,
        operationId: _pendingGenerationOp!,
      );
      _pendingGenerationOp = null;
      _pendingGenerationScope = null;
      if (!mounted) return;
      _notice = result.addedCharges == 0
        ? 'No additional bills generated. Existing bills were preserved.'
        : 'Generated ' + result.addedCharges.toString() +
          ' new immutable charges for ' + FeeMonth.label(data.month) + '.';
      await _load();
    } catch (error) {
      if (mounted) setState(() {
        _busy = false;
        _error = 'Bills were not confirmed: $error. '
          'Retry with the same Generate button before attempting another run.';
      });
    }
  }

  String _money(int minor, String currency) =>
      currency + ' ' + FeeMoney.showMinor(minor);

  Future<void> _receiptDetails({
    required String studentName, required String currency,
    required FeeReceiptResult result, required String method,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.verified_outlined),
          SizedBox(width: 8), Text('Fee Receipt'),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Supa Model School',
                style: Theme.of(dialogContext).textTheme.titleMedium),
              const Divider(),
              SelectableText('Receipt: ' + result.number),
              Text('Student: ' + studentName),
              Text('Amount: ' + _money(result.amountMinor, currency)),
              Text('Method: ' + method.toUpperCase()),
              const SizedBox(height: 12),
              const Text('The receipt is saved in Supabase. '
                'Use the reference number to identify the transaction.'),
            ]),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: result.number));
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy Number')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _collect(FeeLedgerStudent student) async {
    final ledger = _ledger;
    if (ledger == null || student.outstandingMinor <= 0) return;
    FeeStudentStatement statement;
    try {
      statement = await widget.repository.statement(
        schoolId: ledger.schoolId, campusId: ledger.campusId,
        yearId: ledger.yearId, studentId: student.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not verify student balance: $error')));
      return;
    }
    if (!mounted) return;
    if (statement.outstandingMinor <= 0) {
      _notice = 'This student has no outstanding fees.';
      await _load();
      return;
    }
    final amount = TextEditingController();
    final bankReference = TextEditingController();
    var method = 'cash';
    var sending = false;
    var lockedDetails = false;
    String? message;
    final operationId = FeeOperationId.create();

    await showDialog<void>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (dialogContext, update) => AlertDialog(
        title: Text('Collect Fee • ' + student.name),
        content: SizedBox(width: 490,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Outstanding: ' +
              _money(statement.outstandingMinor, ledger.currency)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('fee-payment-amount'), controller: amount,
              enabled: !sending && !lockedDetails,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (' + ledger.currency + ')',
                hintText: '500.00'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('fee-payment-method'),
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Payment Method'),
              items: const [
                DropdownMenuItem(value: 'cash',child: Text('Cash')),
                DropdownMenuItem(value: 'bank',child: Text('Bank Transfer')),
              ],
              onChanged: sending || lockedDetails ? null : (value) {
                if (value != null) update(() => method = value);
              }),
            if (method == 'bank') ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('fee-payment-bank-reference'),
                controller: bankReference,
                enabled: !sending && !lockedDetails,
                decoration: const InputDecoration(
                  labelText: 'Verified Bank Reference'),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Payments are applied to the oldest unpaid charges '
              'for this student and academic year. No overpayment is allowed.'),
            if (sending) const LinearProgressIndicator(),
            if (message != null) Text(message!, style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: sending ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
          FilledButton.icon(
            key: const Key('fee-confirm-payment'),
            icon: const Icon(Icons.payments_outlined),
            onPressed: sending ? null : () async {
              final minor = FeeMoney.parseMinor(amount.text);
              if (minor == null || minor <= 0 ||
                  minor > statement.outstandingMinor ||
                  (method == 'bank' &&
                    bankReference.text.trim().length < 3)) {
                update(() => message = 'Enter a valid amount not exceeding '
                  'outstanding fees and a bank reference when applicable.');
                return;
              }
              update(() {
                sending = true;
                lockedDetails = true;
                message = null;
              });
              try {
                final result = await widget.repository.collect(
                  schoolId: ledger.schoolId,
                  campusId: ledger.campusId, yearId: ledger.yearId,
                  studentId: student.id, amountMinor: minor,
                  method: method,
                  bankReference: method == 'bank'
                    ? bankReference.text.trim() : null,
                  operationId: operationId,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                await _load();
                if (!mounted) return;
                await _receiptDetails(
                  studentName: student.name, currency: ledger.currency,
                  result: result, method: method,
                );
              } catch (error) {
                if (dialogContext.mounted) update(() {
                  sending = false;
                  message = 'Payment not confirmed: $error. '
                    'Retry the same details, or close and refresh the ledger '
                    'before starting another payment.';
                });
              }
            },
            label: Text(lockedDetails ? 'Retry Same Payment' : 'Save Payment')),
        ],
      )));
  }

  List<String> _discountMonths() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final until = DateTime.tryParse(widget.owner.activeYearEndsOn ?? '') ??
      DateTime(now.year, now.month + 12);
    final months = <String>[];
    var d = start;
    while (!d.isAfter(DateTime(until.year, until.month)) &&
        months.length < 24) {
      months.add(FeeMonth.normalize(d));
      d = DateTime(d.year, d.month + 1);
    }
    return months;
  }

  Future<void> _grantDiscount(FeeLedgerStudent student) async {
    final ledger = _ledger;
    if (ledger == null) return;
    final categories = ledger.categories.where((c) => c.discountable).toList();
    final months = _discountMonths();
    if (categories.isEmpty || months.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Configure an active discountable fee category first.')));
      return;
    }
    var categoryId = categories.first.id;
    var kind = 'percent';
    var startMonth = months.first;
    var busy = false;
    final value = TextEditingController();
    final reason = TextEditingController();
    String? error;
    await showDialog<void>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (dialogContext, update) => AlertDialog(
        title: Text('Scholarship • ' + student.name),
        content: SizedBox(width: 490,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Scholarships apply only to the selected category '
              'and future unposted fees. Existing bills are immutable.'),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('fee-discount-category'),
              initialValue: categoryId,
              decoration: const InputDecoration(labelText: 'Fee Category'),
              items: [
                for (final cat in categories)
                  DropdownMenuItem(value: cat.id, child: Text(cat.name)),
              ],
              onChanged: busy ? null : (v) {
                if (v != null) update(() => categoryId = v);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('fee-discount-kind'),
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Discount Type'),
              items: const [
                DropdownMenuItem(value: 'percent',child: Text('Percentage')),
                DropdownMenuItem(value: 'fixed',child: Text('Fixed Amount')),
              ],
              onChanged: busy ? null : (v) {
                if (v != null) update(() => kind = v);
              },
            ),
            TextField(
              key: const Key('fee-discount-value'),
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: kind == 'percent'
                  ? 'Discount Percentage (%)' : 'Discount (' +
                      ledger.currency + ')',
                hintText: kind == 'percent' ? '50.00' : '500.00')),
            DropdownButtonFormField<String>(
              key: const Key('fee-discount-start-month'),
              initialValue: startMonth,
              decoration: const InputDecoration(labelText: 'Start Month'),
              items: [
                for (final month in months)
                  DropdownMenuItem(value: month,child: Text(FeeMonth.label(month))),
              ],
              onChanged: busy ? null : (v) {
                if (v != null) update(() => startMonth = v);
              },
            ),
            TextField(key: const Key('fee-discount-reason'),
              controller: reason, maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Approval Reason',
                hintText: 'Merit scholarship')),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!, style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
          FilledButton(
            key: const Key('save-fee-discount'),
            onPressed: busy ? null : () async {
              final parsed = FeeMoney.parseMinor(value.text);
              if (parsed == null || parsed < 0 ||
                  (kind == 'percent' && parsed > 10000) ||
                  reason.text.trim().length < 4) {
                update(() => error = 'Enter valid scholarship terms '
                  'and a reason of at least four characters.');
                return;
              }
              update(() { busy = true; error = null; });
              try {
                await widget.repository.grantDiscount(
                  schoolId: ledger.schoolId, campusId: ledger.campusId,
                  yearId: ledger.yearId, studentId: student.id,
                  categoryId: categoryId, kind: kind,
                  percentBps: kind == 'percent' ? parsed : null,
                  fixedMinor: kind == 'fixed' ? parsed : null,
                  startMonth: startMonth, reason: reason.text,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _notice = 'Scholarship saved for future unposted fees.';
                await _load();
              } catch (exception) {
                if (dialogContext.mounted) update(() {
                  busy = false; error = 'Scholarship not saved: $exception';
                });
              }
            },
            child: const Text('Save Scholarship')),
        ],
      )));
  }

  Future<void> _statement(FeeLedgerStudent student) async {
    final ledger = _ledger;
    if (ledger == null) return;
    late FeeStudentStatement statement;
    try {
      statement = await widget.repository.statement(
        schoolId: ledger.schoolId, campusId: ledger.campusId,
        yearId: ledger.yearId, studentId: student.id,
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load student statement: $error')));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Fee Statement • ' + student.name),
        content: SizedBox(width: 700,
          height: MediaQuery.sizeOf(dialogContext).height * .65,
          child: ListView(children: [
            Text('Outstanding: ' + _money(
              statement.outstandingMinor, ledger.currency),
              style: Theme.of(dialogContext).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Charges (' + statement.charges.length.toString() + ')',
              style: Theme.of(dialogContext).textTheme.titleMedium),
            for (final charge in statement.charges)
              ListTile(
                dense: true,
                title: Text(charge.category + ' • ' +
                  FeeMonth.label(charge.month)),
                subtitle: Text('Gross ' +
                  _money(charge.grossMinor, ledger.currency) +
                  ' • Discount ' +
                  _money(charge.discountMinor, ledger.currency) +
                  ' • Paid ' + _money(charge.paidMinor, ledger.currency)),
                trailing: Text(_money(charge.outstandingMinor, ledger.currency)),
              ),
            const Divider(),
            Text('Receipts (' + statement.receipts.length.toString() + ')',
              style: Theme.of(dialogContext).textTheme.titleMedium),
            for (final receipt in statement.receipts)
              ListTile(
                dense: true,
                title: Text(receipt.number),
                subtitle: Text(receipt.method.toUpperCase() + ' • ' +
                    receipt.issuedAt.substring(0, 10)),
                trailing: Text(_money(receipt.amountMinor, ledger.currency)),
              ),
            const Divider(),
            Text('Active Scholarships (' +
              statement.discounts.length.toString() + ')',
              style: Theme.of(dialogContext).textTheme.titleMedium),
            for (final discount in statement.discounts)
              ListTile(
                dense: true,
                title: Text(discount.categoryName),
                subtitle: Text(discount.reason + ' • Starting ' +
                  FeeMonth.label(discount.startMonth)),
                trailing: Text(discount.kind == 'percent'
                  ? FeeMoney.showMinor(discount.percentBps ?? 0) + '%'
                  : _money(discount.fixedMinor ?? 0, ledger.currency)),
              ),
          ]),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _metric(String label, int amount, String currency) =>
    Card.outlined(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_money(amount, currency),
            style: Theme.of(context).textTheme.titleLarge)),
      ]),
    ));

  Widget _studentCard(FeeLedgerStudent student, FeeMonthlyLedger ledger) =>
    Card.outlined(
      key: Key('fee-student-' + student.id),
      child: Padding(padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.person_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(student.name,
              style: Theme.of(context).textTheme.titleMedium)),
            if (!student.active) const Chip(label: Text('Inactive')),
          ]),
          const SizedBox(height: 5),
          Text(student.registration + ' • ' + student.className),
          Text('This month: ' + _money(student.chargedMinor, ledger.currency) +
            ' • Paid: ' + _money(student.paidMinor, ledger.currency)),
          const SizedBox(height: 5),
          Text('Outstanding (school year): ' +
            _money(student.outstandingMinor, ledger.currency),
            style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            OutlinedButton(
              key: Key('fee-statement-' + student.id),
              onPressed: () => _statement(student),
              child: const Text('Statement')),
            if (student.outstandingMinor > 0)
              FilledButton.icon(
                key: Key('fee-collect-' + student.id),
                onPressed: () => _collect(student),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Collect Fee')),
            if (student.active)
              TextButton(
                key: Key('fee-scholarship-' + student.id),
                onPressed: () => _grantDiscount(student),
                child: const Text('Scholarship')),
          ]),
        ]),
      ),
    );

  @override
  Widget build(BuildContext context) {
    final ledger = _ledger;
    final options = _monthChoices();
    final displayed = ledger == null ? <FeeLedgerStudent>[] :
      ledger.students.where((s) {
        final q = _filter.toLowerCase().trim();
        return q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.registration.toLowerCase().contains(q) ||
          s.className.toLowerCase().contains(q);
      }).toList();
    return LayoutBuilder(builder: (context, bounds) {
      final compact = bounds.maxWidth < 720;
      return RefreshIndicator(onRefresh: _load, child: ListView(
        key: const Key('live-monthly-billing-page'),
        padding: EdgeInsets.all(compact ? 12 : 20),
        children: [
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 10,
            runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Monthly Fee Billing',
                  style: Theme.of(context).textTheme.headlineSmall),
                Text('Live Supabase • ' +
                  (ledger?.yearLabel ?? widget.owner.activeYearLabel ?? 'School year')),
              ]),
              DropdownButton<String>(
                key: const Key('fee-billing-month'),
                value: options.contains(_month) ? _month : options.last,
                items: [
                  for (final month in options)
                    DropdownMenuItem(value: month,
                      child: Text(FeeMonth.label(month))),
                ],
                onChanged: _busy ? null : _chooseMonth,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Card(child: Padding(padding: EdgeInsets.all(12),
            child: Text('Generate bills only after configuring class fee plans. '
              'Monthly charges are immutable; payment receipts are saved '
              'and allocated to the oldest unpaid charges.'))),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(_error!),
            trailing: TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('Retry'))),
          if (_notice != null) Padding(padding: const EdgeInsets.all(8),
            child: Text(_notice!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary))),
          if (ledger != null) ...[
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, size) {
              final columns = compact ? 2 : 4;
              const gap = 8.0;
              final cardWidth = (size.maxWidth - gap*(columns-1))/columns;
              final values = [
                ('Charges this month', ledger.chargedMinor),
                ('Paid toward month', ledger.paidMinor),
                ('Year outstanding', ledger.outstandingMinor),
                ('Received this month', ledger.receivedMinor),
              ];
              return Wrap(spacing: gap, runSpacing: gap, children: [
                for (final item in values)
                  SizedBox(width: cardWidth,
                    child: _metric(item.$1,item.$2,ledger.currency)),
              ]);
            }),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('fee-generate-monthly-bills'),
                onPressed: _busy ? null : _generate,
                icon: const Icon(Icons.post_add_outlined),
                label: const Text('Generate Monthly Bills'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('fee-student-search'),
              onChanged: (value) => setState(() => _filter = value),
              decoration: InputDecoration(
                hintText: 'Search student, registration or class',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Text('Students (' + displayed.length.toString() + ')',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (displayed.isEmpty)
              const Text('No students for the selected month and campus.'),
            LayoutBuilder(builder: (context, size) {
              final columns = size.maxWidth >= 1050 ? 3 :
                size.maxWidth >= 620 ? 2 : 1;
              const gap = 10.0;
              final width = (size.maxWidth-gap*(columns-1))/columns;
              return Wrap(spacing: gap, runSpacing: gap, children: [
                for (final student in displayed)
                  SizedBox(width: width,
                    child: _studentCard(student, ledger)),
              ]);
            }),
            const SizedBox(height: 16),
            Text('Recent Receipts',
              style: Theme.of(context).textTheme.titleLarge),
            if (ledger.recentReceipts.isEmpty)
              const Text('No fee receipts recorded in this campus.'),
            for (final receipt in ledger.recentReceipts)
              ListTile(
                key: Key('fee-receipt-' + receipt.id),
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(receipt.number + ' • ' + receipt.studentName),
                subtitle: Text(receipt.method.toUpperCase() + ' • ' +
                  receipt.issuedAt.substring(0, 10)),
                trailing: Text(_money(receipt.amountMinor, ledger.currency)),
              ),
          ],
        ],
      ));
    });
  }
}
