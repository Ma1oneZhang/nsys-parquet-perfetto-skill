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
   fetch it when it is not already in Cargo's registry cache, then execute it with
   `cargo run --locked --release --manifest-path ...`. The skill contains no
   Rust source code and Cargo artifacts are cached outside the skill. Set
   `NSYS2PERFETTO_VERSION` only when a reproducible historical version is needed.
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
   flows. Create explicitly named and sorted process-aware CUDA hardware
   context/stream tracks whose slices use CUPTI `start`/`end` intervals. Under
   every device, create separate HW Context/Stream, NVTX Kernel, CUDA API, and
   NVTX Thread children. Emit both NVTX kinds as ordered `B`/`E` stacks so
   Perfetto preserves their push/pop parent-child hierarchy. Use extra lanes
   only for overlapping CUDA API complete events. Within every device, group
   equal source thread IDs and order each group as NVTX Kernel, NVTX Thread,
   then CUDA API. Do not connect consecutive kernels on a stream.
8. Add detailed H2D, D2H, and D2D slices and API-to-copy flows, then write
   aligned events as Parquet.
9. Validate that the JSON is a non-empty array when `jq` is installed.

## Output layout

For `model.nsys-rep`, always write under:

```text
$HOME/.nsys-workspace/model/
├── parquet/                               # Native Nsight tables
├── model.perfetto.json                    # Load this in Perfetto
├── model.perfetto.parquet                 # NVTX/kernel analysis table
└── model.kernel_dependencies.parquet      # Empty compatibility table
```

The report name is the input basename with `.nsys-rep` or `.qdrep` removed.
Do not place final JSON beside the source report.

Set `NSYS_WORKSPACE_ROOT` to override `$HOME/.nsys-workspace`. Do not hard-code
a user home directory in the script or instructions.

## Verify results

After conversion, report:

- selected `nsys` version;
- Rust converter summary counts for kernels, linked CUDA API launches,
  launch dependencies, memcpy directions and links, CPU NVTX, projected NVTX,
  JSON events, and Parquet rows;
- exact JSON and Parquet paths;
- output sizes.

For launch-link validation, Perfetto must contain exactly one parsed
CPU-API-to-GPU-kernel flow per linked kernel. Flow endpoints are placed inside
their slices and kept time-monotonic even when GPU execution starts before the
CUDA Runtime API returns.

Always end the handoff with the absolute Perfetto JSON path so the user can
open it immediately.

Treat any nonzero command status as a failed conversion. Never publish partial
JSON after an Nsight exporter or DataFusion error. Source reports are read-only.

For output columns and flow semantics, read
[references/output-schema.md](references/output-schema.md).
