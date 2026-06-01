import std/[httpclient, json, os, parseopt, strutils]

import jsony
import tribal_village_engine
import tribal_quest/fortress_engine
import tribal_quest/player_surface
import tribal_quest/protocol

type
  TribalQuestError = object of CatchableError

  RunConfig = object
    address: string
    port: int
    seed: int
    maxTicks: int
    maxGames: int
    tokens: seq[string]
    fortressEnginePath: string
    saveReplayPath: string
    saveScoresPath: string

const
  CogameConfigUriEnv = "COGAME_CONFIG_URI"
  CogameResultsUriEnv = "COGAME_RESULTS_URI"
  CogameSaveReplayUriEnv = "COGAME_SAVE_REPLAY_URI"
  UnlimitedFortressMaxSteps = high(int)

proc pathFromCogameUri(value, source: string): string =
  ## Converts a Coworld input URI into a local path.
  if value.len == 0:
    return ""
  const FilePrefix = "file://"
  if value.startsWith(FilePrefix):
    result = value[FilePrefix.len .. ^1]
    if result.len == 0:
      raise newException(ValueError, "empty file URI from " & source)
    return
  if value.startsWith("http://") or value.startsWith("https://"):
    var client = newHttpClient(timeout = 30_000)
    try:
      let body = client.getContent(value)
      result = getTempDir() / ("cogame-" & source.toLowerAscii() & ".json")
      writeFile(result, body)
      return
    finally:
      client.close()
  if "://" in value:
    raise newException(ValueError, "unsupported URI from " & source & ": " & value)
  raise newException(ValueError, source & " must be a URI")

proc pathFromCogameEnv(name: string): string =
  ## Reads a Coworld URI env var and returns the local path it addresses.
  pathFromCogameUri(getEnv(name), name)

proc readConfigStrings(node: JsonNode, name: string, values: var seq[string]) =
  ## Reads one optional string-array config field.
  if not node.hasKey(name):
    return
  let items = node[name]
  if items.kind != JArray:
    raise newException(
      TribalQuestError,
      "Config field " & name & " must be an array."
    )
  values.setLen(0)
  for i in 0 ..< items.len:
    let item = items[i]
    if item.kind != JString:
      raise newException(
        TribalQuestError,
        "Config field " & name & "[" & $i & "] must be a string."
      )
    values.add(item.getStr())

proc readConfigString(node: JsonNode, name: string, value: var string) =
  ## Reads one optional string config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JString:
    raise newException(
      TribalQuestError,
      "Config field " & name & " must be a string."
    )
  value = item.getStr()

proc readConfigInt(node: JsonNode, name: string, value: var int) =
  ## Reads one optional integer config field.
  if not node.hasKey(name):
    return
  let item = node[name]
  if item.kind != JInt:
    raise newException(
      TribalQuestError,
      "Config field " & name & " must be an integer."
    )
  value = item.getInt()

proc defaultReplayPath(): string =
  ## Returns the configured replay save path from the environment.
  pathFromCogameEnv(CogameSaveReplayUriEnv)

proc defaultScoresPath(): string =
  ## Returns the configured score save path from the environment.
  pathFromCogameEnv(CogameResultsUriEnv)

proc isKnownConfigField(name: string): bool =
  ## Returns true when a JSON config field is supported.
  case name
  of "address",
      "port",
      "seed",
      "maxTicks",
      "maxGames",
      "tokens",
      "fortressEnginePath",
      "saveReplayPath",
      "saveScoresPath":
    true
  else:
    false

proc validateConfigFields(node: JsonNode) =
  ## Raises when JSON config contains an unknown field.
  for name, _ in node.pairs:
    if not name.isKnownConfigField():
      raise newException(TribalQuestError, "Unknown config field: " & name)

proc update(config: var RunConfig, jsonText: string) =
  ## Updates the CLI config from JSON.
  if jsonText.len == 0:
    return
  var node: JsonNode
  try:
    node = fromJson(jsonText)
  except jsony.JsonError as e:
    raise newException(
      TribalQuestError,
      "Could not parse config JSON: " & e.msg
    )
  if node.kind != JObject:
    raise newException(TribalQuestError, "Config must be a JSON object.")
  node.validateConfigFields()
  node.readConfigString("address", config.address)
  node.readConfigInt("port", config.port)
  node.readConfigString("saveReplayPath", config.saveReplayPath)
  node.readConfigString("saveScoresPath", config.saveScoresPath)
  node.readConfigInt("seed", config.seed)
  node.readConfigInt("maxTicks", config.maxTicks)
  node.readConfigInt("maxGames", config.maxGames)
  node.readConfigStrings("tokens", config.tokens)
  node.readConfigString("fortressEnginePath", config.fortressEnginePath)

