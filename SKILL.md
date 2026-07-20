---
name: nsys-parquet-perfetto-skill
description: Export NVIDIA Nsight Systems `.nsys-rep` or `.qdrep` reports to native Nsight Parquet tables, then use the published Rust and Apache DataFusion converter to create Perfetto/Chrome Trace JSON, aligned event Parquet, and CUDA stream dependency Parquet. Use when Codex needs a fast, SQLite-free conversion of Nsight CUDA kernel, CUDA Runtime launch, and NVTX timelines; CPU-launch-to-GPU-kernel flows; Perfetto-compatible JSON without tokenizer failures; multi-device NVTX-to-kernel projection; or outputs under `$HOME/.nsys-workspace/REPORT_NAME/`.
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
4. Fetch the fixed `nsys2perfetto-datafusion` crate version from crates.io when
   it is not already in Cargo's registry cache, then execute it directly with
   `cargo run --locked --release --manifest-path ...`. The skill contains no
   Rust source code and Cargo artifacts are cached outside the skill.
5. Read `StringIds`, CUDA kernel, CUDA Runtime, and NVTX Parquet tables through
   DataFusion.
6. Keep NVTX push/pop ranges (`eventType = 59`), map process IDs to devices,
   and project NVTX ranges to kernels through Runtime overlap and
   `correlationId`, matching `nsys2json`.
7. Write matched CUDA Runtime launch slices and connect each CPU launch site to
   its GPU kernel by `(PID, correlationId)` using numeric Perfetto `s`/`f`
   flows. Also add separate numeric flows for same-stream kernel dependencies.
8. Write aligned events and dependency edges as Parquet.
9. Validate that the JSON is a non-empty array when `jq` is installed.

## Output layout

For `model.nsys-rep`, always write under:

```text
$HOME/.nsys-workspace/model/
├── parquet/                               # Native Nsight tables
├── model.perfetto.json                    # Load this in Perfetto
├── model.perfetto.parquet                 # NVTX/kernel analysis table
└── model.kernel_dependencies.parquet      # Same-stream dependency edges
```

The report name is the input basename with `.nsys-rep` or `.qdrep` removed.
Do not place final JSON beside the source report.

Set `NSYS_WORKSPACE_ROOT` to override `$HOME/.nsys-workspace`. Do not hard-code
a user home directory in the script or instructions.

## Verify results

After conversion, report:

- selected `nsys` version;
- Rust converter summary counts for kernels, linked CUDA API launches,
  launch dependencies, CPU NVTX, projected NVTX, stream dependencies, JSON
  events, and Parquet rows;
- exact JSON and Parquet paths;
- output sizes.

Always end the handoff with the absolute Perfetto JSON path so the user can
open it immediately.

Treat any nonzero command status as a failed conversion. Never publish partial
JSON after an Nsight exporter or DataFusion error. Source reports are read-only.

For output columns and dependency semantics, read
[references/output-schema.md](references/output-schema.md).
