#!/usr/bin/env bash

set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFR_JAR="${BASE_DIR}/cfr-0.152.jar"
OUT_ROOT="${BASE_DIR}/sources"
LOG_DIR="${OUT_ROOT}/_logs"
FAILED_LIST="${LOG_DIR}/failed.txt"
MAPPER_ROOT="${OUT_ROOT}/mapper"

DO_DECOMPILE=1
DO_MAPPER=1

for arg in "$@"; do
  case "${arg}" in
    --decompile-only)
      DO_MAPPER=0
      ;;
    --mapper-only)
      DO_DECOMPILE=0
      ;;
    --all)
      DO_DECOMPILE=1
      DO_MAPPER=1
      ;;
    *)
      ;;
  esac
done

if [[ ! -f "${CFR_JAR}" ]]; then
  echo "cfr not found: ${CFR_JAR}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"
if [[ "${DO_DECOMPILE}" -eq 1 ]]; then
  : > "${FAILED_LIST}"
fi

shopt -s nullglob
JARS=("${BASE_DIR}"/*.jar)
shopt -u nullglob

if [[ ${#JARS[@]} -eq 0 ]]; then
  echo "No .jar files found in ${BASE_DIR}" >&2
  exit 1
fi

size_of() {
  stat -f%z "$1"
}

decompile_jars() {
  for jar in "${JARS[@]}"; do
    if [[ "${jar}" == "${CFR_JAR}" ]]; then
      continue
    fi

    jar_name="$(basename "${jar}" .jar)"
    out_dir="${OUT_ROOT}"
    log_file="${LOG_DIR}/${jar_name}.log"

    mkdir -p "${out_dir}"

    echo "Decompiling ${jar_name}..."
    if java -jar "${CFR_JAR}" "${jar}" --outputdir "${out_dir}" >"${log_file}" 2>&1; then
      echo "OK: ${jar_name}"
    else
      echo "FAIL: ${jar_name}" >&2
      echo "${jar}" >> "${FAILED_LIST}"
    fi

  done

  if [[ -s "${FAILED_LIST}" ]]; then
    echo "Some jars failed. See ${FAILED_LIST} for details." >&2
  else
    echo "All jars decompiled successfully."
  fi
}

extract_mapper_xmls() {
  mkdir -p "${MAPPER_ROOT}"

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT

  for jar in "${JARS[@]}"; do
    if [[ "${jar}" == "${CFR_JAR}" ]]; then
      continue
    fi

    while IFS= read -r entry; do
      [[ -z "${entry}" ]] && continue

      entry_path="${entry}"
      [[ "${entry_path}" != *.xml ]] && continue

      work_dir="${TMP_DIR}/work"
      rm -rf "${work_dir}"
      mkdir -p "${work_dir}"

      if ! (cd "${work_dir}" && jar xf "${jar}" "${entry_path}" >/dev/null 2>&1); then
        continue
      fi

      src_file="${work_dir}/${entry_path}"
      [[ -f "${src_file}" ]] || continue

      if ! grep -qi '<mapper[[:space:]][^>]*namespace=' "${src_file}"; then
        continue
      fi

      if [[ "${entry_path}" == mapper/* ]]; then
        rel_path="${entry_path#mapper/}"
      else
        rel_path="${entry_path}"
      fi

      dest_file="${MAPPER_ROOT}/${rel_path}"
      dest_dir="$(dirname "${dest_file}")"
      mkdir -p "${dest_dir}"

      if [[ -f "${dest_file}" ]]; then
        src_size="$(size_of "${src_file}")"
        dest_size="$(size_of "${dest_file}")"
        if [[ "${src_size}" -gt "${dest_size}" ]]; then
          cp -f "${src_file}" "${dest_file}"
        fi
      else
        cp -f "${src_file}" "${dest_file}"
      fi
    done < <(jar tf "${jar}")

  done

  echo "Mapper XML files extracted to ${MAPPER_ROOT}"
}

if [[ "${DO_DECOMPILE}" -eq 1 ]]; then
  decompile_jars
fi

if [[ "${DO_MAPPER}" -eq 1 ]]; then
  extract_mapper_xmls
fi
