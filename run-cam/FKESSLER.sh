#!/usr/bin/env bash
# FKESSLER — create & configure a CESM/CAM case (clean Bash version)
# Usage:
#   ./FKESSLER.sh <RES> [--machine derecho|izumi] [--src <path_to_src>] [--proj <project>] [--account <pbs_account>]
#
# Behavior for --src:
#   - If --src is OMITTED: use $HOME/src/$SRC_BRANCH/cime/scripts/create_newcase
#       where SRC_BRANCH defaults to 'cam-opt-new' (override via env SRC_BRANCH).
#   - If --src is PROVIDED: treat it as a *path* to the CESM/CAM source root and use
#       <src>/cime/scripts/create_newcase
#
# Common knobs (can be env vars or flags):
#   MACHINE=derecho|izumi, PROJECT, PBS_ACCOUNT, QUEUE, STOP_OPTION, STOP_N, NTHRDS
#
set -euo pipefail

# ---------- Defaults ----------
MACHINE="${MACHINE:-derecho}"           # derecho | izumi
SRC_BRANCH="${SRC_BRANCH:-cam_development}" # only used when --src omitted
COMPSET="${COMPSET:-FKESSLER}"
STOP_OPTION="${STOP_OPTION:-ndays}"
STOP_N="${STOP_N:-10}"
NTHRDS="${NTHRDS:-1}"
QUEUE="${QUEUE:-main}"
COMPILER_DERECHO="${COMPILER_DERECHO:-intel}"
COMPILER_IZUMI="${COMPILER_IZUMI:-nag}"
PBS_ACCOUNT="${PBS_ACCOUNT:-P03010039}"
PROJECT="${PROJECT:-P03010039}"

usage() {
  sed -n '1,120p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

die() {
  echo "Error: $*" >&2
  exit 1
}

# ---------- Parse args ----------
[[ $# -ge 1 ]] || usage
RES="$1"; shift || true

SRC_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --machine) MACHINE="$2"; shift 2;;
    --src) SRC_PATH="$2"; shift 2;;
    --proj|--project) PROJECT="$2"; shift 2;;
    --account|--pbs-account) PBS_ACCOUNT="$2"; shift 2;;
    --queue) QUEUE="$2"; shift 2;;
    --stop-n) STOP_N="$2"; shift 2;;
    --stop-option) STOP_OPTION="$2"; shift 2;;
    --nthrds) NTHRDS="$2"; shift 2;;
    -h|--help) usage;;
    *) die "Unknown option: $1";;
  esac
done

# ---------- Machine-specific paths ----------
if [[ "${MACHINE}" == "derecho" ]]; then
  SCR_ROOT="/glade/derecho/scratch"   # local var, NOT exported as SCRATCH
  COMPILER="${COMPILER_DERECHO}"
elif [[ "${MACHINE}" == "izumi" ]]; then
  SCR_ROOT="/scratch/cluster"
  COMPILER="${COMPILER_IZUMI}"
else
  die "Unsupported machine: ${MACHINE} (use 'derecho' or 'izumi')"
fi

# ---------- Choose CIME_OUTPUT_ROOT safely ----------
# Respect an existing CIME_OUTPUT_ROOT if user already set it.
if [[ -n "${CIME_OUTPUT_ROOT:-}" ]]; then
  : # keep as-is
else
  # Prefer $SCRATCH if it exists and is writable;
  # many sites set SCRATCH to .../scratch/$USER already.
  if [[ -n "${SCRATCH:-}" && -d "${SCRATCH}" && -w "${SCRATCH}" ]]; then
    export CIME_OUTPUT_ROOT="${SCRATCH}"
  else
    # Build from SCR_ROOT; avoid duplicating $USER
    if [[ "${SCR_ROOT}" == *"/${USER}" || "${SCR_ROOT}" == *"/${USER}/"* ]]; then
      export CIME_OUTPUT_ROOT="${SCR_ROOT}"
    else
      export CIME_OUTPUT_ROOT="${SCR_ROOT}/${USER}"
    fi
  fi
fi
export PBS_ACCOUNT

# ---------- PE layout / resolution support ----------
PECOUNT="256"
case "${RES}" in
  C96_C96_mg17) PECOUNT="384" ;;
  mpasa120_mpasa120) PECOUNT="256x1" ;;
  ne30pg3_ne30pg3_mg17|ne30_ne30_mg17|f09_f09_mg17) PECOUNT="256" ;;
  *)
    echo "Supported resolutions:"
    echo "  ne30pg3_ne30pg3_mg17  (se-cslam)"
    echo "  ne30_ne30_mg17        (se)"
    echo "  C96_C96_mg17          (fv3)"
    echo "  f09_f09_mg17          (fv)"
    echo "  mpasa120_mpasa120     (mpas)"
    die "Unsupported RES='${RES}'"
    ;;
esac

