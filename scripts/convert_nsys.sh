#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 REPORT.nsys-rep [REPORT.qdrep ...]" >&2
  exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir="$script_dir/nsys2perfetto-datafusion"
output_root=/home/ziyang/.nsys-workspace
cache_root=${XDG_CACHE_HOME:-/home/ziyang/.cache}/nsys-parquet-perfetto-skill
export CARGO_TARGET_DIR="$cache_root/target"

mkdir -p "$output_root" "$cache_root"

nsys_candidates=()
while IFS= read -r candidate; do
  nsys_candidates+=("$candidate")
done < <(find /opt/nvidia/nsight-systems -type f -path '*/target-linux-x64/nsys' -perm -u+x 2>/dev/null | sort -V)

if [[ ${#nsys_candidates[@]} -gt 0 ]]; then
  nsys_bin=${nsys_candidates[${#nsys_candidates[@]}-1]}
else
  nsys_bin=$(command -v nsys || true)
fi

if [[ -z "$nsys_bin" ]]; then
  echo "No usable nsys CLI was found." >&2
  exit 1
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo is required to build the Rust/DataFusion converter." >&2
  exit 1
fi

"$nsys_bin" --version

for input in "$@"; do
  if [[ ! -f "$input" ]]; then
    echo "Report does not exist: $input" >&2
    exit 1
  fi

  absolute_input=$(realpath "$input")
  filename=${absolute_input##*/}
  case "$filename" in
    *.nsys-rep) report_name=${filename%.nsys-rep} ;;
    *.qdrep) report_name=${filename%.qdrep} ;;
    *)
      echo "Unsupported report extension: $absolute_input" >&2
      exit 1
      ;;
  esac

  report_dir="$output_root/$report_name"
  parquet_dir="$report_dir/parquet"
  json_path="$report_dir/$report_name.perfetto.json"
  event_parquet="$report_dir/$report_name.perfetto.parquet"
  dependency_parquet="$report_dir/$report_name.kernel_dependencies.parquet"
  mkdir -p "$report_dir"

  echo "Exporting Nsight Parquet: $absolute_input -> $parquet_dir"
  "$nsys_bin" export \
    --type=parquetdir \
    --ts-normalize=true \
    --force-overwrite=true \
    --quiet=true \
    --output="$parquet_dir" \
    "$absolute_input"

  echo "Converting with cargo run + Rust/DataFusion: $report_name"
  cargo run --locked --release --manifest-path "$project_dir/Cargo.toml" -- \
    --parquet-dir "$parquet_dir" \
    --report "$report_name" \
    --output-json "$json_path" \
    --output-parquet "$event_parquet" \
    --output-dependencies "$dependency_parquet"

  if command -v jq >/dev/null 2>&1; then
    jq -e 'type == "array" and length > 0' "$json_path" >/dev/null
  fi

  echo "Perfetto JSON: $json_path"
  echo "Event Parquet: $event_parquet"
  echo "Dependency Parquet: $dependency_parquet"
  du -h "$json_path" "$event_parquet" "$dependency_parquet"
done
