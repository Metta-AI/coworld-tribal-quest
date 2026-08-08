import std/[json, os]

import tribal_quest/coworld_io

if paramCount() != 2:
  quit("expected results and replay URLs", 2)

putEnv("COGAME_RESULTS_METHOD", "PUT")
putEnv("COGAME_SAVE_REPLAY_METHOD", "POST")
writeCoworldJson(
  paramStr(1),
  %*{"mode": "quest", "scores": [1, 2, 3, 4, 5, 6, 7, 8]},
  "COGAME_RESULTS_METHOD"
)
writeCoworldJson(
  paramStr(2),
  %*{"mode": "quest", "steps": 3},
  "COGAME_SAVE_REPLAY_METHOD"
)
