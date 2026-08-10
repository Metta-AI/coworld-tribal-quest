import
  std/[json, locks, monotimes, os, sets, strutils, tables, times],
  mummy,
  tribal_quest/client,
  tribal_quest/coworld_io,
  tribal_quest/fortress_engine,
  tribal_quest/gridworld_sprites,
  tribal_quest/scoring,
  tribal_quest/sprite_packets

const
  PlayerSocketPath = "/player"
  GlobalSocketPath = "/global"
  GlobalProtocol = "tribal-quest-global-v1"

type
  QuestPlayerFrame* = tuple[websocket: WebSocket, frame: string]

  ViewerState = object
    slot: int
    name: string
    lastMask: uint8
    progress: QuestProgress
    knownSprites: HashSet[int]

  PlayerScore = object
    slot: int
    name: string
    progress: QuestProgress

  SurfaceState = object
    lock: Lock
    engine: ptr FortressEngine
    tokens: seq[string]
    playerNames: seq[string]
    playerCount: int
    viewers: Table[WebSocket, ViewerState]
    globalViewers: HashSet[WebSocket]
    closedSockets: seq[WebSocket]
    closedGlobalSockets: seq[WebSocket]
    completedScores: seq[PlayerScore]
    spriteRegistry: QuestSpriteRegistry

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

proc headerContainsToken(request: Request, key, token: string): bool =
  let expected = token.toLowerAscii()
  for (headerKey, headerValue) in request.headers:
    if cmpIgnoreCase(headerKey, key) == 0:
      for part in headerValue.split(','):
        if part.strip().toLowerAscii() == expected:
          return true
  false

proc isWebSocketUpgrade(request: Request): bool =
  request.headerContainsToken("Connection", "Upgrade") and
    request.headerContainsToken("Upgrade", "websocket")

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

proc surfaceIsInitialized(): bool {.gcsafe.} =
  {.gcsafe.}:
    result = not surface.engine.isNil

proc firstAvailableSlot(): int =
  if surface.engine.isNil:
    return -1
  var used: array[QuestAdventurerSlots, bool]
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

proc viewerName(request: Request, slot: int): string =
  result = request.queryValue("name").strip()
  if result.len == 0 and slot >= 0 and slot < surface.playerNames.len:
    result = surface.playerNames[slot]
  if result.len == 0:
    result = "adventurer_" & $slot

proc playerClientHtml(): string =
  result = readClientHtml(PlayerClientRoute)
  result = result.replace(
    "<canvas id=\"c\" width=\"128\" height=\"128\"></canvas>",
    "<canvas id=\"c\" width=\"128\" height=\"128\" tabindex=\"0\" autofocus></canvas>"
  )
  result = result.replace(
    "function release(){k={};sendMask(0,true)}",
    "function release(){k={};sendMask(0,true)}" &
      "function keyMask(){let h=0;" &
      "h|=!z&&(k.ArrowUp||k.KeyW)?1:0;" &
      "h|=!z&&(k.ArrowDown||k.KeyS)?2:0;" &
      "h|=!z&&(k.ArrowLeft||k.KeyA)?4:0;" &
      "h|=!z&&(k.ArrowRight||k.KeyD)?8:0;" &
      "h|=!z&&(k.Space||k.KeyL)?16:0;" &
      "h|=!z&&(k.KeyZ||k.KeyJ)?32:0;" &
      "h|=!z&&(k.KeyX||k.KeyK)?64:0;" &
      "return h&127}"
  )
  result = result.replace(
    "fit();\nonkeydown=",
    "fit();c.focus();\nonpointerdown=()=>c.focus();\nonkeydown="
  )
  result = result.replace(
    "  k[e.code]=1\n};\nonkeyup=e=>{k[e.code]=0};",
    "  if(e.code.startsWith(\"Arrow\"))e.preventDefault();\n" &
      "  k[e.code]=1;sendMask(keyMask(),true)\n" &
      "};\nonkeyup=e=>{k[e.code]=0;sendMask(keyMask(),true)};"
  )

proc upgradeRequiredHeaders(): HttpHeaders =
  result = textHeaders()
  result["Connection"] = "Upgrade"
  result["Upgrade"] = "websocket"

