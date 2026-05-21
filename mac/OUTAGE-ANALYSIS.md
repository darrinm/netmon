# Outage Analysis — netmon

Analysis of recorded outages on the primary monitored machine.
Outages span **2026-05-19 04:21 UTC → 2026-05-21 13:59 UTC** — **30
outages** over ~2 days, all with the identical signature below.

## Headline

**Every recorded "outage" is the Mac's built-in Ethernet link (`en0`)
physically dropping and re-negotiating.** Not the ISP, not Wi-Fi, not
congestion, not a measurement artifact.

## Evidence

1. **All 30 outages are identical.** 100% packet loss, type `connectivity`,
   recorded duration a near-constant 3.0–4.1s. Not one sustained outage.

2. **Latency is a clean cliff, not a ramp.** Latency holds steady at ~1.8ms,
   drops straight to 100% loss, and returns to the *exact* same baseline.
   No congestion build-up → rules out bufferbloat / saturation / ISP
   congestion.

3. **macOS confirms each one.** Every post-mortem contains an
   `NWPathMonitor` `networkPathUnsatisfied` event within 1–4s of the
   outage. The OS itself declared "no usable network path."

4. **The kernel logged the cause.** Initially recovered from `log show`
   for 2 outages; netmon's `LinkEventMonitor` now captures every one
   live. Five `en0` link-down intervals measured so far:

   ```
   2026-05-20 07:55:31.995 → 36.017   4.022s
   2026-05-20 07:55:50.995 → 55.017   4.022s
   2026-05-21 11:53:02     → 11:53:06   4.022s
   2026-05-21 11:59:13     → 11:59:17   4.023s
   2026-05-21 13:59:33     → 13:59:36   3.022s
   ```

   `configd` simultaneously reports `DHCP en0: status = 'media inactive'`.

   **The durations are quantized: every one is a whole number of seconds
   plus a fixed ~22 ms** (4.022, 4.022, 4.022, 4.023, 3.022). A random
   physical fault produces *variable* durations. Whole-seconds-plus-a-
   constant means a deterministic state machine retrying on a 1-second
   tick — i.e. an autonegotiation cycle, not a loose cable.

5. **The NIC is the smoking gun.** `en0` is an **Apple AQC113 — an
   Aquantia 10 GbE controller** (driver `AppleEthernetAquantiaAqtion`,
   firmware `1.4.33`), negotiated **down to 1000baseT full-duplex with
   energy-efficient-ethernet enabled**. Aquantia AQC-series 10GbE
   controllers in Macs have a long, well-documented history of exactly
   this symptom — spontaneous link flaps, worst when downshifted to 1G
   and with EEE enabled.

6. **Not 8.8.8.8 rate-limiting.** The monitored host is 8.8.8.8 (which
   *would* be suspect), but a UDP DNS query to 1.1.1.1 fails at the same
   instant, and the kernel logs a real `link_off`. Different destination,
   different protocol, same drop. Ruled out.

7. **Scope is Local — the LAN gateway drops too.** netmon now pings the
   gateway (192.168.0.1) concurrently. During the 2026-05-21 outages the
   gateway — one hop away on the same LAN — went to 100% loss at the same
   instant as the internet target. Even the router is unreachable, so the
   break is the Mac↔router link, not anything upstream.

## Patterns

- Outages **cluster** (2–4 flaps within minutes) then go quiet for
  10–14h.
- Spread across all hours, including 1–2am idle time — argues *against*
  a load/thermal-only cause.
- A second interface `en22` flaps independently (a separate adapter or
  dock — not the monitored path).
- No sleep/wake events near any outage — not power-related.
- netmon slightly under-reports duration (~3.5s recorded vs 4.0s real):
  the tracker needs 2 failed samples to open and 1 good sample to close.

## Hypotheses (ranked) & tests

### H1 — Aquantia AQC113 link-stability bug, aggravated by 1G downshift + EEE  *(most likely)*
The AQC negotiating 10G/5G/2.5G down to plain 1G, with EEE, is the most
reported failure mode for this controller in Macs.
- **Test A:** Apply any pending macOS update — Apple ships AQC firmware
  inside macOS updates (currently firmware `1.4.33`).
- **Test B:** Disable EEE / "Green Ethernet" on the router/switch port.
- **Test C:** Force the link, disabling autoneg+EEE:
  `sudo ifconfig en0 media 1000baseT mediaopt full-duplex` — watch netmon.
- **Test D:** If the router has a 2.5G+ port, use it. AQC instability
  often disappears when it doesn't have to downshift all the way to 1G.

### H2 — Marginal cable / connector
Gigabit needs all 4 pairs clean.
- **Test:** Swap for a known-good Cat6, re-seat both ends, reroute away
  from power cables, bypass any wall jack / patch panel.

### H3 — Router/switch port
The port may be flaky or doing power-management cycling. The
independently-flapping `en22` hints the gear could be a common factor.
- **Test:** Move the Mac to a different port. Pull the router/switch's
  own log and correlate port up/down timestamps with netmon's outages.
  Update router firmware.

### H4 — Thermal  *(low priority)*
The AQC113 runs hot; sustained heat can drop the link. The 1–2am idle
outages argue against it, but correlate with Mac load if H1–H3 don't
resolve it.

**Recommended test order (cheap → expensive):** macOS update → disable
EEE on the router port → swap/re-seat cable → force link speed →
different port → different router.

## Tooling follow-ups (built & verified)

- **LinkEventMonitor** — netmon tails the unified log for `en0`
  `link_off`/`link_on` and records exact link-down durations into every
  post-mortem. Verified: the 2026-05-21 outages were captured live with
  exact durations, no `log show` retrieval needed.
- **Gateway monitoring** — netmon pings the default gateway concurrently
  with the internet target each tick; the outage detail shows a
  local-vs-upstream scope verdict. Verified: confirms "Local" on the
  2026-05-21 outages.
- **Post-mortem timing** — capture is delayed 15s after an outage starts.
  These outages are only ~4s long; capturing during one returned nothing
  (no default route → `route`/`traceroute` fail; `link_on` not yet
  logged). The delay lets the link recover so the snapshot is complete.
