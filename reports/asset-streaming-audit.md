# Infinite Warfare asset-streaming audit

Date: 2026-08-21
Target: Steam `iw7_ship.exe` (48,612,264 bytes, SHA-256 `A883EE28EE9F552C63D8ED1E352F60501B2E256D8857CA178C6DD3AAE622723B`)
iwz-mod baseline: `8d5599f4c0fa17f8c2195660222ec8935db3d448`

## Scope and method

This audit covers fastfile (`.ff`) loading and preparation, image-pak streaming, transient/preload arbitration, worker-thread placement, and iwz-mod startup behavior. Evidence came from targeted source review, the current game log, both supplied GSC dumps, and bounded disassembly of a runtime image. The reverse-engineering tools map and disassemble bounded ranges; they do not copy or decode the complete 195 MiB runtime image.

The game log already confirms the expected CP pipeline: `cp_zmb`, `cp_zmb_load`, weapon transient zones, destination-map zones, custom iwz zones, and streamed model images are all observed during normal play.

## Engine and GSC pipeline

The practical loading path is:

1. GSC precaches map-owned assets and requests preload/transient zones.
2. The database thread reads and inflates fastfiles, preparing assets and adding them through `DB_AddXAsset`.
3. The image streamer independently issues background reads against image paks.
4. Transient/preload scheduling yields between database preparation and image streaming according to priority and timeout dvars.

The GSC dumps make the synchronization requirements explicit:

- `dumps/CODIW-Source/scripts/scripts/cp/maps/cp_zmb/cp_zmb.gsc:17` calls the map-local animation precache immediately; its body begins at line 194. Lines 48-50 then invoke the map precache stub and generated art/FX setup. The second dump independently shows the same sequence at `dumps/iw7-gsc-dump/decompiled/scripts/cp/maps/cp_zmb/cp_zmb.gsc:15`, lines 46-48, and line 200.
- `dumps/CODIW-Source/scripts/scripts/sp/endmission.gsc:444-472` starts next-zone preloading and frame-polls `ispreloadzonescomplete()` before proceeding.
- `dumps/CODIW-Source/scripts/scripts/sp/_autosave.gsc:457-466` also waits for preload-zone completion before saving.
- `dumps/CODIW-Source/scripts/scripts/sp/utility.gsc:8019-8035` wraps transient loads and unloads with frame-polled completion barriers.
- The map-local `cp_zmb_precache.gsc` is empty in both dumps. The map entry point instead performs its own animation precache at `dumps/CODIW-Source/scripts/scripts/cp/maps/cp_zmb/cp_zmb.gsc:194-220` and invokes generated art/FX setup at lines 48-50. Consequently, the tens of thousands of `cp_zmb` database publications are fastfile/linker content, not a redundant GSC transient loop that can simply be deferred.

These call sites rule out moving GSC precache work later or bypassing its completion barriers as a general optimization. The safe target is the engine policy underneath those barriers.

## Reverse-engineering findings

### Image-pak I/O is already SSD-friendly

`Sys_CreateFile` at `0x140CFDF50` reaches `CreateFileW` at `0x140CFE06A` with `FILE_FLAG_OVERLAPPED | FILE_FLAG_NO_BUFFERING`. The chunked reader aligns requests to 4 KiB for unbuffered I/O and caps an individual operation at 1 MiB. The runtime error path identifies it as `StreamFileReadChunked`.

This is an appropriate background-streaming design on both SATA and NVMe SSDs: asynchronous requests, no duplicate Windows cache, aligned direct I/O, and bounded request sizes. Replacing it with synchronous/buffered reads or simply enlarging every request would trade latency and memory pressure for uncertain throughput, so iwz-mod preserves this backend unchanged. Its custom-zone fallback already uses the same flags.

### Asset preparation is intentionally serialized against the streamer

The dvar registration block around `0x140341F60` exposes the stock arbitration policy:

| Dvar | Stock | SSD-balanced |
| --- | ---: | ---: |
| `cl_transient_mp_yield_timeout` | 3000 ms | 1500 ms |
| `cl_transient_mp_yield_priority_timeout` | 200 ms | 100 ms |
| `cl_preload_sp_yield_timeout` | 3000 ms | 1500 ms |
| `cl_preload_sp_stream_minimum_time` | 6000 ms | 2000 ms |
| `cl_preload_sp_yield_minimum_time` | 1000 ms | 250 ms |

The same block registers yield-enable booleans and priority thresholds. Those values are not changed: they protect foreground streaming and frame pacing. Only conservative wait hysteresis is shortened, and only when Windows reports that the game volume has no seek penalty. HDDs and unknown devices retain stock defaults.

