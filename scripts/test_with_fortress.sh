#!/usr/bin/env bash
set -euo pipefail

quest_root=$(cd "$(dirname "$0")/.." && pwd)
fortress_root=${TRIBAL_FORTRESS_PATH:-"$quest_root/../coworld-tribal-fortress"}

if [[ ! -f "$fortress_root/src/tribal_fortress_engine.nim" ]]; then
  echo "missing $fortress_root/src/tribal_fortress_engine.nim" >&2
  exit 1
fi

if [[ "${REQUIRE_LOCKED_FORTRESS:-0}" == "1" ]]; then
  expected=$(tr -d '\n' <"$quest_root/fortress.lock")
  actual=$(git -C "$fortress_root" rev-parse HEAD)
  if [[ "$actual" != "$expected" ]]; then
    echo "Fortress checkout is $actual, expected locked commit $expected" >&2
    exit 1
  fi
fi

mkdir -p "$quest_root/out"
nim c \
  -d:release \
  --path:"$quest_root/src" \
  --path:"$fortress_root/src" \
  -o:"$quest_root/out/tribal_quest" \
  "$quest_root/src/tribal_quest.nim"
nim c \
  -d:release \
  --path:"$quest_root/src" \
  -o:"$quest_root/out/tribal_quest_adventurer" \
  "$quest_root/players/adventurer/adventurer.nim"
nim r \
  -d:release \
  --path:"$quest_root/src" \
  --path:"$fortress_root/src" \
  "$quest_root/tests/fortress_integration.nim"

smoke_root=$(mktemp -d)
trap 'rm -rf "$smoke_root"' EXIT
scores_path="$smoke_root/results.json"
replay_path="$smoke_root/replay.json"
config='{"mode":"quest","tokens":["q0","q1","q2","q3","q4","q5","q6","q7"],"players":[{"name":"p0"},{"name":"p1"},{"name":"p2"},{"name":"p3"},{"name":"p4"},{"name":"p5"},{"name":"p6"},{"name":"p7"}],"max_steps":1,"seed":726896,"steps_per_second":1000,"player_connect_timeout_seconds":0,"num_agents":8,"team_count":8,"victory_condition":0}'
"$quest_root/out/tribal_quest" \
  --address:127.0.0.1 \
  --port:18181 \
  --fortress-data-dir:"$fortress_root/data" \
  --save-scores:"$scores_path" \
  --save-replay:"$replay_path" \
  --config:"$config"

python3 - "$scores_path" "$replay_path" <<'PY'
import json
import sys

scores = json.load(open(sys.argv[1], encoding="utf-8"))
replay = json.load(open(sys.argv[2], encoding="utf-8"))
assert scores["mode"] == "quest"
assert scores["steps"] == 1
assert scores["truncation_reason"] == "max_steps"
assert len(scores["scores"]) == 8
assert len(scores["names"]) == 8
assert len(scores["survival_ticks"]) == 8
assert replay == {
    "mode": "quest",
    "steps": 1,
    "truncation_reason": "max_steps",
}
print("Quest shared-host smoke passed")
PY
