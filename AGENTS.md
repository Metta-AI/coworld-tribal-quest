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
nimby use 2.2.10
nimby sync -g nimby.lock
python3 scripts/validate_component.py
python3 scripts/validate_lock.py
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

Release and CI dependency installs must use `nimby.lock`. Do not replace the
lock with range-resolved `nimble install` in Docker or CI.

## Disposable QA Storage

This guidance applies only to this repository's first-party diagnostics, not
vendored/third-party code or other repositories.

- Default disposable diagnostic/audit logs, screenshots, frame dumps and
  browser reports to the OS temporary directory in an application-specific,
  unique per-run subdirectory, such as `coworld-tribal-quest-qa-<unique-run-id>`.
  Use platform temporary-directory APIs or `mktemp -d`, and existing helpers
  where available; do not reuse a fixed shared QA directory.
- Respect explicit output paths, artifact URIs and intentional retention.
  Preserve retained replays, evidence, saves, checkpoints, and research
  inputs/outputs, including game trajectory/proof records. Do not silently
  classify them as disposable or move them to temporary storage.
- Bound capture duration, frame/file count and supported byte limits; check
  free space on the destination filesystem before large captures and report
  the actual artifact path. Stop or skip if space is insufficient.
- Temporary storage may share the checkout's disk and is not guaranteed to
  clear on reboot. It does not reduce live disk consumption.
- Keep live IPC/control sockets, status pointers, leases and databases at
  their required fixed locations so consumers remain compatible.
- Codex/Claude sessions, prompts, traces, histories, recovery exports, indexes
  and databases are protected archival data, never disposable game QA output.
  NEVER delete, prune, rotate, truncate, rewrite or move any of them. Do not
  redirect coding-agent storage to temporary directories.
- This policy does not authorize cleanup. Leave existing artifacts, other
  tasks' outputs untouched.
- For AGENTS.md-only changes, use documentation checks (`git diff --check`
  and diff review); do not run game builds, dependency sync or populate global
  build/dependency caches.
- Repository-specific diagnostic reference:
  `tests/test_http_artifacts.py` and
  `tests/http_artifact_writer.nim` exercise explicit HTTP results/replay
  destinations. Keep those destinations intact; route only ad hoc local QA
  logs and screenshots to a unique temporary run directory.
