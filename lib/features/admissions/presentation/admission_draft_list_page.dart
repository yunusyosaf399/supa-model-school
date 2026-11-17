import 'package:flutter/material.dart';
import '../../auth/data/owner_auth_gateway.dart';
import '../data/admission_draft_repository.dart';

/// Displays only rows returned by the verified Owner/campus-scoped RPC.
/// Document status is metadata only; never opens private storage objects.
class AdmissionDraftListPage extends StatefulWidget {
  const AdmissionDraftListPage({
    super.key, required this.owner, required this.repository,
    required this.onNewAdmission, required this.onOpenDraft,
    this.selectedCampusId,
  });
  final OwnerAccess owner;
  final AdmissionDraftRepository repository;
  final String? selectedCampusId;
  final VoidCallback onNewAdmission;
  final ValueChanged<AdmissionDraftRecord> onOpenDraft;

  @override
  State<AdmissionDraftListPage> createState() => _AdmissionDraftListPageState();
}

class _AdmissionDraftListPageState extends State<AdmissionDraftListPage> {
  List<AdmissionDraftRecord> _records = const [];
  String? _error;
  bool _loading = false;
  int _generation = 0;
  String _statusFilter = 'all';
  String _search = '';
  String get _campusId =>
      widget.owner.campuses.any((c) => c.id == widget.selectedCampusId)
        ? widget.selectedCampusId!
        : widget.owner.campuses.first.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void didUpdateWidget(covariant AdmissionDraftListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.owner.userId != oldWidget.owner.userId ||
        widget.selectedCampusId != oldWidget.selectedCampusId) {
      _generation++;
      _records = const [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
  }

  Future<void> _reload() async {
    final request = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _records = const [];
    });
    try {
      final result = await widget.repository.listDrafts(
        schoolId: widget.owner.schoolId, campusId: _campusId);
      if (!mounted || request != _generation) return;
      setState(() {
        _records = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load authorized admissions. Check connection and permissions.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final campus = widget.owner.campuses
        .firstWhere((c) => c.id == _campusId);
    final visible = _records.where((entry) {
      final matchesFilter = _statusFilter == 'all' || entry.status == _statusFilter;
      final matchesSearch = _search.isEmpty ||
          entry.name.toLowerCase().contains(_search) ||
          entry.id.toLowerCase().contains(_search);
      return matchesFilter && matchesSearch;
    }).toList(growable: false);
    return ListView(
      key: const Key('live-admission-worklist'),
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Admissions', style: Theme.of(context).textTheme.headlineSmall),
              Text('${campus.name} • Live admission register', style:
                  Theme.of(context).textTheme.bodyMedium),
            ])),
          IconButton(onPressed: _loading ? null : _reload,
            tooltip: 'Refresh applications',
            icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: widget.onNewAdmission,
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('New Admission')),
        ]),
        const SizedBox(height: 12),
        const Card(child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Draft → certificate upload → Principal review → '
            'approved student enrollment. Conditional admissions retain '
            'outstanding-document deadlines.'),
        )),
        const SizedBox(height: 12),
        TextField(
          key: const Key('admissions-search'),
          decoration: const InputDecoration(
            labelText: 'Search admissions',
            hintText: 'Student name or application ID',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) => setState(() => _search = value.toLowerCase().trim()),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final filter in const <(String, String)>[
              ('all','All'), ('draft','Drafts'),
              ('submitted','Pending Principal'),
              ('returned','Returned'), ('approved','Approved'),
              ('rejected','Rejected'),
            ]) ...[
              ChoiceChip(
                key: Key('admissions-filter-${filter.$1}'),
                selected: _statusFilter == filter.$1,
                label: Text(filter.$2),
                onSelected: (_) => setState(() => _statusFilter = filter.$1),
              ),
              const SizedBox(width: 7),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(
            key: Key('admission-worklist-loading')),
        if (_error != null) Card(child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(_error!),
          trailing: TextButton(onPressed: _reload,
            child: const Text('Retry')),
        )),
        if (!_loading && _error == null) ...[
          Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('${visible.length} of ${_records.length} admissions',
              key: const Key('admission-worklist-count'),
              style: Theme.of(context).textTheme.titleMedium)),
          if (visible.isEmpty)
            const Card(child: ListTile(title: Text('No applications match this view')))
          else
            for (final entry in visible)
              Card.outlined(child: ListTile(
                title: Text(entry.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${entry.status.toUpperCase()} • Revision ${entry.revision} • '
                      '${entry.documents.where((d) => d['required'] == true &&
                         d['applicable'] == true &&
                         d['status'] != 'verified').length} outstanding documents'),
                    if (entry.status == 'submitted')
                      const Text('Awaiting assigned Principal decision'),
                    if (entry.status == 'approved')
                      const Text('Approved — enrolled student record created'),
                    if (entry.conditionalDue != null)
                      Text('Certificate deadline: ${entry.conditionalDue}'),
                    if (entry.returnedReason != null)
                      Text('Returned: ${entry.returnedReason}'),
                  ],
                ),
                trailing: entry.canResume
                  ? TextButton(
                      key: Key('resume-admission-${entry.id}'),
                      onPressed: () => widget.onOpenDraft(entry),
                      child: const Text('Resume'))
                  : Icon(
                      entry.status == 'approved'
                        ? Icons.verified_outlined
                        : entry.status == 'submitted'
                          ? Icons.hourglass_top
                          : Icons.block,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              )),
        ],
      ],
    );
  }
}
