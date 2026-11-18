import 'package:supabase_flutter/supabase_flutter.dart';

/// Verified campus assignment returned by the server, never constructed
/// from unauthenticated JWT user_metadata or client role selection.
class PrincipalCampus {
  const PrincipalCampus({required this.id,required this.name});
  final String id,name;
}

class PrincipalAccess {
  const PrincipalAccess({
    required this.userId,required this.displayName,
    required this.schoolId,required this.schoolName,required this.campuses,
    this.logoStoragePath,
  });
  final String userId,displayName,schoolId,schoolName;
  final String? logoStoragePath;
  final List<PrincipalCampus> campuses;

  factory PrincipalAccess.fromJson(Map<String,dynamic> json) {
    final raw=json['campuses'];
    if(raw is! List || raw.isEmpty) {
      throw StateError('Principal has no assigned campus');
    }
    final campuses=raw.map((item) {
      final map=Map<String,dynamic>.from(item as Map);
      final id=map['id'] as String?;
      final name=map['name'] as String?;
      if(id==null || id.isEmpty || name==null || name.isEmpty) {
        throw StateError('Invalid Principal campus record');
      }
      return PrincipalCampus(id:id,name:name);
    }).toList(growable:false);
    final userId=json['user_id'] as String?;
    final schoolId=json['school_id'] as String?;
    final schoolName=json['school_name'] as String?;
    final displayName=json['display_name'] as String?;
    if(userId==null || userId.isEmpty || schoolId==null || schoolId.isEmpty ||
      schoolName==null || schoolName.isEmpty ||
      displayName==null || displayName.isEmpty) {
      throw StateError('Invalid authenticated Principal context');
    }
    return PrincipalAccess(
      userId:userId,displayName:displayName,
      schoolId:schoolId,schoolName:schoolName,campuses:campuses,
      logoStoragePath:json['logo_storage_path'] as String?,
    );
  }
}

abstract class PrincipalAuthGateway {
  bool get configured;
  Future<PrincipalAccess?> restore();
  Future<PrincipalAccess> signIn(String email,String password);
  Future<void> signOut();
}

class UnconfiguredPrincipalAuthGateway implements PrincipalAuthGateway {
  const UnconfiguredPrincipalAuthGateway();
  @override bool get configured=>false;
  @override Future<PrincipalAccess?> restore() async=>null;
  @override Future<PrincipalAccess> signIn(String email,String password) async=>
    throw StateError('Principal sign-in is not configured');
  @override Future<void> signOut() async {}
}

class SupabasePrincipalAuthGateway implements PrincipalAuthGateway {
  const SupabasePrincipalAuthGateway(this.client);
  final SupabaseClient client;
  @override bool get configured=>true;

  Future<PrincipalAccess> _verifiedPrincipal() async {
    final identity=await client.auth.getUser();
    final id=identity.user?.id;
    if(client.auth.currentSession==null || id==null) {
      throw StateError('Verified Principal sign-in required');
    }
    final result=await client.rpc('principal_session_context');
    if(result is! Map) throw StateError('Principal role not authorized');
    final access=PrincipalAccess.fromJson(Map<String,dynamic>.from(result));
    if(access.userId!=id) throw StateError('Principal identity mismatch');
    return access;
  }

  @override
  Future<PrincipalAccess?> restore() async {
    if(client.auth.currentSession==null) return null;
    try {
      return await _verifiedPrincipal();
    } catch (_) {
      // Owner login fallback must still be able to inspect the session;
      // do not sign out a valid non-Principal in this method.
      return null;
    }
  }

  @override
  Future<PrincipalAccess> signIn(String email,String password) async {
    if(!email.contains('@') || password.isEmpty) {
      throw const FormatException('Email and password required');
    }
    try {
      final response=await client.auth.signInWithPassword(
        email:email.trim(),password:password);
      if(response.session==null || response.user==null) {
        throw StateError('No authenticated Principal session');
      }
      return await _verifiedPrincipal();
    } catch (_) {
      // Never leave a session open after a Principal authorization failure.
      await client.auth.signOut();
      rethrow;
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}