proc globalSnapshotUnlocked(frameType: string): JsonNode =
  var
    names = newSeq[string](surface.playerCount)
    progresses = newSeq[QuestProgress](surface.playerCount)
    connected = newSeq[bool](surface.playerCount)
    adventurers = newJArray()
    scores = newJArray()
    survivalTicks = newJArray()
    exploredTiles = newJArray()

  for slot in 0 ..< surface.playerCount:
    names[slot] =
      if slot < surface.playerNames.len: surface.playerNames[slot]
      else: "adventurer_" & $slot
  for score in surface.completedScores:
    if score.slot >= 0 and score.slot < surface.playerCount:
      names[score.slot] = score.name
      progresses[score.slot] = score.progress
  for _, viewer in surface.viewers.pairs:
    if viewer.slot >= 0 and viewer.slot < surface.playerCount:
      names[viewer.slot] = viewer.name
      progresses[viewer.slot] = viewer.progress
      connected[viewer.slot] = true

  var connectedPlayers = 0
  for slot in 0 ..< surface.playerCount:
    if connected[slot]:
      inc connectedPlayers
    var cells: array[QuestAdventureCropTiles * QuestAdventureCropTiles, uint8]
    let
      view = surface.engine[].adventurerViewCells(slot, cells)
      alive = connected[slot] and view.ok and not view.done
      done = connected[slot] and view.done
      score = progresses[slot].questScore()
      explored = progresses[slot].exploredTiles()
    adventurers.add(%*{
      "slot": slot,
      "name": names[slot],
      "connected": connected[slot],
      "alive": alive,
      "done": done,
      "team_id": view.teamId,
      "x": view.x,
      "y": view.y,
      "hp": view.hp,
      "max_hp": view.maxHp,
      "score": score,
      "survival_ticks": progresses[slot].survivalTicks,
      "explored_tiles": explored
    })
    scores.add(%score)
    survivalTicks.add(%progresses[slot].survivalTicks)
    exploredTiles.add(%explored)

  let
    finished = surface.engine[].maxSteps > 0 and
      surface.engine[].tick >= surface.engine[].maxSteps
    phase =
      if finished: "finished"
      elif surface.engine[].tick > 0: "running"
      elif connectedPlayers < surface.tokens.len: "waiting_for_players"
      else: "ready"
  %*{
    "type": frameType,
    "protocol": GlobalProtocol,
    "mode": "quest",
    "status": {
      "phase": phase,
      "step": surface.engine[].tick,
      "max_steps": surface.engine[].maxSteps,
      "connected_players": connectedPlayers,
      "expected_players": surface.tokens.len
    },
    "adventurers": adventurers,
    "scores": scores,
    "survival_ticks": survivalTicks,
    "explored_tiles": exploredTiles
  }

