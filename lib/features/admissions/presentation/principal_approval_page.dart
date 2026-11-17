import 'package:flutter/material.dart';

import '../data/admission_approval_repository.dart';

/// Principal-only review surface. Parent router must supply a separately
/// verified Principal campus context; Owner shell must never route here.
/// Every operation is checked again against auth.uid() on the server.
class PrincipalApprovalPage extends StatefulWidget {
  const PrincipalApprovalPage({
    super.key,
    required this.schoolId,
    required this.campusId,
    required this.repository,
  });

  final String schoolId, campusId;
  final AdmissionApprovalRepository repository;

  @override
  State<PrincipalApprovalPage> createState() => _PrincipalApprovalPageState();
}

class _PrincipalApprovalPageState extends State<PrincipalApprovalPage> {
  List<PrincipalApprovalItem> _pending = const [];
  final Map<String, String> _pendingOperationIds = {};
  String? _error;
  bool _loading = false;
  String? _processingId;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void didUpdateWidget(covariant PrincipalApprovalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolId != widget.schoolId ||
        oldWidget.campusId != widget.campusId ||
        oldWidget.repository != widget.repository) {
      ++_generation;
      _pending = const [];
      _pendingOperationIds.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
  }

  Future<void> _reload() async {
    final token = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _pending = const [];
    });
    try {
      final records = await widget.repository.listPending(
        schoolId: widget.schoolId,campusId: widget.campusId);
      if (!mounted || token != _generation) return;
      setState(() { _pending = records; _loading = false; });
    } catch (_) {
      if (!mounted || token != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load the authorized Principal approval queue.';
      });
    }
  }

  Future<void> _decide(PrincipalApprovalItem item, String decision) async {
    if (_processingId != null) return;
    final reason = TextEditingController();
    final answer = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(decision == 'approve'
          ? 'Approve and enroll student?'
          : decision == 'return'
          ? 'Return application to admissions?'
          : 'Reject admission application?'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,children: [
          Text(item.name),
          const SizedBox(height: 9),
          Text(item.missingDocuments > 0
            ? '${item.missingDocuments} required document(s) are not verified. '
              'Conditional deadline: ${item.conditionalDue ?? 'not set'}.'
            : 'All required documents are recorded as verified.'),
          if (decision != 'approve') ...[
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              key: const Key('principal-review-reason'),
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
          FilledButton(
            key: const Key('principal-confirm-decision'),
            onPressed: () {
              final value = reason.text.trim();
              if (decision != 'approve' && value.length < 4) return;
              Navigator.pop(dialogContext,decision == 'approve' ? '' : value);
            },
            child: Text(decision == 'approve' ? 'Confirm approval' :
                decision == 'return' ? 'Return application' : 'Reject'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (answer == null || !mounted) return;
    final key = '${item.id}:${item.revision}:$decision';
    final operation = _pendingOperationIds.putIfAbsent(
      key,SupabaseAdmissionApprovalRepository.operationUuid);
    setState(() { _processingId=item.id; _error=null; });
    try {
      final result = await widget.repository.review(
        applicationId:item.id,expectedRevision:item.revision,
        operationId:operation,decision:decision,
        reason:answer.isEmpty ? null : answer,
      );
      if (!mounted) return;
      _pendingOperationIds.remove(key);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.status=='approved'
          ? 'Student enrolled after Principal approval.'
          : 'Application ${result.status}.'),
      ));
      await _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
        'Decision not confirmed. Retry the same decision to avoid duplication.');
    } finally {
      if (mounted) setState(() => _processingId=null);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('principal-approval-page'),
    padding: const EdgeInsets.all(20),
    children: [
      Row(children: [
        Expanded(child: Text('Principal • Admission Approvals',
          style: Theme.of(context).textTheme.headlineSmall)),
        IconButton(
          tooltip: 'Refresh Principal queue',
          onPressed: _loading || _processingId != null ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ]),
      const SizedBox(height: 8),
      const Card(child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('Only your assigned campus is shown. Conditional '
          'approvals keep outstanding certificate deadlines; files must '
          'be inspected before verification.'),
      )),
      if (_loading) const LinearProgressIndicator(
        key: Key('principal-queue-loading')),
      if (_error != null)
        ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(_error!),
          trailing: TextButton(onPressed: _reload,
            child: const Text('Retry')),
        ),
      if (!_loading && _error == null) ...[
        Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('${_pending.length} pending approvals',
            key: const Key('principal-queue-count'))),
        if (_pending.isEmpty)
          const Card(child: ListTile(title: Text('No pending admissions')))
        else
          for (final item in _pending)
            Card.outlined(child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,style:
                    Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 5),
                  Text('${item.documentState.toUpperCase()} • '
                    '${item.missingDocuments} unverified required certificate(s)'),
                  if (item.conditionalDue != null)
                    Text('Document deadline: ${item.conditionalDue}'),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8,runSpacing: 8,children: [
                    FilledButton(
                      key: Key('principal-approve-${item.id}'),
                      onPressed: _processingId == null
                        ? () => _decide(item,'approve') : null,
                      child: const Text('Approve'),
                    ),
                    OutlinedButton(
                      key: Key('principal-return-${item.id}'),
                      onPressed: _processingId == null
                        ? () => _decide(item,'return') : null,
                      child: const Text('Return'),
                    ),
                    OutlinedButton(
                      key: Key('principal-reject-${item.id}'),
                      onPressed: _processingId == null
                        ? () => _decide(item,'reject') : null,
                      child: const Text('Reject'),
                    ),
                  ]),
                ]),
            )),
      ],
    ],
  );
}
