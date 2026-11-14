# DB01 — structural verification

A static script on main will check that every public table in the DB01 SQL draft has an RLS ENABLE statement and that role/settings policy definitions default to deny.

Static checks cannot validate live PostgreSQL syntax, security-definer behavior or the actual campus permissions. Run the local migration and manual RLS matrix before marking DB01 complete.

At this stage the draft is not deployed.