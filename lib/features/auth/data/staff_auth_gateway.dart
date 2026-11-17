import 'package:supabase_flutter/supabase_flutter.dart';

class SchoolStaffAccess {
  const SchoolStaffAccess({
    required this.userId,required this.displayName,
    required this.schoolId,required this.schoolName,
    required this.campusId,required this.campusName,
    required this.role,
  });
  final String userId,displayName,schoolId,schoolName;
  final String campusId,campusName,role;

  factory SchoolStaffAccess.fromJson(Map<String,dynamic> map) {
    String require(String key) {
      final v=map[key];
      if(v is! String || v.trim().isEmpty) {
        throw StateError('Invalid authorized staff profile');
      }
      return v;
    }
    return SchoolStaffAccess(
      userId:require('user_id'),
      displayName:require('display_name'),
      schoolId:require('school_id'),
      schoolName:require('school_name'),
      campusId:require('campus_id'),
      campusName:require('campus_name'),
      role:require('role'),
    );
  }
}

abstract class StaffAuthGateway {
  bool get configured;
  Future<SchoolStaffAccess?> restore();
  Future<SchoolStaffAccess> signIn(String email,String password);
  Future<void> signOut();
}

class UnconfiguredStaffAuthGateway implements StaffAuthGateway {
  const UnconfiguredStaffAuthGateway();
  @override bool get configured=>false;
  @override Future<SchoolStaffAccess?> restore() async=>null;
  @override Future<SchoolStaffAccess> signIn(String email,String password) async=>
    throw StateError('Staff login is not configured');
  @override Future<void> signOut() async {}
}

class SupabaseStaffAuthGateway implements StaffAuthGateway {
  const SupabaseStaffAuthGateway(this.client);
  final SupabaseClient client;
  @override bool get configured=>true;

  Future<SchoolStaffAccess> _validate() async {
    final identity=await client.auth.getUser();
    if(client.auth.currentSession==null || identity.user==null) {
      throw StateError('Valid staff session required');
    }
    final result=await client.rpc('staff_session_context');
    if(result is! Map) throw StateError('Staff role not authorized');
    final access=SchoolStaffAccess.fromJson(Map<String,dynamic>.from(result));
    if(access.userId!=identity.user!.id) {
      throw StateError('Staff identity mismatch');
    }
    return access;
  }

  @override
  Future<SchoolStaffAccess?> restore() async {
    if(client.auth.currentSession==null)return null;
    try {return await _validate();}catch(_){return null;}
  }

  @override
  Future<SchoolStaffAccess> signIn(String email,String password) async {
    if(!email.contains('@')||password.isEmpty) {
      throw const FormatException('Email and password required');
    }
    try {
      final res=await client.auth.signInWithPassword(
        email:email.trim(),password:password);
      if(res.session==null||res.user==null)throw StateError('Sign-in failed');
      return await _validate();
    } catch (_) {
      await client.auth.signOut();
      rethrow;
    }
  }

  @override Future<void> signOut()=>client.auth.signOut();
}
