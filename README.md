# Nsight Parquet to Perfetto Skill

[中文说明](README_CN.md)

A Codex skill that converts NVIDIA Nsight Systems `.nsys-rep`/`.qdrep` reports
to Perfetto timelines and queryable Parquet without SQLite.

It uses Nsight's native Parquet export and the Rust/DataFusion
[`nsys2perfetto-datafusion`](https://crates.io/crates/nsys2perfetto-datafusion)
converter. Output includes CUDA kernels, CUDA API and synchronization calls,
NVTX, PCIe usage, device timelines, and CPU-to-GPU flow arrows.

## Usage

```bash
bash scripts/convert_nsys.sh /absolute/path/report.nsys-rep
```

Results are written to `$HOME/.nsys-workspace/<report>/`. Open the generated
`.perfetto.json.gz` directly in [Perfetto](https://ui.perfetto.dev/).

Requires NVIDIA Nsight Systems and Rust/Cargo 1.88 or newer. See
[SKILL.md](SKILL.md) for the complete workflow.
