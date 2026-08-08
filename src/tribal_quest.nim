import std/[json, os, parseopt, strutils]

import jsony
import tribal_quest/coworld_io
import tribal_quest/fortress_engine
import tribal_quest/player_surface
import tribal_quest/protocol
import tribal_quest/replay_surface

type
  TribalQuestError = object of CatchableError

  RunConfig = object
    mode: string
    address: string
    port: int
    seed: int
    maxSteps: int
    tokens: seq[string]
    players: seq[string]
    stepsPerSecond: float
    playerConnectTimeoutSeconds: float
    numAgents: int
    teamCount: int
    fortressDataDir: string
    saveReplayPath: string
    saveScoresPath: string

const
  CogameConfigUriEnv = "COGAME_CONFIG_URI"
  FortressDataDirEnv = "TRIBAL_FORTRESS_DATA_DIR"

proc readConfigStrings(node: JsonNode, name: string, values: var seq[string]) =
  if not node.hasKey(name):
    return
  let items = node[name]
  if items.kind != JArray:
    raise newException(TribalQuestError, "Config field " & name & " must be an array.")
  values.setLen(0)
  for i in 0 ..< items.len:
    let item = items[i]
    if item.kind != JString:
      raise newException(
        TribalQuestError,
        "Config field " & name & "[" & $i & "] must be a string."
      )
    values.add(item.getStr())

proc readConfigPlayers(node: JsonNode, values: var seq[string]) =
  if not node.hasKey("players"):
    return
  let items = node["players"]
  if items.kind != JArray:
    raise newException(TribalQuestError, "Config field players must be an array.")
  values.setLen(0)
  for i in 0 ..< items.len:
    let item = items[i]
    if item.kind != JObject or item.len != 1 or not item.hasKey("name") or
        item["name"].kind != JString:
      raise newException(
        TribalQuestError,
        "Config field players[" & $i &
          "] must be an object containing only a string name."
      )
    values.add(item["name"].getStr())

proc readConfigString(node: JsonNode, name: string, value: var string) =
  if node.hasKey(name):
    if node[name].kind != JString:
      raise newException(TribalQuestError, "Config field " & name & " must be a string.")
    value = node[name].getStr()

proc readConfigInt(node: JsonNode, name: string, value: var int) =
  if node.hasKey(name):
    if node[name].kind != JInt:
      raise newException(TribalQuestError, "Config field " & name & " must be an integer.")
    value = node[name].getInt()

proc readConfigFloat(node: JsonNode, name: string, value: var float) =
  if node.hasKey(name):
    case node[name].kind
    of JInt:
      value = node[name].getInt().float
    of JFloat:
      value = node[name].getFloat()
    else:
      raise newException(TribalQuestError, "Config field " & name & " must be a number.")

proc isKnownConfigField(name: string): bool =
  name in [
    "mode",
    "tokens",
    "players",
    "max_steps",
    "seed",
    "steps_per_second",
    "player_connect_timeout_seconds",
    "num_agents",
    "team_count",
    "victory_condition"
  ]

proc update(config: var RunConfig, jsonText: string) =
  ## Reads the shared Fortress/Quest hosted config. victory_condition is a
  ## Fortress-only field intentionally accepted so both modes share one schema.
  var node: JsonNode
  try:
    node = fromJson(jsonText)
  except jsony.JsonError as e:
    raise newException(TribalQuestError, "Could not parse config JSON: " & e.msg)
  if node.kind != JObject:
    raise newException(TribalQuestError, "Config must be a JSON object.")
  for name, _ in node.pairs:
    if not name.isKnownConfigField():
      raise newException(TribalQuestError, "Unknown config field: " & name)
  node.readConfigString("mode", config.mode)
  node.readConfigStrings("tokens", config.tokens)
  node.readConfigPlayers(config.players)
  node.readConfigInt("max_steps", config.maxSteps)
  node.readConfigInt("seed", config.seed)
  node.readConfigFloat("steps_per_second", config.stepsPerSecond)
  node.readConfigFloat(
    "player_connect_timeout_seconds",
    config.playerConnectTimeoutSeconds
  )
  node.readConfigInt("num_agents", config.numAgents)
  node.readConfigInt("team_count", config.teamCount)
  var ignoredVictoryCondition = 0
  node.readConfigInt("victory_condition", ignoredVictoryCondition)

proc requireOptionValue(name, value: string) =
  if value.len == 0:
    raise newException(TribalQuestError, "Option --" & name & " requires a value.")

proc parseOptionInt(name, value: string): int =
  name.requireOptionValue(value)
  try:
    result = parseInt(value)
  except ValueError:
    raise newException(TribalQuestError, "Option --" & name & " must be an integer.")

proc parseOptionFloat(name, value: string): float =
  name.requireOptionValue(value)
  try:
    result = parseFloat(value)
  except ValueError:
    raise newException(TribalQuestError, "Option --" & name & " must be a number.")