The database block decoder at `0x1409E6FC0` consumes an ordered output stream and selects one of three leaf wrappers at `0x1409E6E30`: zlib for block types 1/2 (`0x1409E6DA0`), LZ4 for types 3/4 (`0x1409E6D60`), and a direct copy for type 5 (`0x1409E6D80`). Calls use `(source, destination, compressedBytes, outputBytes)`. A compressed block plus its alignment is capped at `0x12800` bytes. The zlib wrapper initializes and ends an inflate stream for each block; whether that setup cost is material will be established by the new per-zone timing rather than assumed. Parallel block decoding is not currently safe because the caller advances a single destination/read state immediately after each successful decode.

The stock `db_loadSleepTime` dvar is already registered with a default of zero at `0x140A79F10`, so there is no database-thread sleep to remove.

### Generated asset preparation is centrally dispatchable

The generated `Load_XAsset` dispatcher is at `0x140A15A40`; its `Postload_XAsset` counterpart is at
`0x140A72090`. Both read the current 16-byte `XAsset` through `varXAsset` at `0x1453E1298`, switch on its type,
temporarily bind the corresponding generated type pointer, and call the type-specific deserializer. For example,
normal type `0x39` dispatches to `0x1409E9E20`, whose publication wrapper at `0x1403B7FB0` passes the same type to
`DB_AddXAsset`. This gives iwz-mod one stable instrumentation point per preparation family instead of requiring
detours across roughly eighty generated loaders.

The postload identification is structural rather than a name guess: its type-specific functions add the
patch-memory push/pop calls around the same stream-position work performed by the load-family functions. Both
families can publish assets, and the engine selects between them per zone.

The generated publication wrappers call `0x140A78EF0` after `DB_AddXAsset`; several types perform additional
type-specific work as well. Consequently, native `DB_AddXAsset` timing alone cannot represent the complete asset
preparation cost. The dispatcher probes measure the inclusive generated work by type, while the existing
publication and decoder probes provide nested sub-costs.

### CPU topology is only partly modern-hardware-aware

The topology routine at `0x140BB7710` enumerates process-affinity bits, caps its internal logical-processor view at 16, creates a fixed set of eight worker contexts, and pins important engine/worker threads with single-bit `SetThreadAffinityMask` calls around `0x140BB7830`. On SMT systems, ascending logical IDs can assign early high-value threads to sibling logical processors before unused physical cores, depending on Windows' numbering.

iwz-mod now preserves every engine-requested affinity index but translates single-bit requests through a physical-core-first ordering obtained from `GetLogicalProcessorInformationEx`. On heterogeneous CPUs, Windows' efficiency class places performance cores first. Multi-bit, unknown, restricted, or incomplete-topology requests pass through unchanged. Increasing the worker count is not safe: the engine has fixed worker contexts and associated arrays for workers 0-7, so a wider patch requires a separate audit of every consumer.

### Modern VRAM is not artificially capped

Renderer initialization registers `r_videoMemoryScale` at `0x140DF8A58` with default `1.0`, minimum `0.0`, and maximum `2.0`. The consumers at `0x140E04E7C` and `0x140E04F5B` multiply 64-bit adapter-memory values by that scale before converting the result. IW therefore uses the adapter's full reported memory by default and does not contain a legacy 4 GiB accounting cap that iwz-mod needs to patch.

### iwz-mod imposed a persistent startup bottleneck

Before this audit, `main.cpp` created an Image File Execution Options value named `MaxLoaderThreads=1` for `iw7-mod.exe` on every launch. That globally forced the Windows loader preparation path for the process to one thread and survived across launches. The crash-workaround comment did not establish a current need for it.

iwz-mod no longer creates that value. It removes the legacy value when permitted, logs the outcome, and otherwise leaves registry state untouched. Users who previously ran iwz-mod elevated may need one elevated launch of the new build to remove the old HKLM value.

## Temporary audit instrumentation (removed)

The investigation used temporary probes around `DB_TryLoadXFileInternal`, database completion, generated asset
dispatch, common stream service, compressed-input refill/advance, post-publication work, and the three decoder
leaves. Per-zone records captured elapsed and active time, asset counts and type attribution, stream bytes and call
counts, refill/advance time, decoded-window hits, codec throughput, and failures.

Bounded disassembly of the only direct caller at `0x140A7B499` and runtime traces establish the result mapping:

