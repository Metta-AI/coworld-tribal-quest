import
  std/[json, locks, monotimes, os, strutils, tables, times],
  mummy,
  bitworld/client,
  bitworld/protocol,
  tribal_village_engine,
  tribal_quest/fortress_engine

const
  PlayerSocketPath = "/player"
  StepMilliseconds = 100

type
  ViewerState = object
    slot: int
    lastMask: uint8

  SurfaceState = object
    lock: Lock
    engine: ptr FortressEngine
    tokens: seq[string]
    viewers: Table[WebSocket, ViewerState]
    closedSockets: seq[WebSocket]

  ServerThreadArgs = object
    server: ptr Server
    address: string
    port: int

var surface: SurfaceState

proc textHeaders(contentType = "text/plain; charset=utf-8"): HttpHeaders =
  result["Content-Type"] = contentType

proc queryValue(request: Request, key: string): string =
  if key in request.queryParams:
    return request.queryParams[key]
  ""

proc parseSlot(raw: string): int =
  if raw.len == 0:
    return -1
  try:
    parseInt(raw)
  except ValueError:
    -1

proc tokenSlot(token: string): int =
  for i, item in surface.tokens:
    if item == token:
      return i
  -1

proc firstAvailableSlot(): int =
  if surface.engine.isNil:
    return -1
  var used: array[FortressAdventurerSlots, bool]
  for _, viewer in surface.viewers.pairs:
    if viewer.slot >= 0 and viewer.slot < used.len:
      used[viewer.slot] = true
  for slot in 0 ..< surface.engine[].adventurerSlots:
    if not used[slot]:
      return slot
  -1

proc claimViewerSlot(request: Request): int =
  let
    token = request.queryValue("token")
    explicitSlot = parseSlot(request.queryValue("slot"))
  if surface.tokens.len > 0:
    let tokenIndex = tokenSlot(token)
    if tokenIndex < 0:
      return -2
    if explicitSlot >= 0 and explicitSlot != tokenIndex:
      return -2
    result = tokenIndex
  else:
    result = if explicitSlot >= 0: explicitSlot else: firstAvailableSlot()
  if surface.engine.isNil or result < 0 or result >= surface.engine[].adventurerSlots:
    return -1

proc httpHandler(request: Request) {.gcsafe.} =
  if request.path == PlayerSocketPath and request.httpMethod == "GET":
    {.gcsafe.}:
      withLock surface.lock:
        let slot = claimViewerSlot(request)
        if slot == -2:
          request.respond(403, textHeaders(), "invalid token\n")
          return
        if slot < 0:
          request.respond(400, textHeaders(), "invalid or unavailable adventurer slot\n")
          return
        let agentId = surface.engine[].claimAdventurer(slot, slot mod FortressTownTokenSlots)
        if agentId < 0:
          request.respond(409, textHeaders(), "could not claim adventurer\n")
          return
        let websocket = request.upgradeToWebSocket()
        surface.viewers[websocket] = ViewerState(slot: slot, lastMask: 0)
    return

  if request.path in [PlayerClientRoute, PlayerClientHtmlRoute] and
      request.httpMethod == "GET":
    try:
      request.respond(
        200,
        textHeaders(clientStaticContentType(request.path)),
        readClientHtml(request.path)
      )
    except IOError:
      request.respond(404, textHeaders(), "client not found\n")
    return

  if request.path in [SnappyClientRoute, QrcodeClientRoute] and request.httpMethod == "GET":
    try:
      request.respond(
        200,
        textHeaders(clientStaticContentType(request.path)),
        readFile(clientStaticPath(request.path))
      )
    except IOError:
      request.respond(404, textHeaders(), "asset not found\n")
    return

  if request.path == "/" and request.httpMethod == "GET":
    request.respond(200, textHeaders(), "Tribal Quest Fortress player surface\n")
  else:
    request.respond(404, textHeaders(), "not found\n")

proc websocketHandler(
  websocket: WebSocket,
  event: WebSocketEvent,
  message: Message
) {.gcsafe.} =
  case event
  of OpenEvent:
    discard
  of MessageEvent:
    if message.kind == BinaryMessage:
      {.gcsafe.}:
        withLock surface.lock:
          if websocket in surface.viewers:
            var viewer = surface.viewers[websocket]
            viewer.lastMask = blobToMask(message.data)
            surface.viewers[websocket] = viewer
  of ErrorEvent, CloseEvent:
    {.gcsafe.}:
      withLock surface.lock:
        surface.closedSockets.add(websocket)

