# Output schema

All input timeline tables are optional independently. The corresponding output
categories are omitted when a kernel, Runtime, memcpy, or NVTX table is absent.
When `StringIds.parquet` is absent, kernel and Runtime names use stable numeric
fallbacks. A report containing only Runtime events is exported on an unknown
device track; an entirely eventless export is rejected.

## Event Parquet

`<report>.perfetto.parquet` contains matched CUDA Runtime launch calls, CPU
NVTX, projected NVTX, CUDA kernel, and CUDA memcpy events:

- `report`: report basename.
- `event_type`: `cuda_api`, `cuda_kernel`, `cuda_memcpy_h2d`,
  `cuda_memcpy_d2h`, `cuda_memcpy_d2d`, `nvtx`, or `nvtx_kernel`.
- `cat`, `name`, `ph`: Perfetto trace-event fields.
- `ts_us`, `dur_us`: microseconds relative to the first included event.
- `aligned_ts_us`: microseconds relative to the first
  `CriticalPath/MeasuredBatch/.../batch_0` CPU NVTX range, or relative to the
  first trace event when that optional range is absent.
- `pid`, `tid`: human-readable process/device and stream/NVTX track labels.
- `args_json`: kernel launch metadata and projected `NVTXRegions`.
- `event_id`: stable readable kernel ID.
- `launch_event_id`: on a kernel row, the CPU CUDA Runtime event that launched
  it; join this value to the `event_id` of a `cuda_api` row.
- `stream_id`, `correlation_id`, `stream_sequence`: CUDA linkage fields.
- `depends_on_event_id`, `dependency_type`: reserved and null; consecutive
  kernels on a stream are not linked.

## Dependency Parquet

`<report>.kernel_dependencies.parquet` is an empty, schema-valid compatibility
table. The converter does not infer stream ordering or cross-stream CUDA event
dependencies.

## Perfetto JSON

`<report>.perfetto.json.gz` is one gzip stream containing only a compressed
Chrome Trace Event array. It is not an archive and does not contain either
Parquet output. The JSON contains:

- `cat = cuda` complete kernel events;
- `cat = cuda_kernel_usage` kernel-only projections on the per-device `CUDA
  Core Timeline`; overlapping kernels use adjacent lanes and every kernel is
  projected exactly once;
- `cat = cuda_api` matched CPU CUDA Runtime launch calls;
- `cat = cuda_memcpy` H2D, D2H, and D2D hardware copy intervals with detailed
  byte, memory-kind, device/context, address, and bandwidth arguments on the
  original HW context/stream;
- `cat = cuda_copy_usage` projections on a per-device `PCIe Usage` lane for
  combined H2D/D2H occupancy and on `GPU Copy D2D` for device copies;
- `cat = nvtx` CPU NVTX push/pop ranges emitted as ordered `B`/`E` events;
- `cat = nvtx-kernel` NVTX ranges projected to associated kernels, also emitted
  as ordered `B`/`E` events so Perfetto retains parent-child depth;
- `cat = cuda_launch_dependency` numeric-ID `s`/`f` flows from the CPU launch
  slice to the corresponding GPU kernel;
- `cat = cuda_core_launch_dependency` numeric-ID `s`/`f` flows from the CPU
  launch slice to the corresponding `CUDA Core Timeline` projection;
- `cat = cuda_memcpy_dependency` numeric-ID `s`/`f` flows from the CPU API
  slice to the corresponding original GPU copy interval;
- `cat = pcie_usage_dependency` numeric-ID `s`/`f` flows from the CPU API slice
  to the corresponding H2D/D2H `PCIe Usage` projection. D2D copies do not use
  this category.

Optional fields are omitted when absent. In particular, flow events never emit
`"dur": null`, which Perfetto counts as `json_tokenizer_failure`.

Chrome JSON uses numeric process/thread IDs and metadata events to create:

- `CUDA Device N / Source PID P` process tracks; there is no separate CUDA Host
  Process;
- `CUDA HW Context C / Stream S` child tracks containing the actual CUPTI
  kernel and memcpy execution intervals;
- `CUDA Core Timeline` kernel-only device tracks, ordered above all copy and
  stream tracks;
- `PCIe Usage` and `GPU Copy D2D` device-level occupancy tracks;
- `NVTX Kernel T`, `CUDA API T / Lane L`, and `NVTX Thread T` child tracks under
  the matching device. NVTX nesting is represented on one stack track per
  source thread; extra adjacent lanes are used only for overlapping CUDA APIs.
  Equal thread IDs are adjacent and ordered `NVTX Kernel`, `NVTX Thread`, then
  `CUDA API`.

Selecting either a CUDA API launch slice, its original GPU slice, or its
device-level Core/PCIe projection in Perfetto shows the corresponding launch
arrow. Kernel arguments include `gpuStartNs`, `gpuEndNs`, and `gpuDurationNs`;
launch arguments include `cpuStartNs`, `cpuEndNs`, and `cpuDurationNs`.
