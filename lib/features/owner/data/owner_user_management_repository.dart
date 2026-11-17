import 'package:supabase_flutter/supabase_flutter.dart';

/// The staff record is returned only by the verified Owner-scoped RPC.
/// No password, session, token or Auth metadata is exposed.
class OwnerStaffAccount {
  const OwnerStaffAccount({
    required this.roleId,required this.userId,required this.name,
    required this.email,required this.role,required this.campusId,
    required this.campusName,required this.active,
    required this.emailConfirmed,
  });
  final String roleId,userId,name,email,role,campusName;
  final String? campusId;
  final bool active,emailConfirmed;
  factory OwnerStaffAccount.fromJson(Map<String,dynamic> raw) {
    return OwnerStaffAccount(
      roleId:raw['role_id'] as String,
      userId:raw['user_id'] as String,
      name:raw['name'] as String,
      email:raw['email'] as String? ?? '',
      role:raw['role'] as String,
      campusId:raw['campus_id'] as String?,
      campusName:raw['campus_name'] as String? ?? 'School-wide',
      active:raw['active']==true,
      emailConfirmed:raw['email_confirmed']==true,
    );
  }
}

class StaffPermission {
  const StaffPermission({
    required this.code, required this.section, required this.title,
    required this.action, required this.implemented, required this.allowed,
  });
  final String code, section, title, action;
  final bool implemented, allowed;

  factory StaffPermission.fromJson(Map<String, dynamic> map) =>
    StaffPermission(
      code: map['code'] as String,
      section: map['section'] as String,
      title: map['title'] as String,
      action: map['action'] as String,
      implemented: map['implemented'] == true,
      allowed: map['allowed'] == true,
    );
}

class OwnerUserCreation {
  const OwnerUserCreation({
    required this.schoolId,required this.campusId,
    required this.role,required this.email,required this.name,
    required this.password,
  });
  final String schoolId,campusId,role,email,name,password;
}

abstract class OwnerUserManagementRepository {
  const OwnerUserManagementRepository();
  Future<List<OwnerStaffAccount>> listUsers(String schoolId);
  Future<void> createUser(OwnerUserCreation invitation);
  Future<void> setRoleActive(String roleId,bool active);
  Future<List<StaffPermission>> permissions(String roleId) async =>
      throw UnsupportedError('Staff permissions not configured');
  Future<void> setPermission(String roleId, String code, bool allowed) async =>
      throw UnsupportedError('Staff permissions not configured');
}

class SupabaseOwnerUserManagementRepository
    implements OwnerUserManagementRepository {
  const SupabaseOwnerUserManagementRepository(this.client);
  final SupabaseClient client;

  Future<void> _requireUser() async {
    if(client.auth.currentSession == null ||
       (await client.auth.getUser()).user == null) {
      throw StateError('Verified school Owner session required');
    }
  }

  @override
  Future<List<OwnerStaffAccount>> listUsers(String schoolId) async {
    await _requireUser();
    final data=await client.rpc('owner_school_users',params:{
      'p_school':schoolId,
    });
    if(data is! List || data.length>5000) {
      throw StateError('Invalid school staff directory');
    }
    return List.unmodifiable(data.map((item)=>
      OwnerStaffAccount.fromJson(Map<String,dynamic>.from(item as Map))));
  }

  @override
  Future<void> createUser(OwnerUserCreation invitation) async {
    await _requireUser();
    final email=invitation.email.trim().toLowerCase();
    final name=invitation.name.trim();
    if(name.length<2 || name.length>120 ||
       email.length>254 || !email.contains('@') ||
       invitation.password.length < 12 || invitation.password.length > 128 ||
       !RegExp(r'[A-Za-z]').hasMatch(invitation.password) ||
       !RegExp(r'[0-9]').hasMatch(invitation.password)) {
      throw const FormatException('Enter a valid name, email and strong password');
    }
    final result=await client.functions.invoke('owner-create-user',body:{
      'school_id':invitation.schoolId,
      'campus_id':invitation.campusId,
      'role':invitation.role,
      'email':email,
      'name':name,
      'password':invitation.password,
    });
    final body=result.data;
    if(result.status!=201 || body is! Map || body['status']!='created') {
      throw StateError('Staff account creation was not confirmed');
    }
  }

  @override
  Future<List<StaffPermission>> permissions(String roleId) async {
    await _requireUser();
    final raw = await client.rpc('owner_staff_permission_matrix',
        params: {'p_role_id': roleId});
    if (raw is! List || raw.length > 200) {
      throw StateError('Invalid permissions matrix');
    }
    return List.unmodifiable(raw.map((item) => StaffPermission.fromJson(
      Map<String, dynamic>.from(item as Map),
    )));
  }

  @override
  Future<void> setPermission(String roleId, String code, bool allowed) async {
    await _requireUser();
    final raw = await client.rpc('owner_set_staff_permission', params: {
      'p_role_id': roleId, 'p_code': code, 'p_allowed': allowed,
    });
    if (raw is! Map || raw['role_id'] != roleId ||
        raw['code'] != code || raw['allowed'] != allowed) {
      throw StateError('Permission change was not confirmed');
    }
  }

  @override
  Future<void> setRoleActive(String roleId,bool active) async {
    await _requireUser();
    final result=await client.rpc('owner_set_staff_active',params:{
      'p_role_id':roleId,
      'p_active':active,
    });
    if(result is! Map || result['role_id']!=roleId ||
       result['active']!=active) {
      throw StateError('Staff access update was not confirmed');
    }
  }
}
