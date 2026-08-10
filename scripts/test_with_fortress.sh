#!/usr/bin/env bash
set -euo pipefail

quest_root=$(cd "$(dirname "$0")/.." && pwd)
fortress_root=${TRIBAL_FORTRESS_PATH:-"$quest_root/../coworld-tribal-fortress"}

if [[ ! -f "$fortress_root/src/tribal_fortress_engine.nim" ]]; then
  echo "missing $fortress_root/src/tribal_fortress_engine.nim" >&2
  exit 1
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
nim c \
  -d:release \
  --path:"$quest_root/src" \
  -o:"$quest_root/out/tribal_quest_global_client" \
  "$quest_root/tests/global_client.nim"
nim r \
  -d:release \
  --path:"$quest_root/src" \
  --path:"$fortress_root/src" \
  "$quest_root/tests/fortress_integration.nim"

smoke_root=$(mktemp -d)
replay_pid=""
global_pid=""
global_client_pid=""
cleanup() {
  if [[ -n "$global_client_pid" ]]; then
    kill "$global_client_pid" 2>/dev/null || true
    wait "$global_client_pid" 2>/dev/null || true
  fi
  if [[ -n "$global_pid" ]]; then
    kill "$global_pid" 2>/dev/null || true
    wait "$global_pid" 2>/dev/null || true
  fi
  if [[ -n "$replay_pid" ]]; then
    kill "$replay_pid" 2>/dev/null || true
    wait "$replay_pid" 2>/dev/null || true
  fi
  rm -rf "$smoke_root"
}
trap cleanup EXIT
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
assert len(scores["explored_tiles"]) == 8
assert replay["format"] == "tribal-quest-replay-v1"
for field in (
    "mode",
    "scores",
    "steps",
    "truncation_reason",
    "names",
    "survival_ticks",
    "explored_tiles",
):
    assert replay[field] == scores[field]
print("Quest shared-host smoke passed")
PY

global_scores_path="$smoke_root/global-results.json"
global_replay_path="$smoke_root/global-replay.json"
global_config='{"mode":"quest","tokens":["q0","q1","q2","q3","q4","q5","q6","q7"],"players":[{"name":"p0"},{"name":"p1"},{"name":"p2"},{"name":"p3"},{"name":"p4"},{"name":"p5"},{"name":"p6"},{"name":"p7"}],"max_steps":4,"seed":726896,"steps_per_second":20,"player_connect_timeout_seconds":2,"num_agents":8,"team_count":8,"victory_condition":0}'
"$quest_root/out/tribal_quest" \
  --address:127.0.0.1 \
  --port:18183 \
  --fortress-data-dir:"$fortress_root/data" \
  --save-scores:"$global_scores_path" \
  --save-replay:"$global_replay_path" \
  --config:"$global_config" >"$smoke_root/global-server.log" 2>&1 &
global_pid=$!
for _ in {1..400}; do
  if curl -fsS http://127.0.0.1:18183/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done
curl -fsS http://127.0.0.1:18183/healthz >/dev/null
curl -fsS http://127.0.0.1:18183/client/global | grep -q "Tribal Quest Global View"
"$quest_root/out/tribal_quest_global_client" \
  ws://127.0.0.1:18183/global >"$smoke_root/global-client.log" 2>&1 &
global_client_pid=$!
"$quest_root/out/tribal_quest_adventurer" \
  --address:127.0.0.1 \
  --port:18183 \
  --slot:0 \
  --token:q0 \
  --ticks:1
wait "$global_client_pid"
global_client_pid=""
wait "$global_pid"
global_pid=""
python3 - "$global_scores_path" "$global_replay_path" <<'PY'
import json
import sys

scores = json.load(open(sys.argv[1], encoding="utf-8"))
replay = json.load(open(sys.argv[2], encoding="utf-8"))
assert scores["steps"] == 4
assert scores["survival_ticks"][0] >= 1
assert scores["explored_tiles"][0] >= 1
assert scores["scores"][0] > 0
assert replay["scores"] == scores["scores"]
print("Quest live global-view episode proof passed")
PY

COGAME_LOAD_REPLAY_URI="file://$replay_path" \
COGAME_HOST=127.0.0.1 \
COGAME_PORT=18182 \
  "$quest_root/out/tribal_quest" >"$smoke_root/replay-server.log" 2>&1 &
replay_pid=$!
for _ in {1..100}; do
  if curl -fsS http://127.0.0.1:18182/healthz >/dev/null; then
    break
  fi
  sleep 0.05
done
curl -fsS http://127.0.0.1:18182/healthz | python3 -c \
  'import json,sys; assert json.load(sys.stdin) == {"ready": True}'
curl -fsS http://127.0.0.1:18182/client/replay | grep -q "Tribal Quest Replay"
nim r \
  -d:release \
  --path:"$quest_root/src" \
  "$quest_root/tests/replay_client.nim" \
  ws://127.0.0.1:18182/replay
