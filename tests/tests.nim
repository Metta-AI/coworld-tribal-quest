import std/[json, os, sets]

import tribal_quest/contract
import tribal_quest/protocol
import tribal_quest/sprite_packets

const RootDir = currentSourcePath.parentDir.parentDir

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

proc testComponentDescriptor() =
  let
    component = parseJson(readFile(RootDir / "quest_component.json"))
    league = component["league"]
    config = component["config_contract"]
    results = component["results_contract"]
  doAssert component["component"].getStr() == "tribal_quest"
  doAssert component["coworld"].getStr() == "tribal_fortress"
  doAssert component["mode"].getStr() == "quest"
  doAssert component["engine_module"].getStr() == "tribal_fortress_engine"
  doAssert league["variant_id"].getStr() == "quest-8-adventurer"
  doAssert league["player_count"].getInt() == QuestLeaguePlayerCount
  doAssert config["required"].len == 9
  doAssert results["score_count"].getInt() == QuestLeaguePlayerCount
  doAssert not fileExists(RootDir / "coworld_manifest.json")

when isMainModule:
  testAdventurerInputPayloads()
  testSpritePacketConstruction()
  testGeneratedSpritePlaceholder()
  testComponentDescriptor()
  echo "All tests passed"
