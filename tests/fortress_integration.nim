import std/sets

import tribal_quest/fortress_engine
import tribal_quest/gridworld_sprites
import tribal_quest/protocol
import tribal_quest/sprite_packets

proc runIntegration() =
  var config = questFortressEngineConfig(seed = 726896, maxSteps = 2)
  config.validateQuestEngineContract()
  doAssert config.townAgentsPerTeam > 0
  doAssert config.adventurerSlots == QuestAdventurerSlots

  var engine = initFortressEngine(config)
  try:
    let agentId = engine.claimAdventurer(0, 0)
    doAssert agentId >= 0
    engine.submitAdventurerButtons(0, ButtonRight or ButtonA)
    engine.step()

    var
      registry = initQuestSpriteRegistry("data")
      known = initHashSet[int]()
    let frame = engine.buildAdventurerSpriteFrame(0, registry, known)
    let summary = parseSpritePacketSummary(frame)
    doAssert summary.clearObjects == 1
    doAssert summary.viewportCount == 1
    doAssert summary.viewportWidth == QuestSpriteViewportPixels
    doAssert summary.viewportHeight == QuestSpriteViewportPixels
    doAssert summary.objectSpriteIds.len > 0
    doAssert engine.releaseAdventurer(0)
  finally:
    engine.close()

when isMainModule:
  runIntegration()
  echo "Fortress integration passed"
