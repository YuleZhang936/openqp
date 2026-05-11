#!/bin/bash
#SBATCH -J quest1_mrsf
#SBATCH -p amd_512
#SBATCH -N 1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=30
#SBATCH --array=0-17
#SBATCH -o slurm-%x-%A_%a.out
#SBATCH -e slurm-%x-%A_%a.err

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${QUEST_MRSF_WORK_DIR:-${SLURM_SUBMIT_DIR:-$SCRIPT_DIR}}"

if [[ ! -d "$WORK_DIR/inputs" && -d "$WORK_DIR/quest_mrsf/inputs" ]]; then
  WORK_DIR="$WORK_DIR/quest_mrsf"
fi

if [[ ! -d "$WORK_DIR/inputs" && -d "$WORK_DIR/work/quest_mrsf/inputs" ]]; then
  WORK_DIR="$WORK_DIR/work/quest_mrsf"
fi

if [[ ! -d "$WORK_DIR/inputs" ]]; then
  echo "Cannot find inputs directory."
  echo "SLURM_SUBMIT_DIR=${SLURM_SUBMIT_DIR:-unset}"
  echo "SCRIPT_DIR=$SCRIPT_DIR"
  echo "WORK_DIR=$WORK_DIR"
  echo "Please submit from the quest_mrsf directory:"
  echo "  cd /path/to/work/quest_mrsf"
  echo "  sbatch sub.sh"
  echo "Or set QUEST_MRSF_WORK_DIR=/path/to/work/quest_mrsf before sbatch."
  exit 1
fi

cd "$WORK_DIR"

export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-30}"
INPUT_FILES=()
while IFS= read -r input_file; do
  INPUT_FILES+=("$input_file")
done < <(find "$WORK_DIR/inputs" -maxdepth 1 -type f -name 'quest1_*.inp' | sort)

if [[ "${#INPUT_FILES[@]}" -eq 0 ]]; then
  echo "No inputs/quest1_*.inp files found. Run: python3 quest1.py"
  exit 1
fi

TASK_ID="${SLURM_ARRAY_TASK_ID:-}"
if [[ -z "$TASK_ID" ]]; then
  echo "Submit this script with sbatch so SLURM_ARRAY_TASK_ID is set."
  echo "Example: sbatch sub.sh"
  exit 1
fi

if (( TASK_ID < 0 || TASK_ID >= ${#INPUT_FILES[@]} )); then
  echo "SLURM_ARRAY_TASK_ID=$TASK_ID is out of range for ${#INPUT_FILES[@]} input files."
  exit 1
fi

source /public1/soft/modules/module.sh 
module load miniforge/24.11 oneAPI/2022.1 mpi/oneAPI/2022.1 gcc/9.3.0
source activate openqp
export PYTHONUNBUFFERED=1
export OPENQP_ROOT=/public1/home/scg0213/software-scg0213/openqp/openqp-main
export LD_LIBRARY_PATH=$OPENQP_ROOT/lib:$LD_LIBRARY_PATH

export MKL_INTERFACE_LAYER="@_MKL_INTERFACE_LAYER@"
export MKL_THREADING_LAYER=SEQUENTIAL

INPUT_FILE="${INPUT_FILES[$TASK_ID]}"
INPUT_BASENAME="$(basename "$INPUT_FILE")"
CASE_NAME="${INPUT_BASENAME%.inp}"
CASE_NAME="${CASE_NAME#quest1_}"
RUN_DIR="$WORK_DIR/runs/$CASE_NAME"
SYSTEM_VALUE="$(awk -F= '/^system=/ {print $2; exit}' "$INPUT_FILE")"
XYZ_BASENAME="$(basename "$SYSTEM_VALUE")"
XYZ_SOURCE="$WORK_DIR/geometries/$XYZ_BASENAME"

if [[ ! -f "$XYZ_SOURCE" ]]; then
  echo "Geometry file not found for $CASE_NAME: $XYZ_SOURCE"
  exit 1
fi

mkdir -p "$RUN_DIR"
awk -v system_path="$XYZ_SOURCE" '
  /^system=/ && !done {
    print "system=" system_path
    done = 1
    next
  }
  { print }
' "$INPUT_FILE" > "$RUN_DIR/$INPUT_BASENAME"
cd "$RUN_DIR"

echo "[$(date)] Starting $CASE_NAME"
echo "Input: $INPUT_FILE"
echo "Geometry: $XYZ_SOURCE"
echo "Run directory: $RUN_DIR"
echo "OMP_NUM_THREADS=$OMP_NUM_THREADS"

openqp "$INPUT_BASENAME"

echo "[$(date)] Finished $CASE_NAME"