proc handleQuestAdventurerHttp*(request: Request): bool {.gcsafe.} =
  ## Handles Quest-owned adventurer routes for a host that already owns
  ## the Fortress engine/world. Returns false when the route is not ours.
  if request.path == PlayerSocketPath and request.httpMethod == "GET":
    result = true
    if not surfaceIsInitialized():
      request.respond(
        500,
        textHeaders(),
        "Quest adventurer surface is not initialized\n"
      )
      return
    if not request.isWebSocketUpgrade():
      request.respond(
        426,
        upgradeRequiredHeaders(),
        "websocket upgrade required\n"
      )
      return
    if request.queryValue("protocol").len > 0:
      request.respond(
        400,
        textHeaders(),
        "protocol query is not supported; /player is sprite_v1\n"
      )
      return
    {.gcsafe.}:
      withLock surface.lock:
        let slot = claimViewerSlot(request)
        if slot == -2:
          request.respond(403, textHeaders(), "invalid token\n")
          return
        if slot < 0:
          request.respond(400, textHeaders(), "invalid or unavailable adventurer slot\n")
          return
        let agentId = surface.engine[].claimAdventurer(
          slot,
          slot
        )
        if agentId < 0:
          request.respond(409, textHeaders(), "could not claim adventurer\n")
          return
        let websocket = request.upgradeToWebSocket()
        surface.viewers[websocket] = ViewerState(
          slot: slot,
          name: request.viewerName(slot),
          lastMask: 0,
          progress: initQuestProgress(),
          knownSprites: initHashSet[int]()
        )
    return

  if request.path == GlobalSocketPath and request.httpMethod == "GET":
    result = true
    if not surfaceIsInitialized():
      request.respond(
        500,
        textHeaders(),
        "Quest adventurer surface is not initialized\n"
      )
      return
    if not request.isWebSocketUpgrade():
      request.respond(
        426,
        upgradeRequiredHeaders(),
        "websocket upgrade required\n"
      )
      return
    var
      websocket: WebSocket
      initialFrame: string
    {.gcsafe.}:
      withLock surface.lock:
        websocket = request.upgradeToWebSocket()
        surface.globalViewers.incl(websocket)
        initialFrame = $globalSnapshotUnlocked("view.init")
    try:
      websocket.send(initialFrame, TextMessage)
    except CatchableError:
      {.gcsafe.}:
        withLock surface.lock:
          surface.closedGlobalSockets.add(websocket)
    return

  if request.path in [
      PlayerClientRoute,
      PlayerClientHtmlRoute,
      GlobalClientRoute,
      GlobalClientHtmlRoute
  ] and
      request.httpMethod == "GET":
    result = true
    try:
      request.respond(
        200,
        textHeaders(clientStaticContentType(request.path)),
        if request.path in [PlayerClientRoute, PlayerClientHtmlRoute]:
          playerClientHtml()
        else:
          clientStaticBody(request.path)
      )
    except IOError:
      request.respond(404, textHeaders(), "client not found\n")
    return

  if request.path in [SnappyClientRoute, SnappyClientPath] and
      request.httpMethod == "GET":
    result = true
    try:
      request.respond(
        200,
        textHeaders(clientStaticContentType(request.path)),
        clientStaticBody(request.path)
      )
    except IOError:
      request.respond(404, textHeaders(), "asset not found\n")
    return

  if request.path == "/" and request.httpMethod == "GET":
    result = true
    request.respond(200, textHeaders(), "Tribal Quest Fortress player surface\n")
    return

  if request.path == "/healthz" and request.httpMethod == "GET":
    result = true
    request.respond(200, textHeaders(), "ok\n")

proc httpHandler(request: Request) {.gcsafe.} =
  if not handleQuestAdventurerHttp(request):
    request.respond(404, textHeaders(), "not found\n")

