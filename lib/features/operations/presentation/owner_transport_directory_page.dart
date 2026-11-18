import 'package:flutter/material.dart';

import '../../auth/data/owner_auth_gateway.dart';
import '../data/owner_operations_repository.dart';

/// Owner read-only overview of vehicles, routes, stops and enrolled riders.
class OwnerTransportDirectoryPage extends StatefulWidget {
  const OwnerTransportDirectoryPage({
    super.key,
    required this.owner,
    required this.repository,
    this.selectedCampusId,
  });
  final OwnerAccess owner;
  final OwnerOperationsRepository repository;
  final String? selectedCampusId;

  @override
  State<OwnerTransportDirectoryPage> createState() =>
      _OwnerTransportDirectoryPageState();
}

class _OwnerTransportDirectoryPageState
    extends State<OwnerTransportDirectoryPage> {
  TransportDirectorySnapshot? _snapshot;
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
  void didUpdateWidget(covariant OwnerTransportDirectoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCampusId != widget.selectedCampusId ||
        oldWidget.owner.schoolId != widget.owner.schoolId ||
        oldWidget.owner.activeYearId != widget.owner.activeYearId) {
      _snapshot = null;
      _filter = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final campus = _campusId;
    final year = widget.owner.activeYearId;
    if (campus == null || year == null) {
      setState(() {
        _snapshot = null;
        _error = 'Configure an active school campus and academic year first.';
      });
      return;
    }
    final sequence = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _snapshot = null;
    });
    try {
      final result = await widget.repository.loadTransport(
        schoolId: widget.owner.schoolId,
        campusId: campus,
        academicYearId: year,
      );
      if (!mounted || sequence != _request) return;
      setState(() {
        _snapshot = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || sequence != _request) return;
      setState(() {
        _error = 'Unable to load transport records: ' + error.toString();
        _loading = false;
      });
    }
  }

  Widget _routeCard(TransportRoute route) => Card.outlined(
    key: Key('owner-route-' + route.code),
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.route_outlined),
          const SizedBox(width: 9),
          Expanded(child: Text(route.name,
              style: Theme.of(context).textTheme.titleMedium)),
        ]),
        const SizedBox(height: 3),
        Text(route.code + ' • ' +
            (route.active ? 'Active' : 'Inactive') + ' • ' +
            route.students.length.toString() + ' students'),
        const SizedBox(height: 12),
        Text('Pickup and drop-off stops',
            style: Theme.of(context).textTheme.titleSmall),
        if (route.stops.isEmpty)
          const Text('No stops configured'),
        for (final stop in route.stops)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              CircleAvatar(radius: 13,
                  child: Text(stop.order.toString(),
                      style: const TextStyle(fontSize: 11))),
              const SizedBox(width: 9),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stop.name),
                  Text('Pickup ' + (stop.pickupTime ?? 'Not set') +
                       ' • Drop-off ' + (stop.dropoffTime ?? 'Not set'),
                       style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
            ]),
          ),
        const Divider(),
        Text('Assigned students (' + route.students.length.toString() + ')',
            style: Theme.of(context).textTheme.titleSmall),
        if (route.students.isEmpty)
          const Text('No active student assignments for this year'),
        for (final student in route.students)
          ListTile(
            key: Key('owner-rider-' + student.registration),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(student.name),
            subtitle: Text(
              student.registration + ' • ' + student.className +
              (student.sectionName == null
                  ? '' : ' ' + student.sectionName!) +
              ' • ' + student.stopName,
            ),
          ),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = _snapshot;
    final routes = data == null
        ? const <TransportRoute>[]
        : data.routes.where((route) {
            final query = _filter.trim().toLowerCase();
            return query.isEmpty ||
                route.name.toLowerCase().contains(query) ||
                route.code.toLowerCase().contains(query) ||
                route.stops.any(
                    (stop) => stop.name.toLowerCase().contains(query)) ||
                route.students.any((student) =>
                    student.name.toLowerCase().contains(query) ||
                    student.registration.toLowerCase().contains(query));
          }).toList();
    return LayoutBuilder(builder: (context, bounds) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('owner-transport-live-page'),
          padding: EdgeInsets.all(bounds.maxWidth >= 800 ? 22 : 12),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Transport',
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text('Live Supabase • ' +
                      (data?.yearLabel ??
                          widget.owner.activeYearLabel ??
                          'Academic year') +
                      ' • Read-only'),
                ]),
                IconButton(
                  key: const Key('owner-transport-refresh'),
                  tooltip: 'Refresh transport from Supabase',
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
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(spacing: 16, runSpacing: 8, children: [
                    Text('Vehicles: ' + data.vehicles.length.toString()),
                    Text('Routes: ' + data.routes.length.toString()),
                    Text('Stops: ' + data.stopCount.toString()),
                    Text('Riders: ' + data.riderCount.toString()),
                  ]),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Vehicles are listed independently; the database does not '
                  'yet record which bus serves each route. SAMPLE entries '
                  'are fictional testing data.',
                ),
              ),
              Text('Vehicles',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (data.vehicles.isEmpty)
                const Text('No vehicles are recorded for this campus.'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final vehicle in data.vehicles)
                  Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.directions_bus_outlined),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(vehicle.registration),
                            Text(
                              'Seats: ' + vehicle.capacity.toString() +
                              ' • ' + vehicle.status,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              Text('Routes and Students',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              TextField(
                key: const Key('owner-transport-search'),
                onChanged: (value) => setState(() => _filter = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search route, stop or student',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (routes.isEmpty)
                const Text('No matching routes found.'),
              LayoutBuilder(builder: (context, size) {
                final columns = size.maxWidth >= 850 ? 2 : 1;
                const gap = 10.0;
                final cardWidth = (size.maxWidth - gap * (columns - 1)) /
                    columns;
                return Wrap(spacing: gap, runSpacing: gap, children: [
                  for (final route in routes)
                    SizedBox(
                        width: cardWidth, child: _routeCard(route)),
                ]);
              }),
            ],
          ],
        ),
      );
    });
  }
}
