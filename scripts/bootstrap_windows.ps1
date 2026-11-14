# Run on Windows after installing Flutter SDK, Android SDK and Visual Studio C++ desktop workload.
$ErrorActionPreference = 'Stop'
flutter doctor -v
flutter create --project-name supa_model_school --org com.supamodelschool --platforms windows,android .
flutter pub get
flutter analyze
flutter test
Write-Host 'Review git diff and pin verified dependencies before committing generated runners.'
