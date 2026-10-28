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
psql -X -h "$test_dir" -d postgres -v ON_ERROR_STOP=1 \
  -f "$project_dir/supabase/tests/auth_stub.sql" \
  -f "$project_dir/supabase/migrations/20261013200000_create_results.sql" \
  -f "$project_dir/supabase/migrations/20261024164156_academic_workflow.sql" \
  -f "$project_dir/supabase/tests/workflow.sql"
