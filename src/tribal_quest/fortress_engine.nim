import tribal_fortress_engine
import tribal_quest/contract

export tribal_fortress_engine, contract

proc questFortressEngineConfig*(seed, maxSteps: int): FortressEngineConfig =
  ## Starts from Fortress-owned defaults so Quest cannot drift from the world
  ## dimensions, town population, or adventurer capacity of the shared engine.
  result = defaultFortressEngineConfig(seed)
  result.maxSteps = maxSteps
  result.adventurerViewRadius = QuestAdventureCropTiles div 2

proc validateQuestEngineContract*(config: FortressEngineConfig) =
  ## Validates the small part of the Fortress engine contract Quest relies on.
  if config.maxSteps < 1:
    raise newException(ValueError, "max_steps must be positive")
  if config.adventurerSlots < QuestLeaguePlayerCount:
    raise newException(
      ValueError,
      "Fortress engine must expose at least " & $QuestLeaguePlayerCount &
        " adventurer slots"
    )
  if config.adventurerSlots > QuestAdventurerSlots:
    raise newException(
      ValueError,
      "Fortress engine exposes more than the supported " &
        $QuestAdventurerSlots & " adventurer slots"
    )
  if config.adventurerViewRadius * 2 + 1 != QuestAdventureCropTiles:
    raise newException(
      ValueError,
      "Fortress adventurer crop must be " & $QuestAdventureCropTiles &
        " tiles"
    )
