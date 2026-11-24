#! /bin/sh
# Smoke test the sqlite3 shell for the features Fluffy enables at
# configure time: FTS4, FTS5 and JSON.
#
# Usage: $(SHELL) test/sqlite3-smoke.sh ./sqlite3

sqlite3=${1:?usage: $0 path/to/sqlite3}

out="$("$sqlite3" :memory: \
    "CREATE VIRTUAL TABLE t USING fts5(x);
     CREATE VIRTUAL TABLE t4 USING fts4(x);
     INSERT INTO t VALUES ('fluffy glob');
     INSERT INTO t4 VALUES ('fluffy fts4');
     SELECT x FROM t WHERE t MATCH 'fluffy';
     SELECT x FROM t4 WHERE t4 MATCH 'fluffy';
     SELECT json_extract('{\"k\":\"ok\"}', '\$.k');" 2>&1)"
want='fluffy glob
fluffy fts4
ok'
if test "$out" = "$want"
then
    echo "PASS: sqlite3 fts5/fts4/json"
else
    echo "FAIL: sqlite3 fts5/fts4/json"
    echo "got:"
    echo "$out"
    exit 1
fi
