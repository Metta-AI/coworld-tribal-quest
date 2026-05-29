import std/[json, os, strutils]
import bitworld/protocol

const
  FortressEnginePathEnv* = "TRIBAL_FORTRESS_PATH"
  DefaultFortressCheckoutDir* = "../coworld-tribal-fortress"
  FortressWorldWidthTiles* = 768
  FortressWorldHeightTiles* = 480
  FortressTownTokenSlots* = 8
  FortressTownAgentsPerTeam* = 30
  FortressAdventurerSlots* = 64
  QuestAdventureCropTiles* = 11
  QuestBitWorldScreenPixels* = 128
  AdventurerInputType* = "adventurer.input"
  AdventurerControlProfile* = "Adventurer"
  NpcControlProfile* = "Npc"

type
  AdventurerMove* = enum
    MoveNone = "none"
    MoveN = "N"
    MoveS = "S"
    MoveW = "W"
    MoveE = "E"
    MoveNW = "NW"
    MoveNE = "NE"
    MoveSW = "SW"
    MoveSE = "SE"

  FortressEngineConfig* = object
    path*: string
    adventurerRole*: string
    worldWidth*: int
    worldHeight*: int
    townAgentsPerTeam*: int
    adventurerSlots*: int

  FortressAdventurerObservation* = object
    agentId*: int
    teamId*: int
    civilization*: string
    role*: string
    x*: int
    y*: int
    hp*: int
    maxHp*: int
    status*: string
    originX*: int
    originY*: int
    cropWidth*: int
    cropHeight*: int
    done*: bool

proc validateWorldRuntime*(value: string) =
  ## Raises unless a config explicitly selects the only supported runtime.
  let normalized = value.strip().toLowerAscii()
  if normalized notin ["fortress", "fortress-engine", "fortress_engine"]:
    raise newException(ValueError, "worldRuntime must be fortress")

proc defaultFortressEnginePath*(cwd = getCurrentDir()): string =
  ## Returns the configured Fortress checkout path, preferring the environment.
  let envPath = getEnv(FortressEnginePathEnv).strip()
  if envPath.len > 0:
    return envPath
  cwd / DefaultFortressCheckoutDir

proc defaultFortressEngineConfig*(): FortressEngineConfig =
  ## Returns Quest's default shared-engine target.
  FortressEngineConfig(
    path: "",
    adventurerRole: "adventurer",
    worldWidth: FortressWorldWidthTiles,
    worldHeight: FortressWorldHeightTiles,
    townAgentsPerTeam: FortressTownAgentsPerTeam,
    adventurerSlots: FortressAdventurerSlots
  )

proc isLikelyFortressEngineCheckout*(path: string): bool =
  ## Returns true when a path looks like the sibling Fortress repo/package.
  if path.len == 0 or not dirExists(path):
    return false
  fileExists(path / "pyproject.toml") and
    dirExists(path / "tribal_village_env") and
    fileExists(path / "tribal_village_env" / "coworld" / "server.py")

proc validateAdventurerSlot*(slot: int) =
  ## Raises when an adventurer slot is outside the shared engine v1 slot range.
  if slot < 0 or slot >= FortressAdventurerSlots:
    raise newException(
      ValueError,
      "adventurer slot must be between 0 and " & $(FortressAdventurerSlots - 1)
    )

proc validateFortressEngineConfig*(config: FortressEngineConfig) =
  ## Raises when the selected shared-engine config is inconsistent.
  if config.adventurerRole.strip().len == 0:
    raise newException(ValueError, "adventurerRole must not be empty")
  if config.worldWidth < QuestAdventureCropTiles or
      config.worldHeight < QuestAdventureCropTiles:
    raise newException(ValueError, "Fortress world must fit the Quest crop")
  if config.adventurerSlots < 1 or
      config.adventurerSlots > FortressAdventurerSlots:
    raise newException(
      ValueError,
      "adventurerSlots must be between 1 and " & $FortressAdventurerSlots
    )
  if config.path.strip().len == 0:
    raise newException(ValueError, "fortressEnginePath must not be empty")
  if not config.path.isLikelyFortressEngineCheckout():
    raise newException(
      ValueError,
      "fortressEnginePath does not look like coworld-tribal-fortress: " &
        config.path
    )

proc moveName*(move: AdventurerMove): string =
  ## Returns the stable action value for one adventurer movement direction.
  $move

