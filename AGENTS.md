# Tribal Quest repository guidance

Tribal Quest is the adventurer component of the canonical `tribal_fortress`
Coworld. This repository owns the Quest player surface, protocol, development
host, and integration proof. It does not own or upload a separate Coworld.

Quest depends directly on Fortress's `tribal_fortress_engine` Nim module. Keep
Quest-specific code under `src/tribal_quest/`, the development/production mode
entrypoint at `src/tribal_quest.nim`, and tests under `tests/`. Do not add a
local simulation fallback, a Python bridge, or runtime source checkout logic.

Before repository work, fetch current remote state. Do not implicitly merge or
rebase dirty or feature work. For implementation, use a clean task worktree at
current `origin/main`.

Before pushing gameplay, protocol, or shared contract changes, run:

```sh
python3 scripts/validate_component.py
nim r --path:src tests/tests.nim
python3 tests/test_http_artifacts.py
TRIBAL_FORTRESS_PATH=${TRIBAL_FORTRESS_PATH:-$(pwd)/../coworld-tribal-fortress}
bash scripts/test_with_fortress.sh
git diff --check
```

The canonical exact-revision integration and image gate runs in Fortress CI,
which pins public Quest. Public Quest CI cannot read the private Fortress repo.
If the engine module or typed API is missing from a local sibling checkout,
fail loudly; never add another runtime to make the build pass.
