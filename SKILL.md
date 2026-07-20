---
name: nsys-parquet-perfetto-skill
description: Export NVIDIA Nsight Systems `.nsys-rep` or `.qdrep` reports to native Nsight Parquet tables, then use the bundled Rust and Apache DataFusion converter to create Perfetto/Chrome Trace JSON, aligned event Parquet, and CUDA stream dependency Parquet. Use when Codex needs a fast, SQLite-free conversion of Nsight CUDA kernel and NVTX timelines, Perfetto-compatible JSON without tokenizer failures, NVTX-to-kernel projection, or fixed outputs under `/home/ziyang/.nsys-workspace/REPORT_NAME/`.
---

# Nsight Parquet to Perfetto

Use the bundled deterministic workflow. Do not use SQLite or `nsys2json.py` as
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
4. Execute the bundled Rust/DataFusion converter with `cargo run --locked
   --release --manifest-path ...`. Cargo artifacts are cached outside the skill.
5. Read `StringIds`, CUDA kernel, CUDA Runtime, and NVTX Parquet tables through
   DataFusion.
6. Keep NVTX push/pop ranges (`eventType = 59`), map process IDs to devices,
   and project NVTX ranges to kernels through Runtime overlap and
   `correlationId`, matching `nsys2json`.
7. Write Perfetto JSON without nullable optional keys and add valid numeric
   `s`/`f` flow IDs for same-stream kernel dependencies.
8. Write aligned events and dependency edges as Parquet.
9. Validate that the JSON is a non-empty array when `jq` is installed.

## Fixed output layout

For `model.nsys-rep`, always write under:

```text
/home/ziyang/.nsys-workspace/model/
├── parquet/                               # Native Nsight tables
├── model.perfetto.json                    # Load this in Perfetto
├── model.perfetto.parquet                 # NVTX/kernel analysis table
└── model.kernel_dependencies.parquet      # Same-stream dependency edges
```

The report name is the input basename with `.nsys-rep` or `.qdrep` removed.
Do not place final JSON beside the source report.

## Verify results

After conversion, report:

- selected `nsys` version;
- Rust converter summary counts for kernels, CPU NVTX, projected NVTX,
  dependencies, JSON events, and Parquet rows;
- exact JSON and Parquet paths;
- output sizes.

Always end the handoff with the absolute Perfetto JSON path so the user can
open it immediately.

Treat any nonzero command status as a failed conversion. Never publish partial
JSON after an Nsight exporter or DataFusion error. Source reports are read-only.

For output columns and dependency semantics, read
[references/output-schema.md](references/output-schema.md).
