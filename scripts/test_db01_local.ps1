# DB01 local PostgreSQL RLS test runner. No cloud deployment.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $env:LOCAL_DB_URL) {
  throw 'Set LOCAL_DB_URL to your LOCAL Supabase PostgreSQL URL first.'
}
$uri = [System.Uri]$env:LOCAL_DB_URL
if ($uri.Host -notin @('localhost', '127.0.0.1', '::1')) {
  throw 'Refusing to run fixtures against a non-local database hostname.'
}
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
  throw 'psql is not installed or not in PATH.'
}
$testFile = Join-Path $root 'supabase/tests/DB01_RLS_INTEGRATION.sql'
if (-not (Test-Path $testFile)) { throw "Missing test SQL: $testFile" }
Write-Host 'Running DB01 two-campus RLS assertions against local PostgreSQL...'
& psql -X -v ON_ERROR_STOP=1 -d $env:LOCAL_DB_URL -f $testFile
if ($LASTEXITCODE -ne 0) { throw "DB01 SQL test failed (psql exit code $LASTEXITCODE)" }
Write-Host 'DB01 fixture transaction completed successfully and rolled back.'