| Result | Meaning | Caller behavior |
| ---: | --- | --- |
| `0` | successful processing completion | adds the slot to the loaded bitset |
| `1` | yielded / resumable | retains slot state for another pass |
| `2` | transient-only work interrupted this pass | retains the slot without marking it loaded |
| `3` | slot released | clears all work masks and zeroes the 0x478-byte slot |

All database, generated-dispatch, stream, refill, advance, post-add, and decoder diagnostic hooks were removed
before merge. The production build retains only low-frequency operational logs for storage classification/profile
selection, effective streaming dvar values, CPU topology/remaps, and legacy loader-throttle removal. Their prefixes
are `[IWZ][AssetStreaming]`, `[IWZ][CPU]`, and `[IWZ][Startup]`.

The function's return type matters: `DB_TryLoadXFileInternal` returns a boolean in `AL`, and its caller at `0x140A7B2D3` branches on that value. Instrumentation must capture and return it after logging; treating the hook as `void` is only accidentally safe while the hook remains a compiler-generated tail call.

### Validated Zombies-lobby trace

The corrected completion probe was validated through a clean boot into the Zombies lobby. The trace completed
73 fastfiles, observed 196,776 `DB_AddXAsset` calls, returned the measured active-slot count to zero, and contained
no invalid-slot warning, fatal error, or unhandled exception. Summed per-zone elapsed values are diagnostic rather
than wall-clock startup time because yielded slots can include time spent waiting on other streaming work.

The largest measured stages were:

| Fastfile | Duration | Asset publications | Passes |
| --- | ---: | ---: | ---: |
| `cp_zmb` | 5582.20 ms | 21,910 | 3 |
| `global_core_mp` | 768.96 ms | 26,006 | 1 |
| `techsets_global_core_mp` | 613.02 ms | 21,783 | 1 |
| `techsets_global_cp` | 451.06 ms | 16,180 | 1 |
| `techsets_cp_zmb` | 429.30 ms | 13,878 | 1 |
| `global_cp` | 385.61 ms | 19,933 | 1 |
| `cp_frontend` | 379.54 ms | 2,976 | 1 |
| `ui` | 359.10 ms | 8,005 | 1 |

`cp_zmb` was the only multi-pass completion in this run: two result-`1` yields preceded the successful third pass.
That 5.58-second elapsed interval is therefore primarily an arbitration opportunity, not evidence that the fastfile
parser itself spent 5.58 seconds continuously on CPU. Conversely, `global_core_mp`, its techsets companion, and the
large CP global zones complete in one pass while publishing tens of thousands of assets; these are the strongest
candidates for future preparation-path profiling. `patch_ui` also took 227.52 ms for only 118 asset publications,
showing that publication count alone does not explain backend duration.

A second Zombies-lobby run with the decoder probes completed 68 fastfiles and one transient-only interrupted pass,
returned the active-slot count to zero, and reported no decoder failure. Every observed compressed block used LZ4:
28,580 blocks expanded 813.30 MiB to 1,525.92 MiB in 441.04 ms. No zlib or raw block was observed. Across the
12,680.02 ms sum of per-zone wall intervals, LZ4 accounted for only 3.48%; this sum is not startup wall time because
zones may overlap and yielded slots include scheduler waits.

`cp_zmb` expanded 424.16 MiB to 693.82 MiB in 222.19 ms while its one-pass database interval took 3,571.08 ms.
Even there, decoding was only 6.22% of the measured interval. `global_core_mp` spent 38.06 of 994.24 ms decoding,
and `techsets_global_core_mp` spent 14.22 of 623.37 ms. The clearest non-decoder case was `techsets_ui`: 8,166
asset publications and 428.72 ms elapsed, but only 0.20 ms in LZ4. Conversely, the highest meaningful decoder
share was the small custom `iw7mod_ui_mp` zone at 23.25 of 135.77 ms. These measurements rule out zlib stream reuse
and parallel block decoding as useful startup optimizations for the tested build. Database preparation/publication
and yield arbitration are now the evidence-backed targets.

A third lobby run separated scheduler delay from active database work. Across 65 completed zones and one
transient-only interruption, summed zone intervals were 11,149.95 ms: 8,959.83 ms active and 2,190.12 ms waiting.
The entire wait interval belonged to the two-pass `global_core_mp` load (3,243.35 ms wall, 1,053.23 ms active),
confirming that a yielded zone's wall duration is not CPU work. Native `DB_AddXAsset` consumed 483.95 ms (5.40%
of active time), while LZ4 consumed 430.70 ms (4.81%). The remaining 8,045.18 ms, or 89.79%, is primarily generated
deserialization/preparation and backing-stream service. `cp_zmb` is the dominant case: 3,517.23 ms active, only
40.63 ms in native publication and 223.30 ms in LZ4. This rules out database hash insertion as the main bottleneck
and motivates the generated-dispatcher timing described above.

