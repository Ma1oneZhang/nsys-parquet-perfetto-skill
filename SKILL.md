---
name: nsys-parquet-perfetto-skill
description: Export NVIDIA Nsight Systems `.nsys-rep` or `.qdrep` reports to native Nsight Parquet tables, then use the published Rust and Apache DataFusion converter to create Perfetto/Chrome Trace JSON and aligned event Parquet. Use when Codex needs a fast, SQLite-free conversion of Nsight CUDA kernel, H2D/D2H/D2D memcpy, CUDA Runtime launch, and NVTX timelines; CPU-API-to-GPU flows; Perfetto-compatible JSON without tokenizer failures; process-aware multi-device tracks; or outputs under `$HOME/.nsys-workspace/REPORT_NAME/`.
---

# Nsight Parquet to Perfetto

Use the deterministic workflow. Do not use SQLite or `nsys2json.py` as
the data path. The Rust implementation reproduces the relevant `nsys2json`
semantics over Nsight's native Parquet export.

## Convert reports

Run:

```bash
bash <skill-dir>/scripts/convert_nsys.sh /absolute/path/report.nsys-rep
```

Treat the report path as the complete user interface. Do not ask the user for
an output directory, Rust project path, Parquet table list, or additional
conversion flags.

Pass multiple reports to process them sequentially:

```bash
bash <skill-dir>/scripts/convert_nsys.sh first.nsys-rep second.nsys-rep
```

The script performs all required steps:

1. Verify that `cargo` is already available in `PATH`; fail immediately without
   downloading or installing it when absent.
2. Select the newest installed versioned `nsys` CLI without changing the
   system-wide alternative.
3. Export every report with `nsys export --type=parquetdir
   --ts-normalize=true`.
4. Query crates.io for the latest stable `nsys2perfetto-datafusion` version,
   fetch it when it is not already in Cargo's registry cache, then execute it
   with `cargo run --locked --release --manifest-path ...`. The converter uses
   a Tokio multi-thread runtime with eight worker threads. The skill contains
   no Rust source code and Cargo artifacts are cached outside the skill. Set
   `NSYS2PERFETTO_VERSION` only when a reproducible historical version is
   needed.
5. Discover `StringIds`, CUDA kernel, CUDA memcpy, CUDA Runtime, and NVTX
   Parquet tables independently, then read the tables that exist through
   DataFusion. Missing timeline categories are skipped; missing `StringIds`
   uses stable numeric fallback names. Fail only when no available table can
   produce any timeline event.
6. Keep NVTX push/pop ranges (`eventType = 59`), map process IDs to devices,
   and project NVTX ranges to kernels through Runtime overlap and
   `correlationId`, matching `nsys2json`.
7. Write matched CUDA Runtime launch slices and connect each CPU launch site to
   its GPU kernel by `(PID, correlationId)` using numeric Perfetto `s`/`f`
   flows. Also retain `cudaDeviceSynchronize` and `cudaStreamSynchronize`
   Runtime slices, including versioned and per-thread-default-stream suffixes;
   these synchronization calls have no fabricated GPU flow. Create explicitly
   named and sorted process-aware CUDA hardware context/stream tracks whose
   slices use CUPTI `start`/`end` intervals. Under
   every device, create a topmost kernel-only `CUDA Core Timeline`, followed by
   combined H2D/D2H `PCIe Usage`, D2D copy, HW Context/Stream, NVTX Kernel,
   CUDA API, and NVTX Thread children. Preserve every kernel on its original HW
   context/stream and project it exactly once to the overlap-safe CUDA Core
   Timeline; never include H2D, D2H, or D2D on that timeline. Give each linked
   kernel both its original API-to-stream flow and an independent API-to-Core
   projection flow so either copy retains its launch chain. Preserve every
   memcpy on its original HW context/stream as well as its device usage
   projection. Give each linked H2D/D2H copy both its original API-to-stream
   flow and an independent API-to-PCIe projection flow; keep D2D outside PCIe
   Usage. Discover any number of devices dynamically; when a PID has no GPU
   activity of its own, project it to all devices observed in the trace instead
   of creating `Device -1`. Emit both NVTX kinds as ordered `B`/`E` stacks so
   Perfetto preserves their push/pop parent-child hierarchy. Use extra lanes
   only for overlapping CUDA API complete events. Within every device, group
   equal source thread IDs and order each group as NVTX Kernel, NVTX Thread,
   then CUDA API. Do not connect consecutive kernels on a stream.
8. Add detailed H2D, D2H, and D2D slices and API-to-copy flows, then write
   aligned events as Parquet. Have the Rust converter stream the Perfetto JSON
   directly through its gzip encoder so no uncompressed JSON is materialized;
   the shell script only validates the completed gzip stream.
9. Validate gzip integrity and, when `jq` is installed, validate that the
   decompressed JSON is a non-empty array.

## Output layout

For `model.nsys-rep`, always write under:

```text
$HOME/.nsys-workspace/model/
├── parquet/                               # Native Nsight tables
├── model.perfetto.json.gz                 # Gzip stream containing only JSON
├── model.perfetto.parquet                 # NVTX/kernel analysis table
└── model.kernel_dependencies.parquet      # Empty compatibility table
```

The report name is the input basename with `.nsys-rep` or `.qdrep` removed.
Do not place final JSON beside the source report. The `.json.gz` is not an
archive and contains no Parquet files; it is one gzip-compressed Chrome Trace
JSON stream that Perfetto opens transparently.

Set `NSYS_WORKSPACE_ROOT` to override `$HOME/.nsys-workspace`. Do not hard-code
a user home directory in the script or instructions.

## Verify results

After conversion, report:

- selected `nsys` version;
- Rust converter summary counts for kernels, linked CUDA API launches, stream
  and Core launch dependencies, captured CUDA synchronization APIs, memcpy
  directions, stream copy links, PCIe projection links, CPU NVTX, projected
  NVTX, JSON events, and Parquet rows;
- exact JSON and Parquet paths;
- output sizes.

For launch-link validation, every linked kernel must contain exactly one parsed
CPU-API-to-original-stream flow and one CPU-API-to-Core-projection flow. Every
linked memcpy keeps its API-to-original-stream flow, and each linked H2D/D2H
copy additionally has exactly one API-to-PCIe-projection flow. Flow endpoints
are placed inside their slices and kept time-monotonic even when GPU execution
starts before the CUDA Runtime API returns.

Always end the handoff with the absolute Perfetto JSON path so the user can
open it immediately.

Treat any nonzero command status as a failed conversion. Never publish partial
JSON after an Nsight exporter or DataFusion error. Source reports are read-only.

For output columns and flow semantics, read
[references/output-schema.md](references/output-schema.md).
