# Output schema

## Event Parquet

`<report>.perfetto.parquet` contains matched CUDA Runtime launch calls, CPU
NVTX, projected NVTX, and CUDA kernel events:

- `report`: report basename.
- `event_type`: `cuda_api`, `cuda_kernel`, `nvtx`, or `nvtx_kernel`.
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
- `depends_on_event_id`, `dependency_type`: predecessor link; dependency type
  is `same_stream_order`.

## Dependency Parquet

`<report>.kernel_dependencies.parquet` contains one row per adjacent pair of
kernels on the same `(device, context, stream)`:

- predecessor and successor IDs, names, timestamps, and durations;
- `stream_id` and successor `stream_sequence`;
- nonnegative `gap_us` between predecessor end and successor start;
- `dependency_type = same_stream_order`.

This represents CUDA stream ordering. It does not infer cross-stream CUDA event
or synchronization dependencies.

## Perfetto JSON

`<report>.perfetto.json` is a Chrome Trace Event array with:

- `cat = cuda` complete kernel events;
- `cat = cuda_api` matched CPU CUDA Runtime launch calls;
- `cat = nvtx` CPU NVTX push/pop ranges;
- `cat = nvtx-kernel` NVTX ranges projected to associated kernels, with a
  separate projection track for every matched CUDA device;
- `cat = cuda_launch_dependency` numeric-ID `s`/`f` flows from the CPU launch
  slice to the corresponding GPU kernel;
- `cat = cuda_dependency` numeric-ID `s`/`f` flows between adjacent kernels on
  the same stream.

Optional fields are omitted when absent. In particular, flow events never emit
`"dur": null`, which Perfetto counts as `json_tokenizer_failure`.

Chrome JSON uses numeric process/thread IDs and metadata events to create:

- `CUDA HW Device N` process tracks, sorted before host processes;
- `CUDA HW Context C / Stream S` child tracks containing the actual CUPTI
  kernel execution interval;
- `CUDA Host Process P / CUDA API / NVTX Thread T` tracks containing Runtime
  launch intervals.

Selecting either a CUDA API launch slice or its GPU kernel slice in Perfetto
shows their `cuda_launch_dependency` arrow. The kernel arguments include
`gpuStartNs`, `gpuEndNs`, and `gpuDurationNs`; launch arguments include
`cpuStartNs`, `cpuEndNs`, and `cpuDurationNs`.
