import std/[json, strutils]

import mummy

const ReplayClientHtml = """<!doctype html>
<html><head><meta charset="utf-8"><title>Tribal Quest Replay</title></head>
<body><h1>Tribal Quest Replay</h1><pre id="replay">connecting</pre>
<script>
const out=document.getElementById('replay');
const ws=new WebSocket(`${location.protocol==='https:'?'wss':'ws'}://${location.host}/replay`);
ws.onmessage=e=>{const value=JSON.parse(e.data);out.textContent=JSON.stringify(value,null,2)};
ws.onerror=()=>{out.textContent='replay connection failed'};
</script></body></html>"""

var replayPayload: string

proc textHeaders(contentType = "text/plain; charset=utf-8"): HttpHeaders =
  result["Content-Type"] = contentType

proc headerContainsToken(request: Request, key, token: string): bool =
  let expected = token.toLowerAscii()
  for (headerKey, headerValue) in request.headers:
    if cmpIgnoreCase(headerKey, key) == 0:
      for part in headerValue.split(','):
        if part.strip().toLowerAscii() == expected:
          return true

proc isWebSocketUpgrade(request: Request): bool =
  request.headerContainsToken("Connection", "Upgrade") and
    request.headerContainsToken("Upgrade", "websocket")

proc replayHttpHandler(request: Request) {.gcsafe.} =
  if request.path == "/healthz" and request.httpMethod == "GET":
    request.respond(200, textHeaders(), "ok\n")
  elif request.path == "/client/replay" and request.httpMethod == "GET":
    request.respond(
      200,
      textHeaders("text/html; charset=utf-8"),
      ReplayClientHtml
    )
  elif request.path == "/replay" and request.httpMethod == "GET":
    if not request.isWebSocketUpgrade():
      var headers = textHeaders()
      headers["Connection"] = "Upgrade"
      headers["Upgrade"] = "websocket"
      request.respond(426, headers, "websocket upgrade required\n")
    else:
      discard request.upgradeToWebSocket()
  elif request.path == "/" and request.httpMethod == "GET":
    request.respond(200, textHeaders(), "Tribal Quest replay server\n")
  else:
    request.respond(404, textHeaders(), "not found\n")

proc replayWebSocketHandler(
  websocket: WebSocket,
  event: WebSocketEvent,
  message: Message
) {.gcsafe.} =
  discard message
  if event == OpenEvent:
    {.gcsafe.}:
      websocket.send(replayPayload, TextMessage)

proc runQuestReplaySurface*(payload: JsonNode, address: string, port: int) =
  if payload.kind != JObject or payload{"format"}.getStr() !=
      "tribal-quest-replay-v1":
    raise newException(ValueError, "invalid Tribal Quest replay payload")
  replayPayload = $payload
  let server = newServer(
    replayHttpHandler,
    replayWebSocketHandler,
    workerThreads = 2,
    tcpNoDelay = true
  )
  echo "Tribal Quest replay surface listening on http://", address, ":", port
  server.serve(Port(port), address)
