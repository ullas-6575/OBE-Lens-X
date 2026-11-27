"""Parallel saves against the disposable database from test_workflow_db.sh."""
from concurrent.futures import ThreadPoolExecutor
import json
import subprocess
import sys
from threading import Barrier


def main():
    socket = sys.argv[1]

    def query(sql):
        result = subprocess.run(
            ['psql', '-X', '-qAt', '-h', socket, '-d', 'postgres',
             '-v', 'ON_ERROR_STOP=1', '-c', sql],
            capture_output=True, text=True, check=True, timeout=15)
        return json.loads(result.stdout.strip().splitlines()[-1])

    # Make the first write overlap the second request deterministically.
    query("""
        create function private.pause_test_save() returns trigger
        language plpgsql as $$ begin
          if new.roll_no like 'RACE%' then perform pg_sleep(0.2); end if;
          return new;
        end $$;
        create trigger pause_test_save before insert or update on public.results
          for each row execute function private.pause_test_save();
        select 'true'::jsonb;
    """)

    def save(teacher, token, roll, group, mark, previous=None):
        question = '1' if group == '1-4' else '5'
        revision = (f", '{previous['id']}'::uuid, {previous['revision']}"
                    if previous else '')
        return query(f"""
            set role authenticated;
            select set_config('request.jwt.claim.sub',
              '00000000-0000-4000-8000-{teacher:012d}', true);
            select set_config('request.jwt.claims', '{{}}', true);
            select public.save_question_group(
              '30000000-0000-4000-8000-000000000001', '{roll}',
              '50000000-0000-4000-8000-{token:012d}', '{group}',
              jsonb_set((select marks from public.results
                where roll_no='ROLL001' and table_type='{group}'),
                '{{{question},a}}', '"{mark}"'), 1 {revision});
        """)

    def parallel(first, second):
        barrier = Barrier(2)

        def run(args):
            barrier.wait(timeout=5)
            return save(*args)

        with ThreadPoolExecutor(max_workers=2) as pool:
            return list(pool.map(run, (first, second)))

    responses = parallel((2, 1, 'RACE001', '1-4', 1),
                         (3, 2, 'RACE001', '1-4', 2))
    assert sorted(row['status'] for row in responses) == ['conflict', 'saved']
    assert query("select count(*) from public.results where roll_no='RACE001'") == 1

    responses = parallel((2, 3, 'RACE002', '1-4', 3),
                         (3, 4, 'RACE002', '5-8', 4))
    assert all(row['status'] == 'saved' for row in responses)
    assert query("select sum(grand_total) from public.results where roll_no='RACE002'") == 7

    previous = query("select jsonb_build_object('id', id, 'revision', revision) "
                     "from public.results where roll_no='RACE001'")
    responses = parallel((2, 5, 'RACE001', '1-4', 6, previous),
                         (3, 6, 'RACE001', '1-4', 7, previous))
    assert sorted(row['status'] for row in responses) == ['conflict', 'saved']
    assert query("select revision from public.results where roll_no='RACE001'") == 2
    print('PASS: parallel uploads preserve different groups and require fresh confirmation for duplicates.')


if __name__ == '__main__':
    main()
