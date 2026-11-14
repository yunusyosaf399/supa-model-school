# Developer setup runbook

Private GitHub repository: https://github.com/yunusyosaf399/supa-model-school
Supabase dashboard: https://supabase.com/dashboard/project/uebzvfzpbqqttbqyxxos

## Flutter on Windows
1. Install Flutter, Git, Android SDK and Visual Studio C++ desktop components.
2. `flutter doctor -v`
3. In cloned repo: `flutter create --project-name supa_model_school --org com.supamodelschool --platforms windows,android .`
4. Review diff. `flutter pub get`, `flutter analyze`, `flutter test`.
5. Pin dependencies and commit generated `pubspec.lock` after compatible versions are tested.
6. Use public Supabase project URL and publishable key only, via secure build-time configuration. No service-role/secret key in Flutter.

## Supabase schema workflow
1. Read current Supabase docs/changelog; `supabase --help` and check CLI version.
2. `supabase init` if required, `supabase login`, `supabase link --project-ref uebzvfzpbqqttbqyxxos`.
3. Review draft SQL under supabase/drafts. Generate a real CLI migration: `supabase migration new db01_foundation`; copy approved SQL into generated file.
4. Apply locally, run schema checks, negative RLS tests with multiple users and a schema adviser before deploy.
5. Deploy only approved versioned migrations in dependency order; verify after deployment.

**Do not deploy the drafts to the live project until reviewed and tested.**