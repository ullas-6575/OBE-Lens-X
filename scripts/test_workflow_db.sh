#!/usr/bin/env bash
# Disposable local PostgreSQL verification; never connects to the hosted project.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
pg_bin="$(pg_config --bindir)"
test_dir="$(mktemp -d /tmp/obelens-db-test.XXXXXX)"
cleanup() {
  "$pg_bin/pg_ctl" -D "$test_dir/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf -- "$test_dir"
}
trap cleanup EXIT
"$pg_bin/initdb" -D "$test_dir/data" -A trust --no-locale >/dev/null
"$pg_bin/pg_ctl" -D "$test_dir/data" -l "$test_dir/postgres.log" \
  -o "-k $test_dir -c listen_addresses=''" start >/dev/null
files=(-f "$project_dir/supabase/tests/auth_stub.sql")
for migration in "$project_dir"/supabase/migrations/*.sql; do
  files+=(-f "$migration")
done
psql -X -h "$test_dir" -d postgres -v ON_ERROR_STOP=1 \
  "${files[@]}" -v keep_shared_fixtures=1 \
  -f "$project_dir/supabase/tests/workflow.sql" \
  -f "$project_dir/supabase/tests/shared_marks.sql" \
  -f "$project_dir/supabase/tests/selected_questions.sql"
python3 "$project_dir/supabase/tests/shared_marks_concurrency.py" "$test_dir"
