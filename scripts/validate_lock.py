#!/usr/bin/env python3
"""Validate the exact Nimby release lock without third-party packages."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "nimby.lock"
NIMBLE = ROOT / "tribal_quest.nimble"
SHA = re.compile(r"[0-9a-f]{40}")
DIRECT_PACKAGES = {"jsony", "mummy", "pixie", "supersnappy", "ws"}


def main() -> None:
    packages: dict[str, tuple[str, str, str]] = {}
    for line_number, line in enumerate(LOCK.read_text().splitlines(), start=1):
        fields = line.split()
        assert len(fields) == 4, f"nimby.lock:{line_number}: expected four fields"
        name, version, repository, commit = fields
        assert name not in packages, f"duplicate locked package: {name}"
        assert repository.startswith("https://github.com/")
        assert SHA.fullmatch(commit), f"invalid commit for {name}"
        packages[name] = (version, repository, commit)

    assert DIRECT_PACKAGES <= packages.keys()
    nimble = NIMBLE.read_text()
    for package in DIRECT_PACKAGES:
        assert re.search(rf'^requires "{package}(?:\s|\")', nimble, re.MULTILINE)
    assert 'requires "nim >= 2.2.10"' in nimble
    print(f"Quest Nimby lock is valid ({len(packages)} exact packages)")


if __name__ == "__main__":
    main()
