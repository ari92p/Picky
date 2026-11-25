#!/bin/bash
# Check everything that can be checked without the game.
#   tools/check_all.sh          everything
#   tools/check_all.sh --fast   without the mutation test
# 1. syntax of every Lua file   2. no write to a game global (taint)   3. all tests   4. three runs in a row (must be identical)
# 5. random orders (no test may depend on another one)   6. mutation test (every deliberate bug must be noticed)
cd "$(dirname "$0")/.." || exit 2
command -v luajit >/dev/null || { echo "luajit is missing: brew install luajit"; exit 2; }
fail=0
step() { printf "%-42s" "$1"; }

step "1. Syntax of all files"
bad=0
for f in *.lua; do
  luajit -e "assert(loadfile('$f'))" 2>/tmp/picky-syntax.txt || { echo; echo "   $f: $(cat /tmp/picky-syntax.txt)"; bad=1; }
done
[ $bad = 0 ] && echo "ok" || fail=1

step "2. No game global is written (taint)"
out=$(python3 tools/check_taint.py 2>&1); code=$?
echo "$out" | head -1
[ $code = 0 ] || { echo "$out" | tail -n +2 | sed 's/^/   /'; fail=1; }

step "3. All tests"
out=$(luajit tools/run_tests.lua 2>&1); code=$?
echo "$out" | head -1
[ $code = 0 ] || { echo "$out" | tail -n +2 | sed 's/^/   /'; fail=1; }

step "4. Three runs in a row (identical)"
out=$(luajit tools/run_tests.lua --repeat 3 2>&1); code=$?
echo "$out" | head -1
[ $code = 0 ] || { echo "$out" | tail -n +2 | sed 's/^/   /'; fail=1; }

step "5. Random order (10 runs)"
bad=0
for seed in 1 2 3 4 5 6 7 8 9 10; do
  out=$(luajit tools/run_tests.lua --seed $seed 2>&1) || { echo; echo "   seed $seed:"; echo "$out" | sed 's/^/   /'; bad=1; }
done
[ $bad = 0 ] && echo "ok (10 different orders)" || fail=1

if [ "$1" != "--fast" ]; then
  step "6. Mutation test"
  out=$(python3 tools/mutate.py 2>&1); code=$?
  echo "$out" | tail -1
  [ $code = 0 ] || { echo "$out" | grep -E "SURVIVED|STALE" | sed 's/^/   /'; fail=1; }
fi

echo
echo "Line coverage (information only, not a pass/fail check):"
luajit tools/run_tests.lua --coverage 2>&1 | sed -n '/^Line coverage/,$p' | tail -n +2

echo
[ $fail = 0 ] && echo "ALL GREEN" || echo "FAILURES (see above)"
exit $fail
