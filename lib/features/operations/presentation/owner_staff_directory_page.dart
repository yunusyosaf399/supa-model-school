import 'package:flutter/material.dart';

import '../../auth/data/owner_auth_gateway.dart';
import '../data/owner_operations_repository.dart';

/// Owner-only read-only view of real campus HR master data.
class OwnerStaffDirectoryPage extends StatefulWidget {
  const OwnerStaffDirectoryPage({
    super.key,
    required this.owner,
    required this.repository,
    this.selectedCampusId,
  });

  final OwnerAccess owner;
  final OwnerOperationsRepository repository;
  final String? selectedCampusId;

  @override
  State<OwnerStaffDirectoryPage> createState() =>
      _OwnerStaffDirectoryPageState();
}

class _OwnerStaffDirectoryPageState extends State<OwnerStaffDirectoryPage> {
  StaffDirectorySnapshot? _snapshot;
  String? _error;
  String _filter = '';
  bool _loading = false;
  int _request = 0;

  String? get _campusId {
    if (widget.owner.campuses.isEmpty) return null;
    for (final campus in widget.owner.campuses) {
      if (campus.id == widget.selectedCampusId) return campus.id;
    }
    return widget.owner.campuses.first.id;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant OwnerStaffDirectoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCampusId != widget.selectedCampusId ||
        oldWidget.owner.schoolId != widget.owner.schoolId) {
      _snapshot = null;
      _filter = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final campus = _campusId;
    if (campus == null) {
      setState(() {
        _snapshot = null;
        _error = 'No active campus. Configure your school first.';
      });
      return;
    }
    final sequence = ++_request;
    setState(() {
      _snapshot = null;
      _error = null;
      _loading = true;
    });
    try {
      final result = await widget.repository.loadStaff(
        schoolId: widget.owner.schoolId,
        campusId: campus,
      );
      if (!mounted || sequence != _request) return;
      setState(() {
        _snapshot = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || sequence != _request) return;
      setState(() {
        _error = 'Unable to load staff records: ' + error.toString();
        _loading = false;
      });
    }
  }

  Widget _staffCard(StaffMember member) => Card.outlined(
    key: Key('owner-staff-' + member.employeeNo),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.badge_outlined, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(member.name,
              style: Theme.of(context).textTheme.titleMedium)),
        ]),
        const SizedBox(height: 6),
        Text(member.employeeNo,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text(member.position,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(member.department),
        const SizedBox(height: 8),
        Text('Employment: ' + member.status + ' • ' + member.employmentType),
        Text('Hired: ' + member.hiredOn),
        Text(member.hasAccount
            ? 'Login account linked'
            : 'No login account linked',
            style: Theme.of(context).textTheme.bodySmall),
        if (member.isTeaching)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Teaching position'),
          ),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    final filtered = data == null
        ? const <StaffMember>[]
        : data.staff.where((member) {
            final query = _filter.toLowerCase().trim();
            return query.isEmpty ||
                member.name.toLowerCase().contains(query) ||
                member.employeeNo.toLowerCase().contains(query) ||
                member.position.toLowerCase().contains(query) ||
                member.department.toLowerCase().contains(query);
          }).toList();
    return LayoutBuilder(builder: (context, bounds) {
      final wide = bounds.maxWidth >= 800;
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('owner-staff-live-page'),
          padding: EdgeInsets.all(wide ? 22 : 12),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Staff Directory',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const Text('Live Supabase • Read-only'),
                    ]),
                IconButton(
                  key: const Key('owner-staff-refresh'),
                  tooltip: 'Refresh staff from Supabase',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
                trailing: TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('Retry')),
              ),
            if (data != null) ...[
              Card.outlined(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(spacing: 16, runSpacing: 8, children: [
                  Text('Employees: ' + data.staff.length.toString()),
                  Text('Departments: ' + data.departments.length.toString()),
                  Text('Positions: ' + data.positionCount.toString()),
                ]),
              )),
              if (data.staff.any(
                  (member) => member.employeeNo.startsWith('SAMPLE-')))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'SAMPLE employees are fictional test profiles and are '
                    'not login-enabled staff accounts.',
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('owner-staff-search'),
                onChanged: (value) => setState(() => _filter = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name, employee ID, position or department',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const Text('No staff records match the current search.'),
              LayoutBuilder(builder: (context, size) {
                final columns = size.maxWidth >= 1100
                    ? 3 : size.maxWidth >= 640 ? 2 : 1;
                const gap = 10.0;
                final width = (size.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final member in filtered)
                      SizedBox(width: width, child: _staffCard(member)),
                  ],
                );
              }),
            ],
          ],
        ),
      );
    });
  }
}
