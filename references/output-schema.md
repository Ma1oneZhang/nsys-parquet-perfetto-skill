# Output schema

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

`<report>.perfetto.json` is a Chrome Trace Event array with:

- `cat = cuda` complete kernel events;
- `cat = cuda_api` matched CPU CUDA Runtime launch calls;
- `cat = cuda_memcpy` H2D, D2H, and D2D hardware copy intervals with detailed
  byte, memory-kind, device/context, address, and bandwidth arguments;
- `cat = nvtx` CPU NVTX push/pop ranges emitted as ordered `B`/`E` events;
- `cat = nvtx-kernel` NVTX ranges projected to associated kernels, also emitted
  as ordered `B`/`E` events so Perfetto retains parent-child depth;
- `cat = cuda_launch_dependency` numeric-ID `s`/`f` flows from the CPU launch
  slice to the corresponding GPU kernel;
- `cat = cuda_memcpy_dependency` numeric-ID `s`/`f` flows from the CPU API
  slice to the corresponding GPU copy interval.

Optional fields are omitted when absent. In particular, flow events never emit
`"dur": null`, which Perfetto counts as `json_tokenizer_failure`.

Chrome JSON uses numeric process/thread IDs and metadata events to create:

- `CUDA Device N / Source PID P` process tracks; there is no separate CUDA Host
  Process;
- `CUDA HW Context C / Stream S` child tracks containing the actual CUPTI
  kernel execution interval;
- `NVTX Kernel T`, `CUDA API T / Lane L`, and `NVTX Thread T` child tracks under
  the matching device. NVTX nesting is represented on one stack track per
  source thread; extra adjacent lanes are used only for overlapping CUDA APIs.
  Equal thread IDs are adjacent and ordered `NVTX Kernel`, `NVTX Thread`, then
  `CUDA API`.

Selecting either a CUDA API launch slice or its GPU kernel slice in Perfetto
shows their `cuda_launch_dependency` arrow. The kernel arguments include
`gpuStartNs`, `gpuEndNs`, and `gpuDurationNs`; launch arguments include
`cpuStartNs`, `cpuEndNs`, and `cpuDurationNs`.