proc requireOptionValue(name, value: string) =
  ## Raises when a CLI option is missing its value.
  if value.len == 0:
    raise newException(
      TribalQuestError,
      "Option --" & name & " requires a value."
    )

proc parseOptionInt(name, value: string): int =
  ## Parses one integer CLI option.
  name.requireOptionValue(value)
  try:
    result = parseInt(value)
  except ValueError:
    raise newException(
      TribalQuestError,
      "Option --" & name & " must be an integer."
    )

proc fortressEngineConfig(config: RunConfig): fortress_engine.FortressEngineConfig =
  ## Builds the required shared-engine config selected by the Quest run config.
  result = fortress_engine.defaultFortressEngineConfig()
  result.path = config.fortressEnginePath
  if result.path.strip().len == 0:
    result.path = fortress_engine.defaultFortressEnginePath()

proc fortressMaxSteps(config: RunConfig): int =
  ## Fortress's env has a finite default episode cap, so pass an explicit
  ## practical infinity when Quest's dev host is configured as unlimited.
  if config.maxTicks > 0:
    return config.maxTicks
  UnlimitedFortressMaxSteps

proc validate(config: RunConfig) =
  ## Raises when a run config value is outside the supported range.
  if config.maxTicks < 0:
    raise newException(
      TribalQuestError,
      "Config field maxTicks must be non-negative."
    )
  if config.maxGames < 0:
    raise newException(
      TribalQuestError,
      "Config field maxGames must be non-negative."
    )
  try:
    config.fortressEngineConfig().validateFortressEngineConfig()
  except ValueError as e:
    raise newException(TribalQuestError, e.msg)

proc echoStartupPaths(config: RunConfig) =
  ## Prints configured runtime, replay, and score output paths.
  let engineConfig = config.fortressEngineConfig()
  if config.saveReplayPath.len > 0:
    echo "Writing replay file: " & config.saveReplayPath
  else:
    echo "Not writing replay file."
  if config.saveScoresPath.len > 0:
    echo "Writing scores file: " & config.saveScoresPath
  else:
    echo "Not writing scores file."
  if config.tokens.len > 0:
    echo "Using " & $config.tokens.len & " player connection tokens."
  else:
    echo "No player connection tokens configured."
  echo "World runtime: fortress"
  echo "Fortress engine path: " & engineConfig.path
  echo "Fortress world target: " & $engineConfig.worldWidth & "x" &
    $engineConfig.worldHeight & " tiles"
  echo "NPC town agent cap: " & $engineConfig.townAgentsPerTeam
  echo "Adventurer slots: " & $engineConfig.adventurerSlots
  if config.maxTicks > 0:
    echo "Max ticks: " & $config.maxTicks
  else:
    echo "Max ticks: infinite"
  if config.maxGames > 0:
    echo "Max games: " & $config.maxGames
  else:
    echo "Max games: infinite"

when isMainModule:
  var
    config = RunConfig(
      address: DefaultHost,
      port: DefaultPort,
      seed: 0xB1770,
      maxTicks: DefaultMaxTicks,
      maxGames: DefaultMaxGames,
      tokens: @[],
      fortressEnginePath: "",
      saveReplayPath: defaultReplayPath(),
      saveScoresPath: defaultScoresPath()
    )
    configPath = pathFromCogameEnv(CogameConfigUriEnv)
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
      of "max-ticks":
        config.maxTicks = key.parseOptionInt(val)
      of "max-games":
        config.maxGames = key.parseOptionInt(val)
      of "fortress-engine-path":
        key.requireOptionValue(val)
        config.fortressEnginePath = val
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
  if configPath.len > 0:
    config.update(readFile(configPath))
  if configJson.len > 0:
    config.update(configJson)
  config.validate()
  config.echoStartupPaths()

  let questEngineConfig = config.fortressEngineConfig()
  putEnv(FortressEnginePathEnv, questEngineConfig.path)
  var engine = tribal_village_engine.initFortressEngine(
    tribal_village_engine.FortressEngineConfig(
      maxSteps: config.fortressMaxSteps(),
      seed: config.seed,
      adventurerViewRadius: QuestAdventureCropTiles div 2,
      aiMode: "hybrid",
      worldWidth: questEngineConfig.worldWidth,
      worldHeight: questEngineConfig.worldHeight,
      townAgentsPerTeam: questEngineConfig.townAgentsPerTeam,
      adventurerSlots: questEngineConfig.adventurerSlots
    )
  )
  try:
    runQuestPlayerSurface(
      engine = engine,
      address = config.address,
      port = config.port,
      saveReplayPath = config.saveReplayPath,
      saveScoresPath = config.saveScoresPath,
      tokens = config.tokens,
      maxGames = config.maxGames
    )
  finally:
    engine.close()