proc handleQuestAdventurerWebSocket*(
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
            var mask: uint8
            if playerMaskFromPacket(message.data, mask):
              viewer.lastMask = mask
              surface.viewers[websocket] = viewer
            elif message.data.isTextInputPacket():
              discard
  of ErrorEvent, CloseEvent:
    {.gcsafe.}:
      withLock surface.lock:
        if websocket in surface.globalViewers:
          surface.closedGlobalSockets.add(websocket)
        else:
          surface.closedSockets.add(websocket)

proc websocketHandler(
  websocket: WebSocket,
  event: WebSocketEvent,
  message: Message
) {.gcsafe.} =
  handleQuestAdventurerWebSocket(websocket, event, message)

proc serverThreadProc(args: ServerThreadArgs) {.thread.} =
  args.server[].serve(Port(args.port), args.address)

proc rememberScore(viewer: ViewerState) =
  surface.completedScores.add(PlayerScore(
    slot: viewer.slot,
    name: viewer.name,
    progress: viewer.progress
  ))

proc pruneClosedViewers() =
  for websocket in surface.closedGlobalSockets:
    surface.globalViewers.excl(websocket)
  surface.closedGlobalSockets.setLen(0)
  for websocket in surface.closedSockets:
    if websocket in surface.viewers:
      let slot = surface.viewers[websocket].slot
      surface.viewers[websocket].rememberScore()
      surface.viewers.del(websocket)
      var slotStillViewed = false
      for _, viewer in surface.viewers.pairs:
        if viewer.slot == slot:
          slotStillViewed = true
          break
      if not slotStillViewed:
        discard surface.engine[].releaseAdventurer(slot)
  surface.closedSockets.setLen(0)

proc submitQuestAdventurerInputs*() =
  ## Pushes the latest Quest button masks into the shared Fortress engine.
  ## The caller owns the engine step so multiple surfaces can share one tick.
  if not surfaceIsInitialized():
    raise newException(ValueError, "Quest adventurer surface is not initialized")
  withLock surface.lock:
    pruneClosedViewers()
    for _, viewer in surface.viewers.pairs:
      surface.engine[].submitAdventurerButtons(viewer.slot, viewer.lastMask)

proc observeQuestAdventurerProgress*() =
  ## Records score inputs from the post-step Fortress engine state.
  if not surfaceIsInitialized():
    raise newException(ValueError, "Quest adventurer surface is not initialized")
  withLock surface.lock:
    pruneClosedViewers()
    for _, viewer in surface.viewers.mpairs:
      var cells: array[QuestAdventureCropTiles * QuestAdventureCropTiles, uint8]
      let view = surface.engine[].adventurerViewCells(viewer.slot, cells)
      viewer.progress.observeQuestState(
        view.ok and not view.done,
        view.x,
        view.y
      )

proc buildQuestAdventurerFrames*(): seq[QuestPlayerFrame] =
  ## Builds player frames from the current post-step Fortress engine state.
  if not surfaceIsInitialized():
    raise newException(ValueError, "Quest adventurer surface is not initialized")
  withLock surface.lock:
    pruneClosedViewers()
    for websocket, viewer in surface.viewers.mpairs:
      let frame = surface.engine[].buildAdventurerSpriteFrame(
        viewer.slot,
        surface.spriteRegistry,
        viewer.knownSprites
      )
      result.add((
        websocket: websocket,
        frame: frame
      ))

proc stepAndBuildFrames(): seq[QuestPlayerFrame] =
  submitQuestAdventurerInputs()
  surface.engine[].step()
  observeQuestAdventurerProgress()
  buildQuestAdventurerFrames()

proc sendQuestAdventurerFrames*(frames: openArray[QuestPlayerFrame]) =
  ## Sends already-built frames and marks broken sockets for release.
  if not surfaceIsInitialized():
    raise newException(ValueError, "Quest adventurer surface is not initialized")
  for item in frames:
    try:
      item.websocket.send(item.frame, BinaryMessage)
    except CatchableError:
      withLock surface.lock:
        surface.closedSockets.add(item.websocket)

proc broadcastQuestGlobalView*() =
  ## Publishes a read-only snapshot derived from the authoritative shared
  ## Fortress engine and Quest's recorded scoring progress.
  if not surfaceIsInitialized():
    raise newException(ValueError, "Quest adventurer surface is not initialized")
  var
    viewers: seq[WebSocket]
    frame: string
  withLock surface.lock:
    pruneClosedViewers()
    frame = $globalSnapshotUnlocked("view.update")
    for websocket in surface.globalViewers:
      viewers.add(websocket)
  for websocket in viewers:
    try:
      websocket.send(frame, TextMessage)
    except CatchableError:
      withLock surface.lock:
        surface.closedGlobalSockets.add(websocket)

proc tickQuestAdventurerSurface*(): int =
  ## Convenience one-process tick: submit Quest inputs, step the shared engine,
  ## render Quest frames, and send them. Combined hosts should call the pieces.
  let frames = stepAndBuildFrames()
  broadcastQuestGlobalView()
  sendQuestAdventurerFrames(frames)
  frames.len

proc scoresJson(ticks: int, truncationReason: string): JsonNode =
  var
    names = newJArray()
    scores = newJArray()
    survivalTicks = newJArray()
    exploredTiles = newJArray()
    slotNames = newSeq[string](surface.playerCount)
    slotProgress = newSeq[QuestProgress](surface.playerCount)
  for slot in 0 ..< surface.playerCount:
    slotNames[slot] =
      if slot < surface.playerNames.len: surface.playerNames[slot]
      else: "adventurer_" & $slot
  withLock surface.lock:
    for score in surface.completedScores:
      if score.slot >= 0 and score.slot < surface.playerCount:
        slotNames[score.slot] = score.name
        slotProgress[score.slot] = score.progress
    for _, viewer in surface.viewers.pairs:
      if viewer.slot >= 0 and viewer.slot < surface.playerCount:
        slotNames[viewer.slot] = viewer.name
        slotProgress[viewer.slot] = viewer.progress
  for slot in 0 ..< surface.playerCount:
    names.add(%slotNames[slot])
    scores.add(%slotProgress[slot].questScore())
    survivalTicks.add(%slotProgress[slot].survivalTicks)
    exploredTiles.add(%slotProgress[slot].exploredTiles())
  %*{
    "mode": "quest",
    "steps": ticks,
    "truncation_reason": truncationReason,
    "names": names,
    "scores": scores,
    "survival_ticks": survivalTicks,
    "explored_tiles": exploredTiles
  }

proc connectedQuestPlayerCount*(): int =
  if not surfaceIsInitialized():
    return 0
  withLock surface.lock:
    result = surface.viewers.len

proc waitForQuestPlayers(expected: int, timeoutSeconds: float) =
  if expected <= 0 or timeoutSeconds <= 0:
    return
  let deadline = getMonoTime() + initDuration(
    milliseconds = int64(timeoutSeconds * 1000.0)
  )
  while connectedQuestPlayerCount() < expected and getMonoTime() < deadline:
    sleep(20)

proc runLoop(stepSeconds: float, renderEverySteps: int): int =
  var previousTick = getMonoTime()
  while surface.engine[].maxSteps <= 0 or surface.engine[].tick <
      surface.engine[].maxSteps:
    submitQuestAdventurerInputs()
    surface.engine[].step()
    observeQuestAdventurerProgress()
    inc result
    broadcastQuestGlobalView()
    if result mod renderEverySteps == 0 or
        surface.engine[].tick >= surface.engine[].maxSteps:
      sendQuestAdventurerFrames(buildQuestAdventurerFrames())
    let
      targetMilliseconds = int(stepSeconds * 1000.0)
      elapsed = inMilliseconds(getMonoTime() - previousTick).int
    if elapsed < targetMilliseconds:
      sleep(targetMilliseconds - elapsed)
    previousTick = getMonoTime()

proc initQuestAdventurerSurface*(
  engine: var FortressEngine,
  tokens: seq[string],
  playerNames: seq[string] = @[],
  fortressDataDir = "data"
) =
  ## Installs Quest's adventurer controls onto an existing Fortress engine.
  if tokens.len > engine.adventurerSlots:
    raise newException(ValueError, "more player tokens than adventurer slots")
  if tokens.len != 0 and tokens.len notin
      QuestLeagueMinPlayerCount .. QuestLeagueMaxPlayerCount:
    raise newException(ValueError, "player token count must be between 2 and 8")
  if playerNames.len notin [0, tokens.len]:
    raise newException(ValueError, "player names must be empty or match player tokens")
  initLock(surface.lock)
  surface.engine = addr engine
  surface.tokens = tokens
  surface.playerNames = playerNames
  surface.playerCount =
    if tokens.len > 0: tokens.len
    elif playerNames.len > 0: playerNames.len
    else: QuestLeagueMaxPlayerCount
  surface.viewers = initTable[WebSocket, ViewerState]()
  surface.globalViewers = initHashSet[WebSocket]()
  surface.closedSockets = @[]
  surface.closedGlobalSockets = @[]
  surface.completedScores = @[]
  surface.spriteRegistry = initQuestSpriteRegistry(fortressDataDir)

proc runQuestPlayerSurface*(
  engine: var FortressEngine,
  address: string,
  port: int,
  saveReplayPath: string,
  saveScoresPath: string,
  tokens: seq[string],
  playerNames: seq[string],
  stepSeconds: float,
  playerConnectTimeoutSeconds: float,
  renderEverySteps: int,
  fortressDataDir = "data"
) =
  initQuestAdventurerSurface(engine, tokens, playerNames, fortressDataDir)

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

  waitForQuestPlayers(tokens.len, playerConnectTimeoutSeconds)
  let ticks = runLoop(stepSeconds, renderEverySteps)
  httpServer.close()
  joinThread(serverThread)
  writeCoworldJson(
    saveScoresPath,
    scoresJson(ticks, "max_steps"),
    "COGAME_RESULTS_METHOD"
  )
  let replay = scoresJson(ticks, "max_steps")
  replay["format"] = %"tribal-quest-replay-v1"
  writeCoworldJson(
    saveReplayPath,
    replay,
    "COGAME_SAVE_REPLAY_METHOD"
  )
