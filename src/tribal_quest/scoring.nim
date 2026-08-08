import std/sets

const ExplorationScoreWeight* = 10

type
  QuestProgress* = object
    survivalTicks*: int
    visitedTiles*: HashSet[tuple[x, y: int]]

proc initQuestProgress*(): QuestProgress =
  QuestProgress(visitedTiles: initHashSet[tuple[x, y: int]]())

proc observeQuestState*(
  progress: var QuestProgress,
  alive: bool,
  x, y: int
) =
  ## Consumes authoritative Fortress view truth after an engine step. Dead or
  ## dormant agents accrue neither survival nor exploration credit.
  if not alive:
    return
  inc progress.survivalTicks
  if x >= 0 and y >= 0:
    progress.visitedTiles.incl((x: x, y: y))

proc exploredTiles*(progress: QuestProgress): int =
  progress.visitedTiles.len

proc questScore*(progress: QuestProgress): int =
  progress.survivalTicks + progress.exploredTiles * ExplorationScoreWeight
