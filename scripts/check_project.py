from pathlib import Path
import csv

root = Path(__file__).resolve().parents[1]
required = [
    'README.md', 'pubspec.yaml', 'lib/main.dart',
    'docs/01_SRS.md', 'planning/tasks.csv', 'supabase/README.md'
]
missing = [p for p in required if not (root / p).is_file()]
if missing:
    raise SystemExit(f'Missing required project files: {missing}')
with (root / 'planning/tasks.csv').open(encoding='utf-8', newline='') as f:
    tasks = list(csv.DictReader(f))
ids = [row['id'] for row in tasks]
assert len(tasks) == 114, f'Expected 114 tasks, found {len(tasks)}'
assert len(set(ids)) == len(ids), 'Duplicate task IDs'
statuses = {'DONE', 'TODO', 'BLOCKED', 'IN_PROGRESS', 'FAILED'}
assert all(row['status'] in statuses for row in tasks), 'Unknown task status'
print(f'OK: {len(tasks)} tasks, {sum(t["status"]=="DONE" for t in tasks)} completed, {len(missing)} missing required files')
