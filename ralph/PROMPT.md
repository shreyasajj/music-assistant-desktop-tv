# Ralph loop prompt — Bigscreen Jukebox

You are running inside a Ralph loop: a fresh process each iteration. Do **exactly one task**, then stop. State lives in the repo, so the next iteration picks up where you left off.

## CANONICAL DESIGN (read before any UI task)

The approved design is the working web prototype in **`bigscreen-jukebox/`** (`index.html`, `styles.css`, `app.js`) — see `bigscreen-jukebox/README.md`. It is the **binding spec** for the look and behavior of the QML/Kirigami UI.

For any task that builds or styles UI, **first read the matching prototype file/section**, then translate it faithfully to QML:
- **Accent tokens:** `--a1 = #00e0c6`, `--a2 = #ff3da6`, bg `#07070b`. Map to `Theme.a1`/`Theme.a2`. Everything (gradients, focus rings, fills) derives from these two.
- Match layout, proportions, font sizes/weights, radii, blur/glass panels, focus states, and animations to the prototype. When the plan's QML snippets disagree with the prototype, **the prototype wins** — update the QML to match.
- **Backend → UI data contract:** the visualizer is fed `{ beat: 0..1, energy: 0..1, bars: [64] }`. The Python `AudioAnalyzer` must expose `energy`, `beat`, and `bars` (length-64 list) in exactly that shape.
- Include the prototype's components: wordmark, centered tabs, player chip + dropdown menu, **Up Next queue** panel, guest button that becomes a corner **QR card** (and shifts the queue/player chip), Search D-pad focus highlight + PLAY affordance, Lyrics active/d1/d2 scroll, Visualizer **3 modes** (radial/flow/bars) + BEAT slider + source toggle (Simulated/Mic/Live feed), and 4K scaling.

You may open the prototype in a headless browser to compare against your QML render when verifying a UI task.

## Each iteration, do this:

1. Read the plan: `docs/superpowers/plans/2026-06-28-bigscreen-jukebox.md`.
2. Find the **first task whose header is NOT marked `✅ DONE`**. That is your task.
3. **If there are no unmarked tasks left:** print `RALPH-COMPLETE: all tasks done` and stop. Do nothing else.
4. **If your task is Task 14 or Task 16** (they require the user's real Music Assistant server to verify): print `RALPH-PAUSE: Task N needs the live MA server — human required` and stop. Do NOT attempt it.
5. Otherwise, implement that ONE task by dispatching a fresh subagent with the `subagent-driven-development` skill, following the task's TDD steps exactly (write failing test → see it fail → implement → see it pass).
6. Run that task's tests. They **must pass**. If you cannot get them green, print `RALPH-BLOCKED: Task N — <reason>` and stop without committing broken code.
7. When green, commit with the task's commit message (append the Co-Authored-By trailer used elsewhere in this repo).
8. Edit the plan: change that task's header to append `✅ DONE (commit <short-hash>)`.
9. Commit the plan update. Then **stop** — do not start the next task.

## Rules
- One task per iteration. Never batch.
- Never mark a task DONE unless its tests passed.
- Never edit tasks other than the one you're implementing (except the DONE marker).
- Stay within the plan; do not invent scope.