proc serverThreadProc(args: ServerThreadArgs) {.thread.} =
  args.server[].serve(Port(args.port), args.address)

proc frameFromObservation(text: string): string =
  var pixels = newSeq[uint8](ScreenWidth * ScreenHeight)
  try:
    let
      node = parseJson(text)
      view = node["view_plane"]
      cells = view["cells"]
      width = max(1, (if view.hasKey("width"): view["width"].getInt() else: QuestAdventureCropTiles))
      height = max(1, (if view.hasKey("height"): view["height"].getInt() else: QuestAdventureCropTiles))
    for py in 0 ..< ScreenHeight:
      let cellY = min(height - 1, py * height div ScreenHeight)
      for px in 0 ..< ScreenWidth:
        let cellX = min(width - 1, px * width div ScreenWidth)
        if cellY < cells.len and cellX < cells[cellY].len:
          pixels[py * ScreenWidth + px] = uint8(cells[cellY][cellX].getInt() and 0x0f)
  except CatchableError:
    discard

  result = newString(ProtocolBytes)
  for i in 0 ..< ProtocolBytes:
    let lo = pixels[i * 2] and 0x0f
    let hi = pixels[i * 2 + 1] and 0x0f
    result[i] = char(lo or (hi shl 4))

proc pruneClosedViewers() =
  for websocket in surface.closedSockets:
    if websocket in surface.viewers:
      let slot = surface.viewers[websocket].slot
      discard surface.engine[].releaseAdventurer(slot)
      surface.viewers.del(websocket)
  surface.closedSockets.setLen(0)

proc stepAndBuildFrames(): seq[tuple[websocket: WebSocket, frame: string]] =
  withLock surface.lock:
    pruneClosedViewers()
    for _, viewer in surface.viewers.pairs:
      surface.engine[].submitAdventurerInput(viewer.slot, adventurerInputJson(viewer.lastMask))
    surface.engine[].step()
    for websocket, viewer in surface.viewers.pairs:
      result.add((
        websocket: websocket,
        frame: frameFromObservation(surface.engine[].adventurerObservationJson(viewer.slot))
      ))

proc writeJsonFile(path: string, node: JsonNode) =
  if path.len > 0:
    writeFile(path, $node)

proc runLoop(): int =
  var previousTick = getMonoTime()
  while surface.engine[].maxSteps <= 0 or surface.engine[].tick < surface.engine[].maxSteps:
    let frames = stepAndBuildFrames()
    for item in frames:
      try:
        item.websocket.send(item.frame, BinaryMessage)
      except CatchableError:
        withLock surface.lock:
          surface.closedSockets.add(item.websocket)
    inc result
    let elapsed = inMilliseconds(getMonoTime() - previousTick)
    if elapsed < StepMilliseconds:
      sleep(StepMilliseconds - elapsed.int)
    previousTick = getMonoTime()

proc initSurface(engine: var FortressEngine, tokens: seq[string]) =
  initLock(surface.lock)
  surface.engine = addr engine
  surface.tokens = tokens
  surface.viewers = initTable[WebSocket, ViewerState]()
  surface.closedSockets = @[]

proc runQuestPlayerSurface*(
  engine: var FortressEngine,
  address: string,
  port: int,
  saveReplayPath: string,
  loadReplayPath: string,
  saveScoresPath: string,
  tokens: seq[string],
  maxGames: int,
  adventurerRole: string
) =
  discard loadReplayPath
  discard maxGames
  discard adventurerRole
  if tokens.len > engine.adventurerSlots:
    raise newException(ValueError, "more player tokens than adventurer slots")
  initSurface(engine, tokens)

  let httpServer = newServer(
    httpHandler,
    websocketHandler,
    workerThreads = 4,
    tcpNoDelay = true
  )
  var
    serverThread: Thread[ServerThreadArgs]
    serverPtr = cast[ptr Server](unsafeAddr httpServer)
  createThread(
    serverThread,
    serverThreadProc,
    ServerThreadArgs(server: serverPtr, address: address, port: port)
  )
  httpServer.waitUntilReady()
  echo "Tribal Quest player surface listening on http://", address, ":", port

  let ticks = runLoop()
  httpServer.close()
  joinThread(serverThread)
  writeJsonFile(saveScoresPath, %*{
    "runtime": "fortress",
    "ticks": ticks,
    "adventurer_slots": engine.adventurerSlots
  })
  writeJsonFile(saveReplayPath, %*{
    "runtime": "fortress",
    "ticks": ticks
  })
