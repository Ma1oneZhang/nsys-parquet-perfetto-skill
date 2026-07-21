# Nsight Parquet 转 Perfetto Skill

[English](README.md)

这是一个 Codex skill，可将 NVIDIA Nsight Systems 的 `.nsys-rep`/`.qdrep`
报告转换为 Perfetto 时间线和可查询的 Parquet，全程不使用 SQLite。

它基于 Nsight 原生 Parquet 导出和 Rust/DataFusion
[`nsys2perfetto-datafusion`](https://crates.io/crates/nsys2perfetto-datafusion)
转换器，支持 CUDA kernel、CUDA API 与同步调用、NVTX、PCIe usage、设备时间线
以及 CPU 到 GPU 的调用箭头。

## 使用方法

```bash
bash scripts/convert_nsys.sh /absolute/path/report.nsys-rep
```

结果位于 `$HOME/.nsys-workspace/<report>/`。生成的 `.perfetto.json.gz` 可直接在
[Perfetto](https://ui.perfetto.dev/) 中打开。

需要 NVIDIA Nsight Systems 和 Rust/Cargo 1.88 或更新版本。完整流程见
[SKILL.md](SKILL.md)。
