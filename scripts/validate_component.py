#!/usr/bin/env python3
"""Validate the checked-in Quest component descriptor without extra packages."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DESCRIPTOR = ROOT / "quest_component.json"
SCHEMA = ROOT / "quest_component.schema.json"

EXPECTED_TOP_LEVEL = {
    "$schema",
    "component_version",
    "component",
    "coworld",
    "mode",
    "entrypoint",
    "engine_module",
    "engine_runtime",
    "league",
    "config_contract",
    "results_contract",
    "replay_contract",
    "global_contract",
    "protocol",
    "player_route",
}
EXPECTED_CONFIG = [
    "mode",
    "tokens",
    "players",
    "max_steps",
    "seed",
    "steps_per_second",
    "player_connect_timeout_seconds",
    "num_agents",
    "team_count",
]
EXPECTED_RESULTS = [
    "mode",
    "scores",
    "steps",
    "truncation_reason",
    "names",
    "survival_ticks",
    "explored_tiles",
]


def main() -> None:
    descriptor = json.loads(DESCRIPTOR.read_text())
    schema = json.loads(SCHEMA.read_text())
    assert set(descriptor) == EXPECTED_TOP_LEVEL
    assert descriptor["$schema"] == "./quest_component.schema.json"
    assert descriptor["component_version"] == 2
    assert descriptor["component"] == "tribal_quest"
    assert descriptor["coworld"] == "tribal_fortress"
    assert descriptor["mode"] == "quest"
    assert descriptor["entrypoint"] == "src/tribal_quest.nim"
    assert descriptor["engine_module"] == "tribal_fortress_engine"
    assert descriptor["league"] == {
        "variant_id": "quest-8-adventurer",
        "player_count": 8,
        "tokens_field": "tokens",
    }
    assert descriptor["config_contract"]["required"] == EXPECTED_CONFIG
    assert descriptor["config_contract"]["players_item"] == {
        "required": ["name"],
        "additional_properties": False,
    }
    assert descriptor["config_contract"]["accepted_shared_fields"] == [
        "victory_condition"
    ]
    assert descriptor["results_contract"]["required"] == EXPECTED_RESULTS
    assert descriptor["results_contract"]["score_count"] == 8
    assert descriptor["replay_contract"] == {
        "format": "tribal-quest-replay-v1",
        "load_env": "COGAME_LOAD_REPLAY_URI",
        "client_route": "/client/replay",
        "stream_route": "/replay",
        "message_type": "text/json",
    }
    assert descriptor["global_contract"] == {
        "client_route": "/client/global",
        "stream_route": "/global",
        "protocol": "tribal-quest-global-v1",
        "init_type": "view.init",
        "update_type": "view.update",
        "message_type": "text/json",
    }
    assert schema["properties"]["config_contract"]["properties"]["required"][
        "const"
    ] == EXPECTED_CONFIG
    assert schema["properties"]["results_contract"]["properties"]["required"][
        "const"
    ] == EXPECTED_RESULTS
    assert not (ROOT / "coworld_manifest.json").exists()
    print("Quest component contract is valid")


if __name__ == "__main__":
    main()
