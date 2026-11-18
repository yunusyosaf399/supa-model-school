import 'package:flutter/material.dart';
import '../data/owner_user_management_repository.dart';

/// Authorized Owner editor. Each toggle is persisted immediately to an
/// audited, Owner-only RPC; disabled/not implemented modules remain nonfunctional.
Future<void> showStaffPermissionsDialog(
  BuildContext context,
  OwnerStaffAccount staff,
  OwnerUserManagementRepository repository,
) async {
  final OwnerPermissionRepository? access = repository is OwnerPermissionRepository
      ? repository as OwnerPermissionRepository : null;
  if (access == null) return;
  List<StaffPermission> permissions;
  try {
    // RPC projections are immutable. Keep a mutable dialog-local copy so
    // confirmed writes can update the switch without changing the source.
    permissions = List<StaffPermission>.of(
      await access.permissions(staff.roleId),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Permissions could not be loaded: $error')));
    return;
  }
  if (!context.mounted) return;
  var saving = false;
  String? errorText;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, updateDialog) => AlertDialog(
        title: Text('Permissions • ${staff.name}'),
        content: SizedBox(
          width: 650,
          height: MediaQuery.sizeOf(dialogContext).height * .68,
          child: Column(children: [
            Text('Assigned campus: ${staff.campusName}. '
              'You may select read-only, write, or individual actions. '
              'Planned modules will become operational only after their '
              'backend authorization and screens are implemented.'),
            if (errorText != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(errorText!,
                style: TextStyle(color: Theme.of(dialogContext).colorScheme.error))),
            if (saving) const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Expanded(child: ListView.builder(
              key: const Key('owner-permission-list'),
              itemCount: permissions.length,
              itemBuilder: (context, index) {
                final p = permissions[index];
                final sectionChanged = index == 0 ||
                  permissions[index - 1].section != p.section;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (sectionChanged) Padding(
                      padding: const EdgeInsets.fromLTRB(12, 15, 12, 4),
                      child: Text(p.section,
                        style: Theme.of(context).textTheme.titleMedium)),
                    SwitchListTile(
                      key: Key('permission-${p.code}'),
                      dense: true,
                      title: Text(p.title),
                      subtitle: Text(p.implemented
                        ? 'Available • ${p.action}'
                        : 'Planned • ${p.action}'),
                      value: p.allowed,
                      onChanged: saving ? null : (allowed) async {
                        updateDialog(() { saving = true; errorText = null; });
                        try {
                          await access.setPermission(
                            staff.roleId, p.code, allowed);
                        } catch (error) {
                          if (dialogContext.mounted) {
                            updateDialog(() {
                              errorText = 'Could not save this permission: '
                                '${error is StateError ? error.message : error}';
                              saving = false;
                            });
                          }
                          return;
                        }
                        // The database confirmed the change. UI state updates
                        // must not be mistaken for backend save failures.
                        if (!dialogContext.mounted) return;
                        updateDialog(() {
                          permissions[index] = StaffPermission(
                            code: p.code, section: p.section, title: p.title,
                            action: p.action, implemented: p.implemented,
                            allowed: allowed,
                          );
                          saving = false;
                        });
                      },
                    ),
                  ],
                );
              },
            )),
          ]),
        ),
        actions: [
          FilledButton(
            onPressed: saving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}
