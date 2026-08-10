import std/[json, os]

import asyncdispatch
import ws
import tribal_quest/contract

proc checkReplay(url: string) {.async.} =
  let socket = await newWebSocket(url)
  try:
    let (opcode, payload) = await socket.receivePacket()
    doAssert opcode == Text
    let replay = parseJson(payload)
    doAssert replay["format"].getStr() == "tribal-quest-replay-v1"
    doAssert replay["mode"].getStr() == "quest"
    let playerCount = replay["scores"].len
    doAssert playerCount in QuestLeagueMinPlayerCount .. QuestLeagueMaxPlayerCount
    doAssert replay["survival_ticks"].len == playerCount
    doAssert replay["explored_tiles"].len == playerCount
    echo "Quest replay websocket proof passed"
  finally:
    socket.hangup()

if paramCount() != 1:
  quit("expected replay websocket URL", 2)
waitFor checkReplay(paramStr(1))
