# Tribal Quest

Tribal Quest is the adventurer component and Quest league mode of the canonical
`tribal_fortress` Coworld. Fortress and Quest ship in one immutable game image
and use the same `FortressEngine` world simulation. The two leagues select the
matching `fortress-N-town` or `quest-N-adventurer` variant for an active roster
of two through eight entrants.

This repository is deliberately not a separately uploadable Coworld. It has no
root `coworld_manifest.json`. The canonical manifest, image, certification, and
upload workflow live in
[`Metta-AI/coworld-tribal-fortress`](https://github.com/Metta-AI/coworld-tribal-fortress).
[`quest_component.json`](quest_component.json) is the checked, machine-readable
interface Fortress consumes when assembling that artifact.

## Runtime ownership

- Fortress owns one authoritative `FortressEngine` and all world simulation.
- Quest mounts `/player` adventurer controls onto that engine.
- Quest exposes a read-only global spectator at `/client/global` backed by the
  `/global` websocket; it never owns or advances a second simulation.
- The shared host submits town and adventurer inputs, steps the engine once,
  then renders both surfaces from the same post-step state.
- `src/tribal_quest.nim` is also a useful Quest-only development host. It starts
  the same Fortress engine because there is no surrounding host in that case.
- There is no Quest simulation fallback, production Python bridge, runtime
  checkout path, or second world.

The production entrypoint accepts the shared snake-case game config:

```json
{
  "mode": "quest",
  "tokens": ["q0", "q1"],
  "players": [
    {"name": "p0"}, {"name": "p1"}
  ],
  "max_steps": 18000,
  "seed": 726896,
  "steps_per_second": 10,
  "player_connect_timeout_seconds": 180,
  "num_agents": 2,
  "team_count": 2
}
```

It emits a result sized to the active two-to-eight-seat roster containing `mode`, `scores`, `steps`,
`truncation_reason`, `names`, `survival_ticks`, and `explored_tiles`. Scores
combine alive survival ticks with unique tiles visited. Quest intentionally
accepts and ignores the shared `victory_condition` field, which applies only
to Fortress mode.

## Develop and test

Use a sibling Fortress checkout:

```sh
nimby use 2.2.10
nimby sync -g nimby.lock
python3 scripts/validate_component.py
python3 scripts/validate_lock.py
nim r --path:src tests/tests.nim
python3 tests/test_http_artifacts.py
TRIBAL_FORTRESS_PATH=${TRIBAL_FORTRESS_PATH:-$(pwd)/../coworld-tribal-fortress}
bash scripts/test_with_fortress.sh
```

The integration script compiles the Quest host and bundled adventurer, runs a
typed engine/render test, starts a one-step shared-contract episode, and checks
the differentiated scoring and result envelopes. It then runs a live episode
that proves `/client/global`, the immediate `view.init`, an authoritative
post-step `view.update`, and a connected adventurer's state. Finally it starts
the binary in Coworld replay-load mode and verifies `/healthz`,
`/client/replay`, and a real `/replay` websocket message. The canonical
exact-revision integration and
image gate runs in Fortress CI after Fortress pins a public Quest commit.
Quest's public CI validates the descriptor, protocol, HTTP artifact I/O, and
formatting without attempting to read the private Fortress repo.
Both CI and the development image install Quest's complete direct/transitive
dependency graph from exact commits in `nimby.lock`; neither runs a floating
`nimble refresh` or `nimble install`.

Build the development image with the local sibling Fortress checkout as a
BuildKit named context:

```sh
docker build \
  --build-context fortress=../coworld-tribal-fortress \
  -t tribal-quest-component:dev .
```

For an interactive local run:

```sh
TRIBAL_FORTRESS_PATH=${TRIBAL_FORTRESS_PATH:-$(pwd)/../coworld-tribal-fortress}
nim c --path:src --path:$TRIBAL_FORTRESS_PATH/src \
  -o:out/tribal_quest src/tribal_quest.nim
./out/tribal_quest --address:127.0.0.1 --port:2000 \
  --fortress-data-dir:$TRIBAL_FORTRESS_PATH/data --max-steps:18000 \
  --steps-per-second:10
```

Then open
`http://127.0.0.1:2000/client/player?slot=0&name=human&reconnect=2`,
watch the read-only global view at
`http://127.0.0.1:2000/client/global`,
or run the bundled pilot:

```sh
nim c --path:src -o:out/tribal_quest_adventurer \
  players/adventurer/adventurer.nim
./out/tribal_quest_adventurer \
  --address:127.0.0.1 --port:2000 --slot:0 --ticks:80
```

The sprite client uses a 21 by 21 adventurer-centered crop at 16 pixels per
tile. Missing art renders as labeled placeholders rather than a blank frame.
The global websocket sends a JSON `view.init` immediately, followed by
`view.update` after each authoritative engine step. Both use protocol
`tribal-quest-global-v1` and contain one adventurer snapshot per active entrant plus
scores, survival ticks, and explored-tile counts.

## Project layout

- `src/tribal_quest.nim`: shared-config entrypoint and development host.
- `src/tribal_quest/player_surface.nim`: mountable HTTP/WebSocket surface.
- `src/tribal_quest/fortress_engine.nim`: typed Fortress contract adapter.
- `src/tribal_quest/gridworld_sprites.nim`: shared-world sprite rendering.
- `players/adventurer/adventurer.nim`: bundled sprite-protocol pilot.
- `quest_component.json`: non-uploadable shared artifact contract.
- `tests/`: protocol, descriptor, engine, rendering, and episode proof.
