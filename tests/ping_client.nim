import std/os

import asyncdispatch
import ws

proc checkPong(url: string) {.async.} =
  let socket = await newWebSocket(url)
  try:
    let (initialOpcode, _) = await socket.receivePacket()
    doAssert initialOpcode == Text
    await socket.ping("quest-certification-ping")
    for _ in 0 ..< 20:
      let packet = socket.receivePacket()
      doAssert await withTimeout(packet, 2000), "WebSocket Pong timed out"
      let (opcode, payload) = packet.read()
      if opcode == Pong:
        doAssert payload == "quest-certification-ping"
        echo "Quest WebSocket Pong proof passed: ", url
        return
    doAssert false, "WebSocket Pong missing"
  finally:
    socket.hangup()

if paramCount() != 1:
  quit("expected websocket URL", 2)
waitFor checkPong(paramStr(1))
