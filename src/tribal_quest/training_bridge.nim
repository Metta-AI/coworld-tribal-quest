## One certified Quest adventurer seat against the bundled adventurer player.
## Uses the same Fortress engine, button masks, view cells, and score as /player.

import std/[json, os, strutils]
import tribal_quest/[baseline, contract, fortress_engine, protocol, scoring]

const Masks = [
  0'u8, ButtonUp, ButtonDown, ButtonLeft, ButtonRight,
  ButtonUp or ButtonA, ButtonDown or ButtonA, ButtonLeft or ButtonA,
  ButtonRight or ButtonA, ButtonUp or ButtonB, ButtonDown or ButtonB,
  ButtonLeft or ButtonB, ButtonRight or ButtonB
]

var
  engine: FortressEngine
  progress: array[QuestLeagueMaxPlayerCount, QuestProgress]
  playerCount = QuestLeagueMinPlayerCount
  controlledSlot: int
  maxSteps = 3000

proc seedOf(value: string): int =
  var hash = 14695981039346656037'u64
  for ch in value:
    hash = (hash xor uint64(ord(ch))) * 1099511628211'u64
  int(hash and 0x7fffffff'u64)

proc canonicalMask(mask: uint8): uint8 =
  let direction = mask and 15'u8
  if (mask and ButtonA) != 0: return direction or ButtonA
  if (mask and ButtonB) != 0: return direction or ButtonB
  direction

proc current(): JsonNode =
  var cells: array[QuestAdventureCropTiles * QuestAdventureCropTiles, uint8]
  let view = engine.adventurerViewCells(controlledSlot, cells)
  var rows = newJArray()
  for y in 0 ..< QuestAdventureCropTiles:
    var row = ""
    for x in 0 ..< QuestAdventureCropTiles:
      row.add(toHex(int(cells[y * QuestAdventureCropTiles + x]), 1))
    rows.add(%row)
  let scene = %*{
    "step": engine.tick, "max_steps": maxSteps,
    "position": {"x": view.x, "y": view.y},
    "hp": view.hp, "max_hp": view.maxHp,
    "palette_rows": rows
  }
  var choices = newJArray()
  for mask in Masks:
    choices.add(%*{"buttons": int(mask)})
  %*{
    "kind": "decision", "game": "tribal-fortress-quest",
    "decision_id": engine.tick, "seat": 0, "engine_seat": controlledSlot,
    "turn": engine.tick, "semantic_view": scene, "inbox": [],
    "messages": [
      {"role": "system", "content": "Explore and survive. Choose one legal adventurer button mask."},
      {"role": "user", "content": $scene}
    ],
    "speech_messages": [], "action_schema": {"enum": choices},
    "typed_question": newJNull()
  }

proc encoding(): JsonNode =
  var cells: array[QuestAdventureCropTiles * QuestAdventureCropTiles, uint8]
  let view = engine.adventurerViewCells(controlledSlot, cells)
  var values = %*[
    float(engine.tick) / float(maxSteps),
    float(view.x) / float(defaultFortressEngineConfig().worldWidth),
    float(view.y) / float(defaultFortressEngineConfig().worldHeight),
    float(view.hp) / float(view.maxHp),
    float(controlledSlot) / float(playerCount)
  ]
  for cell in cells:
    values.add(%(float(cell) / 15.0))
  var actions = newJArray()
  for mask in Masks:
    actions.add(%*{"buttons": int(mask)})
  %*{"decision_id": engine.tick, "values": values, "actions": actions}

proc terminal(): JsonNode =
  let score = progress[controlledSlot].questScore()
  %*{
    "kind": "terminal", "scores": {"0": score},
    "utilities": {"0": float(score) / float(11 * maxSteps)}
  }

proc reset(request: JsonNode): JsonNode =
  doAssert request["players"].getInt() == 1
  engine.close()
  let seed = seedOf(request["seed"].getStr())
  controlledSlot = seed mod playerCount
  engine = initFortressEngine(questFortressEngineConfig(seed, maxSteps))
  for slot in 0 ..< playerCount:
    doAssert engine.claimAdventurer(slot, slot) >= 0
    progress[slot] = initQuestProgress()
  current()

proc handle(request: JsonNode): JsonNode =
  case request["kind"].getStr()
  of "reset": return reset(request)
  of "encode": return encoding()
  of "teacher":
    let mask = canonicalMask(chooseAdventurerMask(engine.tick, 0))
    return %*{"response": $(%*{"buttons": int(mask)})}
  of "step":
    doAssert request["decision_id"].getInt() == engine.tick
    let action = parseJson(request["response"].getStr())
    let mask = uint8(action["buttons"].getInt())
    doAssert mask in Masks
    for slot in 0 ..< playerCount:
      engine.submitAdventurerButtons(slot,
        if slot == controlledSlot: mask
        else: chooseAdventurerMask(engine.tick, 0))
    engine.step()
    for slot in 0 ..< playerCount:
      var cells: array[QuestAdventureCropTiles * QuestAdventureCropTiles, uint8]
      let view = engine.adventurerViewCells(slot, cells)
      progress[slot].observeQuestState(view.ok and not view.done, view.x, view.y)
    var cells: array[QuestAdventureCropTiles * QuestAdventureCropTiles, uint8]
    let learner = engine.adventurerViewCells(controlledSlot, cells)
    return %*{
      "kind": "accepted", "action": action,
      "observation": (if learner.done or engine.tick >= maxSteps: terminal() else: current())
    }
  else: raise newException(ValueError, "Unknown bridge command")

when isMainModule:
  let args = commandLineParams()
  if args.len > 2: quit("usage: training_bridge [players] [max_steps]", 1)
  if args.len >= 1: playerCount = parseInt(args[0])
  if args.len == 2: maxSteps = parseInt(args[1])
  doAssert playerCount in QuestLeagueMinPlayerCount .. QuestLeagueMaxPlayerCount
  doAssert maxSteps > 0
  for line in stdin.lines:
    echo $handle(parseJson(line))