proc validate(config: RunConfig, hostedConfig: bool) =
  if config.mode != "quest":
    raise newException(TribalQuestError, "Config field mode must be quest.")
  if config.maxSteps < 1:
    raise newException(TribalQuestError, "Config field max_steps must be positive.")
  if hostedConfig and config.tokens.len != QuestLeaguePlayerCount:
    raise newException(
      TribalQuestError,
      "Quest league config requires exactly " & $QuestLeaguePlayerCount & " tokens."
    )
  if not hostedConfig and config.tokens.len notin [0, QuestLeaguePlayerCount]:
    raise newException(
      TribalQuestError,
      "Development config tokens must be empty or contain exactly " &
        $QuestLeaguePlayerCount & " items."
    )
  for token in config.tokens:
    if token.len == 0:
      raise newException(TribalQuestError, "Player tokens must not be empty.")
  if hostedConfig and config.players.len != QuestLeaguePlayerCount:
    raise newException(
      TribalQuestError,
      "Quest league config requires exactly " & $QuestLeaguePlayerCount & " players."
    )
  if config.players.len notin [0, QuestLeaguePlayerCount]:
    raise newException(
      TribalQuestError,
      "Config field players must be empty or contain exactly " &
        $QuestLeaguePlayerCount & " items."
    )
  for player in config.players:
    if player.len == 0:
      raise newException(TribalQuestError, "Player names must not be empty.")
  if config.stepsPerSecond < 1 or config.stepsPerSecond > 1000:
    raise newException(
      TribalQuestError,
      "Config field steps_per_second must be between 1 and 1000."
    )
  if config.playerConnectTimeoutSeconds < 0:
    raise newException(
      TribalQuestError,
      "Config field player_connect_timeout_seconds must be non-negative."
    )
  if config.numAgents != QuestLeaguePlayerCount:
    raise newException(
      TribalQuestError,
      "Config field num_agents must equal " & $QuestLeaguePlayerCount & "."
    )
  if config.teamCount != QuestLeaguePlayerCount:
    raise newException(
      TribalQuestError,
      "Config field team_count must equal " & $QuestLeaguePlayerCount & "."
    )
  questFortressEngineConfig(config.seed, config.maxSteps)
    .validateQuestEngineContract()

proc echoStartup(config: RunConfig) =
  let engineConfig = questFortressEngineConfig(config.seed, config.maxSteps)
  echo "Mode: quest"
  echo "World runtime: tribal_fortress_engine"
  echo "Fortress world: ", engineConfig.worldWidth, "x",
      engineConfig.worldHeight
  echo "NPC town agents per team: ", engineConfig.townAgentsPerTeam
  echo "Adventurer slots: ", engineConfig.adventurerSlots
  echo "League players: ", config.tokens.len
  echo "Max steps: ", config.maxSteps
  echo "Steps per second: ", config.stepsPerSecond

when isMainModule:
  let replayLoadUri = getEnv("COGAME_LOAD_REPLAY_URI")
  if replayLoadUri.len > 0:
    let replay = parseJson(readCoworldData(
      replayLoadUri,
      "COGAME_LOAD_REPLAY_URI"
    ))
    runQuestReplaySurface(
      replay,
      getEnv("COGAME_HOST", "0.0.0.0"),
      parseInt(getEnv("COGAME_PORT", $DefaultPort))
    )
    quit(0)

  var
    config = RunConfig(
      mode: "quest",
      address: DefaultHost,
      port: DefaultPort,
      seed: 0xB1770,
      maxSteps: 300,
      tokens: @[],
      players: @[],
      stepsPerSecond: 10,
      playerConnectTimeoutSeconds: 0,
      numAgents: QuestLeaguePlayerCount,
      teamCount: QuestLeaguePlayerCount,
      fortressDataDir: getEnv(FortressDataDirEnv, "data"),
      saveReplayPath: getEnv("COGAME_SAVE_REPLAY_URI"),
      saveScoresPath: getEnv("COGAME_RESULTS_URI")
    )
    configPath = getEnv(CogameConfigUriEnv)
    configJson = ""

  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "address":
        key.requireOptionValue(val)
        config.address = val
      of "port":
        config.port = key.parseOptionInt(val)
      of "seed":
        config.seed = key.parseOptionInt(val)
      of "max-steps":
        config.maxSteps = key.parseOptionInt(val)
      of "steps-per-second":
        config.stepsPerSecond = key.parseOptionFloat(val)
      of "player-connect-timeout-seconds":
        config.playerConnectTimeoutSeconds = key.parseOptionFloat(val)
      of "fortress-data-dir":
        key.requireOptionValue(val)
        config.fortressDataDir = val
      of "save-replay":
        key.requireOptionValue(val)
        config.saveReplayPath = val
      of "save-scores":
        key.requireOptionValue(val)
        config.saveScoresPath = val
      of "config":
        key.requireOptionValue(val)
        configJson = val
      of "config-file":
        key.requireOptionValue(val)
        configPath = val
      else:
        raise newException(TribalQuestError, "Unknown option: --" & key)
    of cmdShortOption:
      raise newException(TribalQuestError, "Unknown option: -" & key)
    of cmdArgument:
      raise newException(TribalQuestError, "Unexpected argument: " & key)
    of cmdEnd:
      discard

  let hostedConfig = configPath.len > 0
  if hostedConfig:
    config.update(readCoworldData(configPath, CogameConfigUriEnv))
  if configJson.len > 0:
    config.update(configJson)
  config.validate(hostedConfig or configJson.len > 0)
  config.echoStartup()

  var engine = initFortressEngine(
    questFortressEngineConfig(config.seed, config.maxSteps)
  )
  try:
    runQuestPlayerSurface(
      engine = engine,
      address = config.address,
      port = config.port,
      saveReplayPath = config.saveReplayPath,
      saveScoresPath = config.saveScoresPath,
      tokens = config.tokens,
      playerNames = config.players,
      stepSeconds = 1.0 / config.stepsPerSecond,
      playerConnectTimeoutSeconds = config.playerConnectTimeoutSeconds,
      renderEverySteps = 1,
      fortressDataDir = config.fortressDataDir
    )
  finally:
    engine.close()
