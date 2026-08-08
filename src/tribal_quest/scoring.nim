import std/sets

const ExplorationScoreWeight* = 10

type
  QuestProgress* = object
    survivalTicks*: int
    visitedTiles*: HashSet[int]

proc initQuestProgress*(): QuestProgress =
  QuestProgress(visitedTiles: initHashSet[int]())

proc observeQuestState*(
  progress: var QuestProgress,
  alive: bool,
  x, y, worldWidth: int
) =
  ## Consumes authoritative Fortress view truth after an engine step. Dead or
  ## dormant agents accrue neither survival nor exploration credit.
  if not alive:
    return
  inc progress.survivalTicks
  if x >= 0 and y >= 0 and worldWidth > 0:
    progress.visitedTiles.incl(y * worldWidth + x)

proc exploredTiles*(progress: QuestProgress): int =
  progress.visitedTiles.len

proc questScore*(progress: QuestProgress): int =
  progress.survivalTicks + progress.exploredTiles * ExplorationScoreWeight
