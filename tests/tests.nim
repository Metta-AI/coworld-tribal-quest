import std/[json, os, sets]

import tribal_quest/fortress_engine
import tribal_quest/protocol
import tribal_quest/sprite_packets

const RootDir = currentSourcePath.parentDir.parentDir

template expectValueError(body: untyped, message: string) =
  var rejected = false
  try:
    body
  except ValueError:
    rejected = true
  doAssert rejected, message

proc testAdventurerInputPayloads() =
  let mask = ButtonUp or ButtonRight or ButtonA
  var parsedMask: uint8
  doAssert playerMaskFromPacket("\x84" & char(mask), parsedMask)
  doAssert parsedMask == mask
  doAssert playerMaskFromPacket(spriteInputPacket(mask), parsedMask)
  doAssert parsedMask == mask
  doAssert not playerMaskFromPacket("\x00" & char(mask), parsedMask)

proc testSpritePacketConstruction() =
  var
    packet: seq[uint8] = @[]
    known = initHashSet[int]()
  let selected = generatedSprite(1, "selected player human")

  packet.addClearObjects()
  packet.addLayer(SpriteLayerMap, SpriteLayerTypeMap, SpriteLayerFlagZoomable)
  packet.addViewport(SpriteLayerMap, QuestSpriteViewportPixels, QuestSpriteViewportPixels)
  packet.addSpriteIfNeeded(known, selected)
  packet.addObject(100, 10, 12, 20, SpriteLayerMap, selected.id)

  let summary = parseSpritePacketSummary(packet.toPacketString())
  doAssert summary.clearObjects == 1
  doAssert summary.layerCount == 1
  doAssert summary.viewportCount == 1
  doAssert summary.viewportWidth == QuestSpriteViewportPixels
  doAssert summary.viewportHeight == QuestSpriteViewportPixels
  doAssert "selected player human" in summary.spriteLabels
  doAssert selected.id in summary.definedSprites
  for spriteId in summary.objectSpriteIds:
    doAssert spriteId in summary.definedSprites

proc testGeneratedSpritePlaceholder() =
  let sprite = generatedSprite(7, "missing asset wolf")
  doAssert sprite.id == 7
  doAssert sprite.width == 16
  doAssert sprite.height == 16
  doAssert sprite.pixels.len == 16 * 16 * 4
  var nonTransparent = 0
  for i in countup(3, sprite.pixels.high, 4):
    if sprite.pixels[i] != 0:
      inc nonTransparent
  doAssert nonTransparent > 0

proc testFortressEngineConfigValidation() =
  let config = defaultFortressEngineConfig()
  doAssert config.path.len == 0
  doAssert config.worldWidth == FortressWorldWidthTiles
  doAssert config.worldHeight == FortressWorldHeightTiles
  doAssert config.townAgentsPerTeam == FortressTownAgentsPerTeam
  doAssert config.adventurerSlots == FortressAdventurerSlots

  expectValueError(validateAdventurerSlot(-1), "negative slot must be rejected")
  expectValueError(
    validateAdventurerSlot(FortressAdventurerSlots),
    "Fortress adventurer slots should be capped at 64"
  )
  validateAdventurerSlot(FortressAdventurerSlots - 1)

  var blankPath = config
  expectValueError(
    blankPath.validateFortressEngineConfig(),
    "fortress mode requires a concrete engine path"
  )

  let tempRoot = getTempDir() / "tribal_quest_fortress_engine_test"
  if dirExists(tempRoot):
    removeDir(tempRoot)
  createDir(tempRoot)
  createDir(tempRoot / "src")
  writeFile(tempRoot / "src" / "tribal_village_engine.nim", "")
  doAssert tempRoot.isLikelyFortressEngineCheckout()

  var engineConfig = config
  engineConfig.path = tempRoot
  engineConfig.validateFortressEngineConfig()
  removeDir(tempRoot)

proc testDefaultFortressPath() =
  let expected = RootDir / DefaultFortressCheckoutDir
  doAssert defaultFortressEnginePath(RootDir) == expected

proc testManifestHasNoRuntimeSelector() =
  let
    manifest = parseJson(readFile(RootDir / "coworld_manifest.json"))
    properties = manifest["game"]["config_schema"]["properties"]
    smokeConfig = manifest["variants"][0]["game_config"]
  doAssert not properties.hasKey("worldRuntime")
  doAssert not properties.hasKey("adventurerRole")
  doAssert not smokeConfig.hasKey("worldRuntime")

when isMainModule:
  testAdventurerInputPayloads()
  testSpritePacketConstruction()
  testGeneratedSpritePlaceholder()
  testFortressEngineConfigValidation()
  testDefaultFortressPath()
  testManifestHasNoRuntimeSelector()
  echo "All tests passed"
