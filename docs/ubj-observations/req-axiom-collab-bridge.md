# Observation: req_axiom_collab_bridge — Axiom collaboration & catalog integration (attention gates, artwork rotation, media)

> **Status: NOT demonstrated.** This note only records observations. It
> does not verify the outcome. Nothing here is a claim that either acceptance
> criterion is met. The repository has **no Axiom integration at all**.

## Observation identity and limits

- Checkout: UBJ worktree `ruixen-shell-docs-20261123-070816-a8ac1a00`,
  branch `ubj/ruixen-shell/docs-20261123-070816-a8ac1a00`, HEAD
  `7945f9aa7214181c54047c3b94edc0c92a9338e3` (2026-11-22, "fix(notch): bound
  optional ubj-today.py calls in parallel under 2s total deadline"). The tree
  was clean when observed.
- Observer: a docs-only agent iteration on 2026-11-23. It only read the
  source statically and ran `grep` over the working tree.
- Inputs: files in this checkout only. I did **not** contact the Axiom
  (MyPLM) endpoint or any ngrok tunnel. I did **not** run a live
  Quickshell/Omarchy session or take a screenshot. I ran no test suite.
  Running `git log --grep=axiom` needed sandbox approval and did not run, so
  commit history was **not** searched. Only the working tree was.
- UBJ's verify phase runs `bash tests/run-all.sh` separately. That suite
  has no Axiom test, so a pass says nothing about this outcome.

## 1. Evidence that exists in the repository today

- `grep -rIil axiom --exclude-dir=.git .` returned **zero files**. A grep
  for `myplm`, `ngrok` and `midjourney` also matched nothing. No source,
  test, doc or backlog entry (`.claude/BACKLOG.md`) mentions Axiom.
- Nearby surfaces that the outcome could build on, none of which reads
  Axiom:
  - **Attention gates (UBJ, not Axiom):**
    `bars/widgets/ruixen.notch/ubj-today.py` and
    `bars/widgets/ruixen.notch/UbjTodayPanel.qml` show an ATTENTION list
    (waiting, failing, unpushed) from UBJ's loopback API only
    (`http://127.0.0.1:<api_port>`, no proxy, redirects refused). Offline
    and timeout states are rendered. `tests/notch-ubj-today.sh` (registered
    in `tests/run-all.sh`) checks this against a local mock. See
    `docs/ubj-observations/req-ad220256e706.md` for the earlier observation
    of this panel. None of it queries Axiom `attention` or `work_board`.
  - **Artwork rotation (local folder only):**
    `ruixen.wallpaper/wallpaper-rotation.py` defaults to
    `~/Pictures/ruixen-wallpapers` and only accepts an absolute local
    folder ("Choose an artwork folder"). It makes no network calls.
    `ruixen.wallpaper/WallpaperRotation.qml`,
    `ruixen.wallpaper/WallpaperRotationState.qml`,
    `ruixen.launcher/extensions/wallpaper-shuffle/WallpaperShuffleContent.qml`
    and `tests/wallpaper-rotation.sh` / `tests/wallpaper-rotation.py` cover
    this local rotation. Nothing pulls from Axiom `images` (the Midjourney
    catalog) or `artworks`.
  - **Media:** `bars/widgets/ruixen.media/Service.qml` uses local MPRIS
    players. There is no Axiom media or catalog feed.
- The house rules this work would have to follow are in `AGENTS.md`:
  read-only, `Process`-based and never on the UI thread, bounded, with
  last-action-wins and generation guards (§4–§5). The agent IPC surface is
  in `docs/AGENT.md`.

## 2. What is missing, per declared acceptance criterion

**Criterion A: "Surfaces Axiom attention counts, work board gates, or
Midjourney artwork/media catalog feeds cleanly in the shell."**
- Missing entirely. No helper, QML panel, IPC target, config key or test
  reads from Axiom. The existing attention UI uses UBJ, not Axiom. The
  existing artwork rotation reads a local directory, not the Axiom `images`
  or `artworks` catalog.

**Criterion B: "Degrades gracefully when the remote Axiom tunnel is offline
or unreachable."**
- Cannot be observed, because no Axiom client exists. The only comparable
  pattern is `ubj-today.py`, which handles offline, 401 and timeout cases.
  That code is loopback-only by design, so it is not evidence about a
  remote tunnel.

**Open human judgment (not decided here):**
- Whether the shell should call the Axiom MCP/ngrok endpoint directly, or
  go through UBJ's existing Axiom bridge (the UBJ MCP exposes
  `get_axiom_status` / `search_axiom` / `axiom_request`). Going through UBJ
  would keep the shell loopback-only, matching `ubj-today.py`.
- Where Axiom credentials would come from. This involves secrets and auth,
  so it needs an operator decision before any implementation.

## 3. Smallest next check that would settle it

1. Confirm the absence across history too:
   `git log --oneline -i --grep=axiom` and
   `git log -p -S axiom --oneline | head` in this repo. An empty result
   means the outcome was never started here.
2. With the operator choosing a source (direct Axiom vs. through UBJ),
   observe one live read outside the shell first, for example the UBJ
   `get_axiom_status` tool, or the Axiom `attention` call. Record the
   response shape and the offline error shape (tunnel stopped).
3. Only after a Ruixen helper exists: run a mocked contract test in the
   style of `tests/notch-ubj-today.sh` covering online, unauthenticated and
   unreachable cases. Then do a real `omarchy restart shell`, with a
   screenshot of the panel both online and with the tunnel down, plus a
   `journalctl --user -b 0` check, per `AGENTS.md` §8.

Until steps 2–3 produce evidence, this outcome stays **not demonstrated**.