A fourth lobby run timed both generated dispatch families. They accounted for 6,853.66 of 8,605.95 ms active
database time (79.64%): 3,778.05 ms in `Load_XAsset` and 3,075.61 ms in `Postload_XAsset`. Only 1,752.29 ms fell
outside the dispatchers. The expensive work is content-specific:

- `cp_zmb`: 2,378.49 ms postload, led by `xmodelsurfs` (1,344.82 ms / 4,657 dispatches), its single `gfx_map`
  (448.55 ms), and `xanim` (142.61 ms / 1,212).
- `global_core_mp`: 808.33 ms load, led by `xmodelsurfs` (532.62 ms), two `streaminginfo` dispatches
  (101.45 ms), and images (62.19 ms).
- `techsets_global_core_mp`: 659.79 ms load, led by one `streaminginfo` asset (323.37 ms), materials
  (175.55 ms), and technique sets (160.86 ms).
- `techsets_cp_zmb`: 616.33 ms postload, led by one `streaminginfo` asset (334.69 ms), technique sets
  (238.15 ms), and materials (43.49 ms).
- UI/image-heavy zones are similarly concentrated: images consume 333.06 ms in `ui`, 224.55 ms in `patch_ui`,
  and 131.68 ms in `iw7mod_ui_mp`.

The repeated one-asset `streaminginfo` cost is generated traversal of large per-zone metadata rather than database
hash insertion. Type 64 dispatches to `0x140A0C0C0` in the load family and `0x140A69D60` in the postload family.
Both walk nested arrays and repeatedly call the common stream-service routine at `0x140A7CA90`; postload adds the
patch-memory bookkeeping. The next diagnostic separates time inside that stream-service routine and the generated
post-publication synchronization at `0x140A78EF0` from pointer fixups and traversal. Calls with stream-start zero
return immediately and are excluded from stream timing, keeping probe overhead bounded.

A fifth lobby run performed that separation across 65 completed zones. The database thread was active for
8,530.04 ms and waited for 2,363.36 ms across yielded work. Generated dispatch occupied 6,769.12 ms (79.36% of
active time), and its nested common stream service occupied 3,145.91 ms (36.88% of active time and 46.47% of
dispatch time) while servicing 1,099,953 non-empty requests for 1,485.14 MiB. Native publication took 372.44 ms
and post-publication work took only 111.34 ms. After subtracting those measured nested costs, 3,139.43 ms remained
inside generated traversal/fixup code and 1,760.92 ms remained outside the dispatchers.

`cp_zmb` again dominated: 3,497.92 ms active, 2,438.07 ms in postload, and 1,624.52 ms in the common stream
service for 694.78 MiB across 342,389 requests. Its largest stream consumers were `xmodelsurfs`
(698.43 ms / 344.37 MiB), `gfx_map` (423.92 ms / 160.80 MiB), and `xanim` (146.19 ms / 43.96 MiB).
The generated post-add stage was only 15.21 ms. Across all zones, LZ4 accounted for 432.17 ms of stream-service
time, leaving 2,713.74 ms in input refills, destination copies, and decoder state-machine traversal.

Bounded disassembly now identifies the entire service chain. `0x140A7CA90` returns immediately for a false
stream-start flag, handles mode 6 by zero-filling, and otherwise calls `0x1409E91B0`. That routine binds one global
destination and byte count, drives the stateful block decoder through `0x1409E6860`, and requests more compressed
input through `0x1409E9360`. The refill routine caps each input acquisition at `0x40000` bytes (256 KiB); depending
on reader state it either copies already-buffered data or advances the asynchronous file-reader interface. This
global input/output state and ordered generated pointer fixups make per-asset parallelism unsafe. The high request
count also cannot be eliminated by skipping calls: many calls advance serialized pointers or populate addresses
that later fixups consume, while false stream-start calls already take the stock two-instruction early return.

The bounded refill probe at `0x1409E9360` then completed a sixth lobby run with 66 zones, zero decoder failures,
and no active slot left behind. Across 8,612.35 ms of database-thread activity, the common service processed
1,513.36 MiB in 3,172.70 ms. Its 2,681 compressed-input refills took only 79.46 ms (2.50% of service time), while
LZ4 took 433.16 ms. `cp_zmb` was representative: 1,334 refills consumed only 36.96 ms of its 1,608.73 ms service
time. The backend is therefore not storage/refill-bound on the tested SSD, and increasing the stock 256 KiB refill
cap cannot materially improve these loads.

