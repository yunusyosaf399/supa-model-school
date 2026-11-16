import 'package:supabase_flutter/supabase_flutter.dart';

/// An authorized Owner context is issued only after Supabase Auth AND DB01
/// active-profile, active-owner-role, school and campus RLS checks pass.
class OwnerAccess {
  const OwnerAccess({
    required this.userId,
    required this.displayName,
    required this.schoolId,
    required this.schoolName,
    required this.campuses,
    this.currencyCode = 'XXX',
    this.timezoneName = 'Etc/UTC',
    this.schoolRevision = 1,
    this.setupComplete = false,
    this.activeYearLabel,
    this.activeYearId,
    this.activeYearStartsOn,
    this.activeYearEndsOn,
  });

  final String userId;
  final String displayName;
  final String schoolId;
  final String schoolName;
  final String currencyCode;
  final String timezoneName;
  final int schoolRevision;
  final bool setupComplete;
  final String? activeYearLabel;
  final String? activeYearId;
  final String? activeYearStartsOn;
  final String? activeYearEndsOn;
  final List<OwnerCampus> campuses;
}

class OwnerCampus {
  const OwnerCampus({
    required this.id,
    required this.name,
    this.revision = 1,
  });
  final String id;
  final String name;
  final int revision;
}

/// A single, validated initial-setup transaction; all fields are supplied
/// explicitly by the Owner rather than inferred from demonstration data.
class OwnerInitialSetupRequest {
  const OwnerInitialSetupRequest({
    required this.schoolId,
    required this.campusId,
    required this.schoolName,
    required this.campusName,
    required this.currencyCode,
    required this.timezoneName,
    required this.yearLabel,
    required this.yearStartsOn,
    required this.yearEndsOn,
    required this.expectedSchoolRevision,
    required this.expectedCampusRevision,
  });

  final String schoolId, campusId, schoolName, campusName, currencyCode;
  final String timezoneName, yearLabel, yearStartsOn, yearEndsOn;
  final int expectedSchoolRevision, expectedCampusRevision;
}

/// Injected to keep UI tests network-free and to prevent debug mode from
/// accidentally serving as a login authorization pathway.
abstract class OwnerAuthGateway {
  bool get configured;
  Future<OwnerAccess?> restore();
  Future<OwnerAccess> signIn(String email, String password);
  Future<void> signOut();
  Future<void> sendRecovery(String email);
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<OwnerAccess> completeInitialSetup(OwnerInitialSetupRequest request);
}

class UnconfiguredOwnerAuthGateway implements OwnerAuthGateway {
  const UnconfiguredOwnerAuthGateway();

  @override
  bool get configured => false;

  @override
  Future<OwnerAccess?> restore() async => null;

  @override
  Future<OwnerAccess> signIn(String email, String password) async =>
      throw StateError('Supabase is not configured');

  @override
  Future<void> signOut() async {}

  @override
  Future<void> sendRecovery(String email) async =>
      throw StateError('Supabase is not configured');

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async =>
      throw StateError('Supabase is not configured');

  @override
  Future<OwnerAccess> completeInitialSetup(OwnerInitialSetupRequest request) async =>
      throw StateError('Supabase is not configured');
}

class SupabaseOwnerAuthGateway implements OwnerAuthGateway {
  SupabaseOwnerAuthGateway(this.client);

  final SupabaseClient client;

  @override
  bool get configured => true;

  @override
  Future<OwnerAccess?> restore() async {
    if (client.auth.currentSession == null) return null;
    try {
      final user = await client.auth.getUser();
      final id = user.user?.id;
      if (id == null) throw StateError('Missing Auth user');
      return await _loadVerifiedOwner(id);
    } catch (_) {
      await client.auth.signOut();
      return null;
    }
  }

