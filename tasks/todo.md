# CPU investigation — Netmon (2026-07-25)

## Findings (measured, not inferred)

Sustained CPU over a 60s window, uptime 18 days:

| Process | CPU |
|---|---|
| WindowServer | 74.8% |
| **Netmon** | **24.1%** |
| diagnosticd | 14.5% |
| Netmon's `log stream` child | 8.8% |

`launchservicesd` was the original suspect and is **not** implicated:
251 CPU-minutes over 18 days (~0.95% avg), 0.0–1.7% live.

### Root cause A — 10 Hz chart re-render with nothing on screen

`Sparkline.swift:15` and `MainView.swift:175` both run
`TimelineView(.periodic(from: .now, by: 0.1))`, rebuilding a full Swift
`Chart` (AreaMark + LineMark `ForEach`, spline-interpolated) ten times a
second.

SwiftUI keeps `MenuBarExtra` popover content instantiated after the popover
is dismissed, so this never stops. Verified: Netmon had **zero** windows open
(`System Events` window count = 0) while burning 24% CPU.

`sample 13472` (10s, 7094 samples) attributes it clearly:

| Binary | Samples |
|---|---|
| SwiftUICore | 1347 |
| libswiftCore | 1192 |
| Charts | 1038 |
| AppKit | 823 |
| QuartzCore | 298 |
| *Netmon's own code* | *277* |

`Sparkline` appears 190×; `RecentLatencyChart` 0× — so it is the popover.
Hot path is `UC::DriverCore::continueProcessing` → `CA::Transaction::commit()`
→ `CA::Render::Encoder::send_message` → `mach_msg`, which is why WindowServer
is coupled to it.

Amplifier: `intervalSeconds = 1` in prefs (code default is 30), so the 5-min
window holds ~207 points instead of ~10 → ~4,100 spline mark-evals/sec/chart.

### Root cause B — unindexed log predicate

`LinkEventMonitor.swift:35` filters on `eventMessage CONTAINS`, which forces
the log system to format *every* system-wide message before matching.

Measured (20s each, `/usr/bin/log` directly):

| Predicate | CPU |
|---|---|
| broad (current) | 10.9% |
| `process == "kernel" AND (...)` | 0.7% |
| union of 4 processes AND (...) | 0.3% |

The union is both cheaper and safer than pinning to one process.

### Investigated and deliberately NOT changed

- `MetricStore.insertMetric` runs `SELECT COUNT(*)` on every insert with the
  table at its 100k cap. Benchmarked at **0.65ms** (covering-index scan),
  ~0.05% CPU at this rate. A smell, not a cost. Left alone.
- ~121k `/sbin/ping` spawns/day from `intervalSeconds = 1`. Measured at
  ~0.6% of a core total. Not worth restructuring.
- `intervalSeconds = 1` itself is a monitoring-resolution tradeoff and is the
  user's call, not a bug. Left alone.

## Plan

- [x] Add `LiveTimeline` — a timeline that ticks only while its host window is
      actually on screen (occlusion + visibility observed via `NSViewRepresentable`)
- [x] Use it in `Sparkline.swift`
- [x] Use it in `MainView.swift` (`RecentLatencyChart`)
- [x] Narrow the `LinkEventMonitor` predicate to an indexed process union
- [x] Build
- [x] Verify: measure Netmon + log-stream CPU before/after

## Open caveat

No real `link_off`/`link_on` event exists in the current 48h log store (the
ASUS switch fix stopped the flapping), and the literal isn't recoverable from
`*.kc` kernel collections. So the *process* that emits these is taken from
`OUTAGE-ANALYSIS.md` ("the kernel logs a real `link_off`") rather than
observed directly. The 4-process union is the hedge. Re-verify next time a
link event actually occurs:

```sh
/usr/bin/log show --last 1h --style ndjson \
  --predicate 'eventMessage CONTAINS "event=link_"' \
  | python3 -c "import sys,json; [print(json.loads(l).get('processImagePath')) for l in sys.stdin if l.strip().startswith('{')]"
```

Note: `log` is aliased to `git log` in this shell — always use `/usr/bin/log`.

## Results (measured, same 60–90s methodology as the baseline)

| Process | Before | After | |
|---|---|---|---|
| Netmon | 24.1% | **2.9%** | ~8x |
| `log stream` child | 8.8% | **0.6%** | ~15x |
| diagnosticd | 14.5% | **0.3%** | ~48x |
| WindowServer | 74.8% | **54.3%** | −20 pts |

~46 points of CPU recovered, roughly half a core.

`diagnosticd` collapsing to 0.3% is the retrospective proof that the
unindexed predicate was driving it. The earlier attempt to measure that
marginally came out *negative* because the always-running stream was a
constant in every trial — the A/B could never isolate what only removing it
would reveal.

### Gate verified in both directions

Toggling the popover via the AX API, measuring Netmon each time:

| State | CPU |
|---|---|
| popover closed | 1.7% |
| **popover open** | **22.5%** |
| popover closed again | 3.1% |

So the 10 Hz smooth scroll is fully intact when visible — the fix removes the
cost only when nothing is on screen. No behaviour was traded away.

## Orphaned `log stream` child — found while verifying, then fixed

Killing the old app left PID 13484 reparented to launchd, still running the
expensive predicate at ~4.8% CPU, 18 days elapsed.

Worse than first assumed: **nothing called `AppModel.stop()` at all**, so the
child leaked on *every* exit including an ordinary Quit — not just crashes. It
survives its parent because `log stream` only discovers the closed pipe when a
write fails, and this predicate matches so rarely it may never write.

Fixed in three layers, since no single one covers everything:

- `applicationShouldTerminate` → Quit, logout, restart. Returns
  `.terminateLater` so the async stop isn't raced by AppKit teardown.
- `DispatchSource` signal handlers (SIGTERM/SIGINT/SIGHUP) → `kill`, and
  terminations that bypass AppKit. Default disposition is `SIG_IGN`'d first,
  or the process dies before the source ever runs.
- `LinkEventMonitor.reapOrphans()` at startup → the only possible cover for
  SIGKILL and crashes. Identifies orphans by ppid 1, so a concurrently running
  instance's child is never a candidate.

Verified by killing the app three ways:

| Path | App | Child | Orphans after |
|---|---|---|---|
| Quit | dies | **dies** | none |
| SIGTERM | dies | **dies** | none |
| SIGKILL | dies | survives (nothing can run) | **reaped on next launch** |

## Latent deadlock in `Subprocess.capture` — found by the above, fixed

`reapOrphans()` initially hung the app at launch: no `log stream` child ever
spawned, and a `/bin/ps` sat blocked for 37s.

`Subprocess.capture` called `waitUntilExit()` *before* draining the pipe. A
pipe holds ~64KB; a full `ps -Ao pid=,ppid=,args=` listing is ~270KB. So `ps`
blocked writing and `waitUntilExit()` waited on a child that could never
finish. Every existing caller had the same latent bug — this was simply the
first output large enough to cross the threshold. Fixed by draining first,
which also covers `PostMortemCollector`'s `traceroute`/`route` calls.

## Final measured state

| Process | Before | After |
|---|---|---|
| Netmon | 24.1% | **1.7%** |
| `log stream` child | 8.8% | **0.6%** |
| diagnosticd | 14.5% | **0.4%** |
| WindowServer | 74.8% | **54.4%** |

Metric collection confirmed still running after all changes.
