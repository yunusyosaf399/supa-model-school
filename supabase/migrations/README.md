# Version-controlled migrations

Do not manually invent timestamped CLI migration filenames. First run `supabase migration new db01_foundation` in a verified local CLI environment, then paste/review `supabase/drafts/DB01_foundation.sql` into the generated migration. Repeat for DB02 after DB01 is tested. Do not automatically run draft SQL against the live project.