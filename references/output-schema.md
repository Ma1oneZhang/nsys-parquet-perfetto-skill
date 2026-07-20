# Output schema

## Event Parquet

`<report>.perfetto.parquet` contains CPU NVTX, projected NVTX, and CUDA kernel
events:

- `report`: report basename.
- `event_type`: `cuda_kernel`, `nvtx`, or `nvtx_kernel`.
- `cat`, `name`, `ph`: Perfetto trace-event fields.
- `ts_us`, `dur_us`: microseconds relative to the first included event.
- `aligned_ts_us`: microseconds relative to the first
  `CriticalPath/MeasuredBatch/.../batch_0` CPU NVTX range.
- `pid`, `tid`: human-readable device and stream/NVTX track labels.
- `args_json`: kernel launch metadata and projected `NVTXRegions`.
- `event_id`: stable readable kernel ID.
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
- `cat = nvtx` CPU NVTX push/pop ranges;
- `cat = nvtx-kernel` NVTX ranges projected to associated kernels;
- `cat = cuda_dependency` numeric-ID `s`/`f` flows.

Optional fields are omitted when absent. In particular, flow events never emit
`"dur": null`, which Perfetto counts as `json_tokenizer_failure`.