  @override
  Future<OwnerAccess> signIn(String email, String password) async {
    if (!email.contains('@') || password.isEmpty) {
      throw const FormatException('Email and password required');
    }

    try {
      final response = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null || response.session == null) {
        throw StateError('No authenticated session');
      }
      return await _loadVerifiedOwner(response.user!.id);
    } catch (_) {
      // Never retain an authenticated session without an active Owner role.
      await client.auth.signOut();
      rethrow;
    }
  }

  Future<OwnerAccess> _loadVerifiedOwner(String id) async {
    final verifiedUser = await client.auth.getUser();
    if (verifiedUser.user?.id != id) {
      throw StateError('User identity validation failed');
    }
    final profile = await client
        .from('user_profiles')
        .select('user_id,display_name,is_active')
        .eq('user_id', id)
        .maybeSingle();
    if (profile == null || profile['is_active'] != true) {
      throw StateError('Account is not active');
    }

    final roles = await client
        .from('user_roles')
        .select('school_id,role,campus_id,is_active')
        .eq('user_id', id)
        .eq('role', 'owner')
        .eq('is_active', true)
        .isFilter('campus_id', null);
    if (roles.length != 1) {
      throw StateError('No unique authorized Owner membership');
    }
    final schoolId = roles.single['school_id'] as String;
    final school = await client
        .from('schools')
        .select('id,name,status,currency_code,timezone_name,revision')
        .eq('id', schoolId)
        .maybeSingle();
    if (school == null || school['status'] != 'active') {
      throw StateError('School is not active');
    }
    final campuses = await client
        .from('campuses')
        .select('id,name,revision')
        .eq('school_id', schoolId)
        .eq('is_active', true)
        .order('name');
    if (campuses.isEmpty) {
      throw StateError('School has no active campus');
    }

    // These tables are owner-readable through DB01 RLS.
    final initialSettings = await client
        .from('school_settings')
        .select('setting_value')
        .eq('school_id', schoolId)
        .eq('setting_key', 'initial_setup')
        .maybeSingle();
    final setup = initialSettings?['setting_value'];
    final complete = setup is Map<String, dynamic> &&
        setup['status'] == 'complete';
    final year = await client
        .from('academic_years')
        .select('id,label,starts_on,ends_on')
        .eq('school_id', schoolId)
        .eq('is_active', true)
        .maybeSingle();

    return OwnerAccess(
      userId: id,
      displayName: profile['display_name'] as String,
      schoolId: schoolId,
      schoolName: school['name'] as String,
      currencyCode: school['currency_code'] as String,
      timezoneName: school['timezone_name'] as String,
      schoolRevision: (school['revision'] as num).toInt(),
      setupComplete: complete && year != null,
      activeYearLabel: year?['label'] as String?,
      activeYearId: year?['id'] as String?,
      activeYearStartsOn: year?['starts_on'] as String?,
      activeYearEndsOn: year?['ends_on'] as String?,
      campuses: [
        for (final item in campuses)
          OwnerCampus(
            id: item['id'] as String,
            name: item['name'] as String,
            revision: (item['revision'] as num).toInt(),
          ),
      ],
    );
  }

  @override
  Future<OwnerAccess> completeInitialSetup(
      OwnerInitialSetupRequest request) async {
    final identity = await client.auth.getUser();
    final id = identity.user?.id;
    if (id == null || client.auth.currentSession == null) {
      throw StateError('Authentication required');
    }
    final before = await _loadVerifiedOwner(id);
    if (before.setupComplete || before.schoolId != request.schoolId ||
        !before.campuses.any((campus) => campus.id == request.campusId)) {
      throw StateError('Invalid Owner school setup request');
    }

    // No client-side direct update to DB01 tables is permitted.
    await client.rpc('owner_complete_initial_setup', params: {
      'p_school_id': request.schoolId,
      'p_campus_id': request.campusId,
      'p_school_name': request.schoolName.trim(),
      'p_campus_name': request.campusName.trim(),
      'p_currency_code': request.currencyCode.trim().toUpperCase(),
      'p_timezone_name': request.timezoneName.trim(),
      'p_year_label': request.yearLabel.trim(),
      'p_year_starts_on': request.yearStartsOn,
      'p_year_ends_on': request.yearEndsOn,
      'p_expected_school_revision': request.expectedSchoolRevision,
      'p_expected_campus_revision': request.expectedCampusRevision,
    });
    final updated = await _loadVerifiedOwner(id);
    if (!updated.setupComplete) {
      throw StateError('Setup save was not confirmed by Supabase');
    }
    return updated;
  }

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    if (currentPassword.isEmpty || newPassword.length < 12 ||
        currentPassword == newPassword) {
      throw const FormatException('Use a distinct password of 12+ characters');
    }
    final before = await client.auth.getUser();
    final userId = before.user?.id;
    if (userId == null || client.auth.currentSession == null) {
      throw StateError('No active session');
    }
    // Verify Owner access again, not just an earlier client-side screen flag.
    await _loadVerifiedOwner(userId);
    final result = await client.auth.updateUser(UserAttributes(
      password: newPassword,
      currentPassword: currentPassword,
    ));
    if (result.user?.id != userId) {
      throw StateError('Password update could not be confirmed');
    }
    // Force re-login using the updated credentials.
    await client.auth.signOut();
  }

  @override
  Future<void> sendRecovery(String email) async {
    // Configure an approved recovery redirect and in-app password-update
    // route before enabling this in an installed release.
    throw UnimplementedError('Password recovery redirect is not configured');
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut();
  }
}