proc adventurerMoveFromMask*(mask: uint8): AdventurerMove =
  ## Converts BitWorld direction bits into shared-engine adventurer movement.
  let
    north = (mask and ButtonUp) != 0 and (mask and ButtonDown) == 0
    south = (mask and ButtonDown) != 0 and (mask and ButtonUp) == 0
    west = (mask and ButtonLeft) != 0 and (mask and ButtonRight) == 0
    east = (mask and ButtonRight) != 0 and (mask and ButtonLeft) == 0
  if north and west:
    MoveNW
  elif north and east:
    MoveNE
  elif south and west:
    MoveSW
  elif south and east:
    MoveSE
  elif north:
    MoveN
  elif south:
    MoveS
  elif west:
    MoveW
  elif east:
    MoveE
  else:
    MoveNone

proc adventurerInputJson*(mask: uint8): string =
  ## Builds the in-process action payload Quest maps from /player input.
  let node = %*{
    "type": AdventurerInputType,
    "control_profile": AdventurerControlProfile,
    "move": mask.adventurerMoveFromMask().moveName(),
    "attack": (mask and ButtonA) != 0,
    "use": (mask and ButtonB) != 0,
    "buttons": {
      "up": (mask and ButtonUp) != 0,
      "down": (mask and ButtonDown) != 0,
      "left": (mask and ButtonLeft) != 0,
      "right": (mask and ButtonRight) != 0,
      "a": (mask and ButtonA) != 0,
      "b": (mask and ButtonB) != 0
    }
  }
  $node

proc adventurerRawActionJson*(action: int): string =
  ## Builds a raw shared-engine action payload for tests and debugging.
  $(%*{
    "type": AdventurerInputType,
    "control_profile": AdventurerControlProfile,
    "raw_action": action
  })

proc getString(node: JsonNode, names: openArray[string], default = ""): string =
  for name in names:
    if node.hasKey(name) and node[name].kind == JString:
      return node[name].getStr()
  default

proc getInt(node: JsonNode, names: openArray[string], default = 0): int =
  for name in names:
    if node.hasKey(name) and node[name].kind == JInt:
      return node[name].getInt()
  default

proc getBool(node: JsonNode, names: openArray[string], default = false): bool =
  for name in names:
    if node.hasKey(name) and node[name].kind == JBool:
      return node[name].getBool()
  default

proc cropOrigin(crop: JsonNode): tuple[x, y: int] =
  ## Reads both legacy flat origin fields and Fortress view_plane.origin.
  if crop.hasKey("origin") and crop["origin"].kind == JObject:
    return (
      x: crop["origin"].getInt(["x"], 0),
      y: crop["origin"].getInt(["y"], 0)
    )
  (
    x: crop.getInt(["origin_x", "originX"], 0),
    y: crop.getInt(["origin_y", "originY"], 0)
  )

proc parseFortressAdventurerObservation*(
  text: string
): FortressAdventurerObservation =
  ## Parses the stable fields Quest needs from one engine adventurer tick.
  let node = parseJson(text)
  if node.kind != JObject:
    raise newException(
      ValueError,
      "adventurer observation must be a JSON object"
    )
  result.agentId = node.getInt(["agent_id", "agentId"], -1)
  result.teamId = node.getInt(["team_id", "teamId"], -1)
  result.civilization = node.getString(["civilization", "civ"])
  result.role = node.getString(["role"])
  result.hp = node.getInt(["hp", "health"], 0)
  result.maxHp = node.getInt(["max_hp", "maxHp"], result.hp)
  result.status = node.getString(["status"])
  result.done = node.getBool(["done"])
  if node.hasKey("position") and node["position"].kind == JObject:
    result.x = node["position"].getInt(["x"], 0)
    result.y = node["position"].getInt(["y"], 0)
  else:
    result.x = node.getInt(["x"], 0)
    result.y = node.getInt(["y"], 0)
  let crop =
    if node.hasKey("view_plane") and node["view_plane"].kind == JObject:
      node["view_plane"]
    elif node.hasKey("crop") and node["crop"].kind == JObject:
      node["crop"]
    else:
      node
  let origin = crop.cropOrigin()
  result.originX = origin.x
  result.originY = origin.y
  result.cropWidth = crop.getInt(["width"], QuestAdventureCropTiles)
  result.cropHeight = crop.getInt(["height"], QuestAdventureCropTiles)