# ---------- Path to create_newcase ----------
SRC_ROOT=""
if [[ -z "${SRC_PATH}" ]]; then
  # --src omitted: use $HOME/src/$SRC_BRANCH/...
  SRC_ROOT="$HOME/src/${SRC_BRANCH}"
else
  # --src provided: treat as a path (absolute or relative); normalize
  if [[ "${SRC_PATH}" == /* ]]; then
    SRC_ROOT="${SRC_PATH}"
  else
    SRC_ROOT="$(cd "${SRC_PATH}" 2>/dev/null && pwd)" || die "Invalid --src path: ${SRC_PATH}"
  fi
fi

CIME_CREATE="${SRC_ROOT}/cime/scripts/create_newcase"
[[ -x "${CIME_CREATE}" ]] || die "create_newcase not found or not executable at: ${CIME_CREATE}
Hint 1: If you omitted --src, ensure $HOME/src/${SRC_BRANCH} contains a CESM/CAM tree with cime/scripts.
Hint 2: If you provided --src, point it to the *source root* that contains cime/ (e.g., /glade/work/<user>/cesm2)."

# ---------- Case naming (no username duplication) ----------
CASE_NAME="${COMPSET}_${RES}_perf-cslam"

# Prefer CIME_OUTPUT_ROOT; otherwise fall back carefully using SCRATCH/SCR_ROOT
if [[ -n "${CIME_OUTPUT_ROOT:-}" ]]; then
  CASE_PATH="${CIME_OUTPUT_ROOT}/${CASE_NAME}"
elif [[ -n "${SCRATCH:-}" ]]; then
  if [[ "${SCRATCH}" == *"/${USER}" || "${SCRATCH}" == *"/${USER}/"* ]]; then
    CASE_PATH="${SCRATCH}/${CASE_NAME}"
  else
    CASE_PATH="${SCRATCH}/${USER}/${CASE_NAME}"
  fi
else
  if [[ "${SCR_ROOT}" == *"/${USER}" || "${SCR_ROOT}" == *"/${USER}/"* ]]; then
    CASE_PATH="${SCR_ROOT}/${CASE_NAME}"
  else
    CASE_PATH="${SCR_ROOT}/${USER}/${CASE_NAME}"
  fi
fi

# ---------- Create new case ----------
echo "Creating case: ${CASE_NAME}"
echo "  Machine           : ${MACHINE}"
echo "  Queue             : ${QUEUE}"
echo "  Compiler          : ${COMPILER}"
echo "  Project           : ${PROJECT} (PBS_ACCOUNT=${PBS_ACCOUNT})"
echo "  PE count          : ${PECOUNT}"
echo "  Source root       : ${SRC_ROOT}"
echo "  create_newcase    : ${CIME_CREATE}"
echo "  CIME_OUTPUT_ROOT  : ${CIME_OUTPUT_ROOT}"
echo "  CASE_PATH         : ${CASE_PATH}"

"${CIME_CREATE}" \
  --case "${CASE_PATH}" \
  --compset "${COMPSET}" \
  --res "${RES}" \
  --q "${QUEUE}" \
  --walltime "00:15:00" \
  --pecount "${PECOUNT}" \
  --project "${PROJECT}" \
  --compiler "${COMPILER}" \
  --run-unsupported

cd "${CASE_PATH}"

# ---------- XML changes ----------
./xmlchange "STOP_OPTION=${STOP_OPTION},STOP_N=${STOP_N}"
./xmlchange DOUT_S=FALSE
./xmlchange DEBUG=FALSE
./xmlchange "NTHRDS=${NTHRDS}"
./xmlchange TIMER_LEVEL=10

# Optional CAM config (uncomment and edit as needed)
# ./xmlchange --append "CAM_CONFIG_OPTS=-phys kessler -chem terminator -analytic_ic -nlev 32"

# ---------- user_nl_cam tweaks for SE grids ----------
if [[ "${RES}" == "ne30pg3_ne30pg3_mg17" || "${RES}" == "ne30_ne30_mg17" ]]; then
  {
    echo "se_statefreq         = 144"
    echo "se_statediag_numtrac = 200"
    echo "interpolate_output   = .true.,.true.,.true."
    echo "interpolate_nlat     = 192,192,192"
    echo "interpolate_nlon     = 288,288,288"
  } >> user_nl_cam
fi

{
  echo "avgflag_pertape(1) = 'I'"
  echo "avgflag_pertape(2) = 'I'"
  echo "avgflag_pertape(3) = 'I'"
  echo "nhtfrq=-24,-24,-24"
} >> user_nl_cam

# ---------- Setup complete ----------
./case.setup

echo
echo "Case created at: ${CASE_PATH}"
echo "Next steps:"
echo "  cd ${CASE_PATH}"
echo "  # Optional build & submit:"
echo "  # ./case.build"
echo "  # ./case.submit"
