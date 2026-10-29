# LaneSight measurement-engine architecture — decision brief
Status: OPEN decision (prove-out phase) · 2026-10-29 · For external review

## 1. Context (for someone with no prior knowledge)
LaneSight analyzes a phone video of a bowling shot and measures ball metrics (speed, entry board, entry angle,
rev rate, pin result) plus body-form metrics, then layers coaching on top. The hard part is the **computer-vision
measurement engine**: detect/stabilize the lane, track the ball, calibrate image→lane geometry, and compute
metrics accurately. "Accurate" matters a lot — a believable-but-wrong number is considered worse than "couldn't
measure it," and small errors flip advice (a 2-board entry error changes the recommendation).

**Today:** the engine is **Python + OpenCV + numpy + MediaPipe**, running server-side on Google Cloud Run. The
phone just captures video and shows results. It's validated and in use.

## 2. The decision
We will converge on **ONE** long-term measurement engine (not a permanent server+device split). The prove-out
question: **what should that single engine be, and where should it run?**

## 3. Evidence gathered so far
- **Latency is environment-bound, not algorithmic.** Same engine code: **Cloud Run ~186–280 s p50** per shot
  (4 vCPU, scale-to-zero cold starts, synchronous) vs the **same code on a Mac (Apple Silicon) ~16 s p50** —
  ~12–17× faster on identical code. The algorithm isn't the bottleneck; the server environment is.
- **On-device is feasible and fast.** On an iPhone 17 Pro Max, a native benchmark showed: HEVC decode ~550 fps
  (9× realtime), a Vision image-registration step (the server's dominant CV cost) ~4× faster than the server,
  **peak memory 67.6 MB** (vs the server pipeline's ~2 GB — because native streams frames), **no thermal
  throttling over a 30-shot run**, negligible battery. The two risks that would kill on-device (memory, heat)
  did not materialize.
- **Accuracy bar is tolerance-based, not bit-exact.** The server itself has ~0.35–0.83 mph speed error vs
  ground-truth references. "Good enough" = within a defined tolerance band, not perfection.
- **A from-scratch native re-implementation is partway there.** A Swift/Vision re-write of the pipeline now
  runs end-to-end on the phone and produces ball speed within ~7% of the server on a test clip (19.1 vs 17.8
  mph). The remaining gap traces to one subsystem (precise impact/distance detection) not yet ported.
- **Platforms:** iOS first; Android is a likely future requirement.

## 4. Options for the single engine

### Option A — Server-only (keep the Python/OpenCV engine; phone is a thin client)
- **Pros:** zero rewrite; already validated; one codebase; any device works (just needs a camera + network).
- **Cons:** requires connectivity (no offline analysis at the lane); latency + cold-starts (the ~186–280 s
  problem, needs infra work to improve); per-shot cloud compute cost; worst at-lane UX; no path to instant
  feedback.

### Option B — Native per-platform engine (Swift/Vision on iOS now; re-written per platform later)
- **Pros:** **best on-device performance/battery/thermals** — uses Apple-Silicon accelerators (Vision,
  Accelerate, Neural Engine, GPU) that a generic CPU port can't; offline; near-zero per-shot server cost; lean
  app (no heavy CV dependency). Realizes the whole reason to go on-device.
- **Cons:** must **re-implement and re-validate** the full validated engine in Swift (CV + calibration +
  physics + form/pose); **Android later = a second native rewrite** (Kotlin + a different accelerator stack);
  during prove-out, two implementations drift and must be kept in parity.

### Option C — Portable shared core (one engine in C++ or Rust; compiled for server + every device)
- **Pros:** **write once, run everywhere** (server, iOS, future Android) — no drift, no per-platform
  re-validation; one source of truth; good for a multi-platform future.
- **Cons:** **largest upfront rewrite** — port the entire validated Python/OpenCV/numpy/MediaPipe engine to
  C++/Rust **and migrate the server onto it** (re-validating the server too); on-device it runs a **generic CPU
  algorithm that does NOT leverage the Neural Engine/Vision/GPU**, so it's likely slower/hotter/more
  battery-hungry on the phone than native (Option B); cross-platform build + interop + binary-size complexity
  (e.g. OpenCV on mobile is large).

## 5. The core trade-off
| Axis | A: Server (Python) | B: Native per-platform (Swift…) | C: Portable core (C++/Rust) |
|---|---|---|---|
| Offline / at-lane instant feedback | ✗ | ✓ | ✓ |
| On-device speed / battery / thermal | n/a | **Best** (HW accelerators) | Weaker (generic CPU) |
| Per-shot cloud cost | High | ~0 | ~0 (on device) |
| App size / deps | Lean client | Lean | Heavier |
| Upfront cost | None (status quo) | Medium (1 rewrite/platform) | **High** (rewrite + server migration) |
| Multi-platform (Android) cost | Free | Another rewrite | **Free** (recompile) |
| Accuracy path | Already there | Per-metric port + validate | Exact by construction |
| Long-term maintenance | One codebase | One per platform | **One total** |

## 6. The crux question for reviewers
If the future is **mostly iOS (+ maybe one other platform)** and **on-device performance/battery is the point**,
native (B) likely wins — the hardware optimization is the whole reason to leave the server, and a portable CPU
core throws that away. If the future is **many platforms** and **engine churn is high** (the CV keeps changing),
the single portable core (C) amortizes better despite the big rewrite and weaker per-device performance.

Also open: Rust vs C++ for a portable core (safety/interop); whether a portable core could still call platform
accelerators via an abstraction layer (hybrid); and whether improving the *server* environment (Option A) is
"good enough" if offline isn't actually required.

## 7. Specific questions to ask other sources
1. For a CV pipeline that must run fast on-device (Apple Silicon) AND ideally cross-platform, is a **native
   per-platform** engine or a **single portable C++/Rust core** the better long-term bet — given that a portable
   CPU core can't use the Neural Engine/Vision/Metal?
2. How much on-device performance (speed/battery/thermal) is typically lost by using a portable CPU core
   (C++/OpenCV) vs native Apple frameworks (Vision/Accelerate/Metal/CoreML) for classical CV + pose?
3. Is re-implementing a validated Python/OpenCV engine in Swift (and separately validating it) a worse bet than
   porting once to C++/Rust and migrating the server too? How do teams usually de-risk the re-validation?
4. If Android is 1–2 years out, does that change the native-vs-portable answer materially?
5. Is there a hybrid (portable core for the math + platform-native frontends for decode/accelerated primitives)
   that captures most of both?

## 8. Current internal lean (not binding)
Given the evidence that on-device performance is the main prize and that a portable CPU core would forfeit the
Apple accelerators, the current lean is **Option B (native)** if the platform count stays small — with Option C
reconsidered if a true multi-platform future with a fast-changing engine emerges. This is exactly what a
second opinion should pressure-test.