The decoder also already avoids an obvious double copy. In `0x1409E6FC0`, if the current generated request has
room for the complete decompressed block, the selected codec writes directly to the final asset destination. Only
partial-block requests decode into the embedded 64 KiB output window and then copy through `0x1409E6880`.
The engine's `memcpy` at `0x1412BFE40` checks the platform feature mask and uses Enhanced REP MOVSB for large
non-overlapping copies on supported CPUs, with specialized small-copy and SSE paths otherwise. Replacing it with
an unconditionally AVX implementation would not address the measured bottleneck and could regress small or
overlapping copies.

The remaining service time is consequently dominated by numerous small, serialized generated requests, partial
block copies, and decoder state transitions. The next read-only diagnostic counts positive-size requests already
satisfiable from the 64 KiB decoded-output window; zero-byte requests are now excluded from service metrics because
the stock `0x140A7CA90` path immediately returns for them. This establishes the ceiling for a potential buffer-hit
fast path before any state mutation is considered.

The seventh lobby run measured 1,130,869 positive-size service requests across 70 completed zones. Of these,
1,116,017 (98.69%) were already satisfiable from the decoded-output window. They represented only 546.92 of
1,533.14 MiB (35.67%), confirming that the hit population consists overwhelmingly of small generated reads.
`cp_zmb` recorded 333,532 hits out of 339,074 requests (98.37%) for 232.78 of 694.78 MiB. UI image zones were
different: large image payloads produced lower hit-byte shares despite high call shares. This makes a guarded
buffer-hit fast path plausible, but call count alone does not establish useful time savings. The existing inclusive
service timer now also attributes elapsed time to hits, adding no timer invocations, so the next run measures the
actual optimization ceiling before the decoder state is modified.

The eighth run ruled that fast path out. Decoded-window hits consumed only 113.27 of 3,205.94 ms total service
time (3.53%); `cp_zmb` hits consumed 48.65 of 1,614.66 ms (3.01%). A replacement would still have to perform the
same destination copy and state updates, so its realizable saving would be smaller than those already modest
ceilings. Mutating the global decoder state for this path is therefore unjustified.

The expensive population is the roughly 1.3% of calls that cross decoded-block boundaries. Static tracing shows
that `0x1409E9900`, invoked on this path before `0x1409E9360`, queries the asynchronous reader's completion method,
updates the completed byte count, and rotates between the two 256 KiB input buffers. The refill timer alone does
not include time spent in that completion step. A low-frequency inclusive probe around `0x1409E9900` now separates
hidden asynchronous completion time from CPU-side block decode/copy work.

The ninth and final run measured 1,082,400 positive-size service requests for 1,477.25 MiB in 3,128.50 ms across 65 zones.
There were 2,645 asynchronous advances totaling 90.79 ms (2.90% of service time), but 89.26 ms belonged to one
`iw7mod_ui_mp` outlier. The sustained data-heavy path was effectively hidden: `cp_zmb` spent only 0.69 ms in 1,336
advances while its service path consumed 1,626.33 ms. Its 1,334 refills took 36.37 ms and LZ4 took 220.97 ms.
Storage completion therefore is not the source of the large `cp_zmb` cost. A subsequent block-processor detour was
not retained after it caused a black screen during validation; the investigation ended without shipping that hook.

Use `-stock_asset_streaming` to retain stock streaming dvar defaults for A/B tests. That flag does not change CPU affinity or loader behavior because those are independent of asset-streamer timing.

Use `-stock_cpu_affinity` to retain the engine's original affinity masks when isolating a CPU-topology issue. The obsolete loader-throttle fix remains active.

## Expected effect and remaining work

The implemented changes should reduce avoidable startup serialization, keep worker/database work on distinct physical cores longer on SMT CPUs, and reduce SSD load/preload stalls caused by 2016-era arbitration windows. The exact improvement is content-, cache-, and storage-dependent; the added logging is the source of truth for benchmarking.

Recommended manual validation is three cold-ish launches and three repeat launches per profile, using the same map and route. Compare total time to interactivity and the per-fastfile `durationMs` values. Also watch for texture pop-in or traversal stalls; if either regresses, repeat with `-stock_asset_streaming` to isolate the timing profile.

Parallel fastfile decompression is not an appropriate next step. The observed block path is stateful, database asset
publication is ordered, and measured LZ4 work is only a small fraction of backend time. Adding threads would risk
corrupt assets while placing the theoretical maximum gain well below the remaining preparation and scheduling cost.
