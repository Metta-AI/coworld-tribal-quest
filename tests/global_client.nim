import std/[json, os]

import asyncdispatch
import ws

proc requireFixedEight(frame: JsonNode) =
  doAssert frame["adventurers"].len == 8
  doAssert frame["scores"].len == 8
  doAssert frame["survival_ticks"].len == 8
  doAssert frame["explored_tiles"].len == 8

proc checkGlobal(url: string) {.async.} =
  let socket = await newWebSocket(url)
  try:
    let (initOpcode, initPayload) = await socket.receivePacket()
    doAssert initOpcode == Text
    let initFrame = parseJson(initPayload)
    doAssert initFrame["type"].getStr() == "view.init"
    doAssert initFrame["protocol"].getStr() == "tribal-quest-global-v1"
    doAssert initFrame["mode"].getStr() == "quest"
    doAssert initFrame["status"]["step"].getInt() == 0
    initFrame.requireFixedEight()

    var sawAuthoritativeUpdate = false
    for _ in 0 ..< 8:
      let (opcode, payload) = await socket.receivePacket()
      doAssert opcode == Text
      let frame = parseJson(payload)
      if frame["type"].getStr() != "view.update":
        continue
      frame.requireFixedEight()
      let adventurer = frame["adventurers"][0]
      if frame["status"]["step"].getInt() >= 1 and
          frame["status"]["connected_players"].getInt() >= 1 and
          adventurer["connected"].getBool() and adventurer["alive"].getBool():
        doAssert adventurer["x"].getInt() >= 0
        doAssert adventurer["y"].getInt() >= 0
        doAssert adventurer["hp"].getInt() > 0
        doAssert adventurer["survival_ticks"].getInt() >= 1
        sawAuthoritativeUpdate = true
        break
    doAssert sawAuthoritativeUpdate
    echo "Quest global websocket proof passed"
  finally:
    socket.hangup()

if paramCount() != 1:
  quit("expected global websocket URL", 2)
waitFor checkGlobal(paramStr(1))
