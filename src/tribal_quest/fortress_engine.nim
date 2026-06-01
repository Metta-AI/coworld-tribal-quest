import std/[os, strutils]

const
  FortressEnginePathEnv* = "TRIBAL_FORTRESS_PATH"
  DefaultFortressCheckoutDir* = "../coworld-tribal-fortress"
  FortressWorldWidthTiles* = 768
  FortressWorldHeightTiles* = 480
  FortressTownTokenSlots* = 8
  FortressTownAgentsPerTeam* = 200
  FortressAdventurerSlots* = 64
  QuestAdventureCropTiles* = 21
  QuestSpriteTilePixels* = 16
  QuestSpriteViewportPixels* = QuestAdventureCropTiles * QuestSpriteTilePixels

type
  FortressEngineConfig* = object
    path*: string
    worldWidth*: int
    worldHeight*: int
    townAgentsPerTeam*: int
    adventurerSlots*: int

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
    worldWidth: FortressWorldWidthTiles,
    worldHeight: FortressWorldHeightTiles,
    townAgentsPerTeam: FortressTownAgentsPerTeam,
    adventurerSlots: FortressAdventurerSlots
  )

proc isLikelyFortressEngineCheckout*(path: string): bool =
  ## Returns true when a path looks like the sibling Fortress repo/package.
  if path.len == 0 or not dirExists(path):
    return false
  fileExists(path / "src" / "tribal_village_engine.nim")

proc validateAdventurerSlot*(slot: int) =
  ## Raises when an adventurer slot is outside the shared engine v1 slot range.
  if slot < 0 or slot >= FortressAdventurerSlots:
    raise newException(
      ValueError,
      "adventurer slot must be between 0 and " & $(FortressAdventurerSlots - 1)
    )

proc validateFortressEngineConfig*(config: FortressEngineConfig) =
  ## Raises when the selected shared-engine config is inconsistent.
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
      "fortressEnginePath does not expose src/tribal_village_engine.nim: " &
        config.path
    )
