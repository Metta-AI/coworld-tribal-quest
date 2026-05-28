# Tribal Quest on Tribal Fortress Runtime Plan

Last updated: 2026-05-28

## Summary

Make `coworld-tribal-fortress` the authoritative grid/world simulation,
add an upstream Adventure Mode there, then turn `coworld-tribal-quest`
into a thin adventure-focused consumer of the Fortress runtime.

Tribal Quest should keep the quest experience, player client, default
adventure configuration, bots, story flavor, and scoring. Tribal
Fortress should own the large shared world, civilizations, elevation,
towns, NPCs, world mechanics, and runtime protocols.

The intended end state is similar to adventure mode in Dwarf Fortress:
a player walks one adventurer through a sprawling active Fortress world
while towns, civilizations, monsters, goblin hives, camps, lairs, and
relic objectives continue to exist around them.

## Implementation Sequence

1. Pull both repositories before implementation work:
   - `/Users/relh/Code/coworld-tribal-quest`
   - `/Users/relh/Code/coworld-tribal-fortress`
2. Land runtime and protocol work first in `coworld-tribal-fortress`.
3. Land world/civilization/elevation work in `coworld-tribal-fortress`.
4. Port reusable Quest mechanics into `coworld-tribal-fortress`.
5. Switch `coworld-tribal-quest` to consume the Fortress runtime with an
   Adventure Mode config.

## Fortress Runtime Work

Add a `player_mode` Coworld config field:

- `town`: existing behavior, existing town-controller protocol, default
  for backwards compatibility.
- `adventure`: new direct-adventurer control mode.

In `adventure` mode:

- Each Coworld player slot maps to exactly one direct-controlled
  adventurer agent.
- The rest of the world continues to run under Fortress built-in AI.
- The player route remains `/player`, but accepts adventure commands
  instead of town-management commands.
- The global route remains the Fortress world view.

Fix or extend Fortress hybrid stepping so built-in AI generates default
actions for all agents, then player input overrides only the assigned
adventurer agents. This is the key runtime requirement: direct avatar
control must not disable the living town simulation.

The adventure command protocol should start small and JSON-based:

```json
{
  "type": "adventure.input",
  "move": "N",
  "attack": false,
  "use": false
}
```

The server should translate those commands into the existing Fortress
action encoding. Supported movement values should include the eight
directions plus `none`.

Adventure observations should be centered on the controlled adventurer
and include:

- adventurer agent id
- team and civilization
- position
- health and status
- inventory or held item state
- local sprite view
- nearby towns, camps, lairs, relics, enemies, and interactable objects

Existing town observations and commands must remain unchanged in
`player_mode=town`.

## Fortress World Work

Add an explicit `CivilizationKind` model with these initial values:

- `Human`
- `Elf`
- `Dwarf`
- `Orc`
- `Goblin`

Humans should keep the current baseline town behavior. Other
civilizations should be added as real world-generation and gameplay
variants, not only as labels.

Initial civilization goals:

- Elves live in forest settlements with tree houses, high platforms,
  bridges, and drawbridges.
- Dwarves live in mountains, mine, tunnel, and build smithies.
- Orcs build surface strongholds and direct or amplify nearby goblin
  raids.
- Goblins spawn readily as hostile hives, camps, patrols, and raiders.
  Goblins can become playable later, but hostile goblin ecology should
  come first.
- Humans remain the stable default civilization and compatibility
  baseline.

Increase the Fortress world size after the runtime foundation is stable.
The first target should be a `384 x 240` room under the existing terrain
size ceiling, with performance checks before merge.

Make the existing elevation concept explicit and consistent:

- low
- base
- high

Movement should use ramps, roads, bridges, drawbridges, and tunnels to
cross elevation boundaries. Visibility should respect higher ground and
obscured tiles. This should support elven tree houses and dwarf mountain
settlements without introducing a full 3D engine.

## Quest Mechanics to Upstream

Port interesting Tribal Quest mechanics into Fortress as reusable world
systems. They should enrich the shared world rather than recreate the
current Quest route as a sidecar.

Initial mechanics to upstream:

- roles for adventurers, units, and civilization-specific specialists
- mana or ability energy for adventurer powers and special units
- camps as outposts, shelters, staging sites, or civilization structures
- lairs as hostile spawn structures with pacification or reward states
- relic chains as exploration objectives tied into Fortress relic and
  victory systems

Once these systems exist in Fortress, Tribal Quest should configure and
skin them for an adventure-focused experience.

## Tribal Quest Migration

After Fortress Adventure Mode is merged and usable, change Tribal Quest
from a standalone BitWorld-style simulation into a Fortress runtime
consumer.

The first migration should use the existing Fortress Python package and
Coworld server path. Do not block the first version on extracting a Nimble
package. Add a native Nim package boundary later only if direct Nim reuse
is still needed.

Tribal Quest should provide:

- a Coworld manifest that launches Fortress in `player_mode=adventure`
- a Quest/default variant config
- an adventure-focused player client
- story and scoring defaults
- bundled bots or reference players
- documentation for the Quest experience

Tribal Quest should stop owning duplicated world simulation once the
Fortress-backed adventure path works.

## Pull Request Breakdown

Suggested PR sequence:

1. Fortress Adventure Mode runtime foundation.
2. Fortress fantasy civilization and elevation foundation.
3. Fortress camps, lairs, relic chains, roles, and mana systems.
4. Tribal Quest Fortress-runtime consumer migration.

The first Fortress PR should be kept focused on the runtime contract:
`player_mode`, direct adventurer control, hybrid action override, and
backwards-compatible town mode.

## Test Plan

Fortress validation:

```sh
make check
timeout 15s nim r -d:release --path:src tribal_village.nim
make test-nim
```

Add targeted Fortress tests for:

- `player_mode=town` preserving current town commands and observations
- `player_mode=adventure` assigning one direct adventurer per player slot
- duplicate player-slot connection handling
- direct movement, attack, and use commands
- hybrid stepping where AI controls non-adventurers and player input
  overrides only assigned adventurers
- civilization assignment and world-generation invariants
- elf tree-house connectivity
- dwarf mountain settlement connectivity
- orc influence over goblin raiding
- hostile goblin hive spawning
- low/base/high elevation traversal and visibility

Tribal Quest validation after migration:

```sh
git diff --check
```

Then smoke the Quest manifest against the Fortress runtime:

- local game image starts
- `/client/player` opens the adventure client
- `/client/global` opens the Fortress world view
- a player can move the adventurer
- towns and NPCs continue acting while the player moves
- bundled reference bots still run or are intentionally replaced

## Assumptions

- Fortress remains backwards compatible by defaulting to `player_mode=town`.
- Adventure Mode uses Fortress JSON/view-plane protocols, not the old
  BitWorld binary sprite protocol.
- Quest mechanics are upstreamed into Fortress before Quest depends on
  them.
- The first Quest consumer uses the existing Fortress Python package and
  Coworld server boundary.
- A Nimble package extraction is optional follow-up work, not a blocker
  for the first shared-runtime milestone.
