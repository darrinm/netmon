# Outage Analysis — netmon

Analysis of recorded outages on the primary monitored machine.
Monitoring window: **2026-05-19 03:44 UTC → 2026-05-20 14:57 UTC** (~35h),
86,990 metric samples, **26 outages**, 22 post-mortems.

## Headline

**Every recorded "outage" is the Mac's built-in Ethernet link (`en0`)
physically dropping and re-negotiating.** Not the ISP, not Wi-Fi, not
congestion, not a measurement artifact.

## Evidence

1. **All 26 outages are identical.** 100% packet loss, type `connectivity`,
   recorded duration a near-constant 3.0–3.5s. Not one sustained outage.

2. **Latency is a clean cliff, not a ramp.** Latency holds steady at ~1.8ms,
   drops straight to 100% loss, and returns to the *exact* same baseline.
   No congestion build-up → rules out bufferbloat / saturation / ISP
   congestion.

3. **macOS confirms each one.** All 22 post-mortems contain an
   `NWPathMonitor` `networkPathUnsatisfied` event within 1–4s of the
   outage. The OS itself declared "no usable network path."

4. **The kernel logged the cause** (2 of 26 outages still in `log`
   retention; the rest rolled out):

   ```
   07:55:31.995  kernel: intf=en0 event=link_off
   07:55:36.017  kernel: intf=en0 event=link_on     → 4.022s
   07:55:50.995  kernel: intf=en0 event=link_off
   07:55:55.017  kernel: intf=en0 event=link_on     → 4.022s
   ```

   Both link-downs lasted **exactly 4.022 seconds — identical to the
   millisecond.** `configd` simultaneously reported
   `DHCP en0: status = 'media inactive'`. A random physical fault gives
   *variable* durations; an exact-to-the-ms recovery indicates a
   deterministic state machine — an autonegotiation cycle.

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

## Tooling follow-ups (built)

- **LinkEventMonitor** — netmon now tails the unified log for
  `en0` `link_off`/`link_on` and records exact link-down durations into
  every post-mortem, so we no longer depend on `log show` retention.
- **Gateway monitoring** — netmon now pings the default gateway
  concurrently with the internet target each tick, and the outage detail
  shows a local-vs-upstream scope verdict.
