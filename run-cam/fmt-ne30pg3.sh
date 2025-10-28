#!/usr/bin/env bash
# fmt-ne30pg3.sh — create/run an NE30pg3 CAM case with sane arg parsing
# Usage:
#   ./fmt-ne30pg3.sh [--use-fork PATH] [--short|--long] [--skip-build] CASE_NAME
#
# Frequently used:
#
#  ./fmt-ne30pg3.sh --use-fork /glade/u/home/pel/src/cam_development --short --skip-build test001
#    
# Chemistry compset:
#./fmt-ne30pg3.sh --chemistry --short mychem_case
#
#Performance analysis, no diag I/O:
#./fmt-ne30pg3.sh --performance_analysis --long myperf_case
#
#Performance analysis with chemistry (Cecile pecount): 2160:
#./fmt-ne30pg3.sh --use-fork ~/src/cam_development --short --chemistry --performance_analysis test001

set -euo pipefail

# ---- Defaults ----
RUN_PROFILE="long"
STOP_OPTION_DEFAULT="ndays"
STOP_N_SHORT_DEFAULT=1
STOP_N_LONG_DEFAULT=5

CAM_FORK_PATH=""
CASE_NAME=""
SKIP_BUILD="false"

CHEMISTRY="false"
PERF_ANALYSIS="false"

STOP_N_OVERRIDE=""
STOP_OPTION_OVERRIDE=""

# Derecho/NCAR environment defaults
PROJECT="P03010039"                     # default project code
CESM_ROOT="/glade/work/$USER/cesm"      # fallback CESM root
MACHINE="derecho"
QUEUE="main"
WALLTIME="00:15:00"

#COMPSET="FHISTC_MTso"
COMPSET="FHISTC_MTt4s"
RES="ne30pg3_ne30pg3_mg17"
PECOUNT="1920"
CHEMISTRY="${CHEMISTRY:-false}"
STOP_N_OVERRIDE=""; STOP_OPTION_OVERRIDE=""

#RES="f09_f09_mg17"
# ---- Helpers ----
usage() {
  cat <<EOF
Usage: $(basename "$0") [--use-fork PATH] [--short|--long] [--skip-build] [--chemistry] [--performance_analysis] [--stop-n N] [--stop-option OPTION] CASE_NAME

Options:
  --use-fork PATH   Path to your CESM/CAM fork (uses its cime/scripts if present).
  --short           One-day smoke test (STOP_N=${STOP_N_SHORT_DEFAULT}).
  --long            Longer run (STOP_N=${STOP_N_LONG_DEFAULT}).
  --skip-build      Create and setup the case, but DO NOT build or submit.
  --chemistry       Switch COMPSET to FHISTC_MTt4s.
  --performance_analysis  Remove all lines starting with "fincl" from user_nl_cam to avoid I/O.
  --stop-n N        Override STOP_N (integer).
  --stop-option OPT Override STOP_OPTION (e.g., ndays, nmonths, nyears).
  --stop-n N        Override STOP_N (default depends on run profile).
  --stop-option OPT Override STOP_OPTION (default depends on run profile).
  -h, --help        Show this help.

Defaults:
  PROJECT=${PROJECT}
  CESM_ROOT=${CESM_ROOT}
  MACHINE=${MACHINE}, QUEUE=${QUEUE}, WALLTIME=${WALLTIME}
  COMPSET=${COMPSET}, RES=${RES}
  PECOUNT=${PECOUNT}
Example:
  $(basename "$0") --use-fork /glade/u/home/\$USER/src/cam_development --short --skip-build test001
EOF
}

die() { echo "[fmt-ne30pg3:ERROR] $*" >&2; exit 2; }

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --use-fork)
      [[ $# -ge 2 ]] || die "--use-fork requires a PATH"
      CAM_FORK_PATH="$2"; shift 2;;
    --short) RUN_PROFILE="short"; shift;;
    --long)  RUN_PROFILE="long";  shift;;
    --skip-build) SKIP_BUILD="true"; shift;;
    --chemistry) CHEMISTRY="true"; shift;;
    --performance_analysis) PERF_ANALYSIS="true"; shift;;
    --stop-n)
      [[ $# -ge 2 ]] || die "--stop-n requires an integer value"
      STOP_N_OVERRIDE="$2"; shift 2;;
    --stop-option)
      [[ $# -ge 2 ]] || die "--stop-option requires a value (ndays, nmonths, nyears, etc.)"
      STOP_OPTION_OVERRIDE="$2"; shift 2;;
    --stop-n)
      [[ $# -ge 2 ]] || die "--stop-n requires a value"
      STOP_N_OVERRIDE="$2"; shift 2;;
    --stop-option)
      [[ $# -ge 2 ]] || die "--stop-option requires a value"
      STOP_OPTION_OVERRIDE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    -*) die "Unknown option: $1";;
    *)
      if [[ -z "${CASE_NAME}" ]]; then
        CASE_NAME="$1"
      else
        die "Multiple CASE_NAMEs provided: $CASE_NAME and $1"
      fi
      shift;;
  esac
done

[[ -n "${CASE_NAME}" ]] || die "Missing CASE_NAME. See --help."
if [[ "${CASE_NAME}" == -* ]]; then
  die "CASE_NAME ('${CASE_NAME}') looks like an option. Put options BEFORE the case name."
fi

if [[ -n "${CAM_FORK_PATH}" ]]; then
  [[ -d "${CAM_FORK_PATH}" ]] || die "CAM fork path not found: ${CAM_FORK_PATH}"
fi

# ---- STOP settings ----
# Defaults depend on RUN_PROFILE unless overridden by CLI flags.
if [[ "${RUN_PROFILE}" == "short" ]]; then
  STOP_OPTION="ndays"
  STOP_N="1"
else
  STOP_OPTION="nmonths"
  STOP_N="2"
  WALLTIME="06:00:00"
  PECOUNT="2150"
fi

# Apply explicit overrides if provided
if [[ -n "${STOP_N_OVERRIDE}" ]]; then STOP_N="${STOP_N_OVERRIDE}"; fi
if [[ -n "${STOP_OPTION_OVERRIDE}" ]]; then STOP_OPTION="${STOP_OPTION_OVERRIDE}"; fi

# ---- Determine cime/scripts location ----

CIME_SCRIPTS=""
if [[ -n "${CAM_FORK_PATH}" && -d "${CAM_FORK_PATH}/cime/scripts" ]]; then
  CIME_SCRIPTS="${CAM_FORK_PATH}/cime/scripts"
else
  CIME_SCRIPTS="${CESM_ROOT}/cime/scripts"
fi

CREATE_NEWIN="${CIME_SCRIPTS}/create_newcase"
[[ -x "${CREATE_NEWIN}" ]] || die "create_newcase not found at: ${CREATE_NEWIN}
Checked:
  - ${CAM_FORK_PATH:+${CAM_FORK_PATH}/cime/scripts}
  - ${CESM_ROOT}/cime/scripts
Tip: set --use-fork to your CESM fork containing cime/scripts, or adjust CESM_ROOT."

# ---- Paths ----
CASEDIR="/glade/derecho/scratch/${USER}/${CASE_NAME}"

# ---- Optional switches ----
if [[ "${CHEMISTRY}" == "true" ]]; then
  COMPSET="FHISTC_MTt4s"
fi

# ---- Echo config ----
echo "[fmt-ne30pg3] CASE_NAME=${CASE_NAME}"
echo "[fmt-ne30pg3] RUN_PROFILE=${RUN_PROFILE}"
echo "[fmt-ne30pg3] SKIP_BUILD=${SKIP_BUILD}"
echo "[fmt-ne30pg3] CHEMISTRY=${CHEMISTRY}, PERFORMANCE_ANALYSIS=${PERF_ANALYSIS}"
echo "[fmt-ne30pg3] CAM_FORK_PATH=${CAM_FORK_PATH:-<none>}"
echo "[fmt-ne30pg3] STOP_OPTION=${STOP_OPTION}, STOP_N=${STOP_N}"
echo "[fmt-ne30pg3] PROJECT=${PROJECT}, CESM_ROOT=${CESM_ROOT}"
echo "[fmt-ne30pg3] CIME_SCRIPTS=${CIME_SCRIPTS}"
echo "[fmt-ne30pg3] MACHINE=${MACHINE}, QUEUE=${QUEUE}, WALLTIME=${WALLTIME}"
echo "[fmt-ne30pg3] COMPSET=${COMPSET}, RES=${RES}"
echo "[fmt-ne30pg3] PECOUNT=${PECOUNT}"
echo "[fmt-ne30pg3] CASEDIR=${CASEDIR}"

# ---- Create case ----
if [[ -d "${CASEDIR}" ]]; then
  die "Case directory already exists: ${CASEDIR}"
fi

"${CREATE_NEWIN}" \
  --case "${CASEDIR}" \
  --compset "${COMPSET}" \
  --res "${RES}" \
  --machine "${MACHINE}" \
  --project "${PROJECT}" \
  --queue "${QUEUE}" \
  --walltime "${WALLTIME}" \
  --pecount "${PECOUNT}" \
  --run-unsupported

cd "${CASEDIR}"

./xmlchange "STOP_OPTION=${STOP_OPTION}"
./xmlchange "STOP_N=${STOP_N}"
./xmlchange "TIMER_LEVEL=10"
# Disable short-run archiving
if [[ "${RUN_PROFILE}" == "short" ]]; then
  ./xmlchange "DOUT_S=FALSE"
fi

# Write user_nl_cam BEFORE setup (bnd_topo always; rest depends on RUN_PROFILE)
if [[ "${RUN_PROFILE}" == "short" ]]; then
  cat > "user_nl_cam" <<'NL'
bnd_topo = "/glade/campaign/cgd/amp/pel/topo/cesm3/ne30pg3_gmted2010_modis_bedmachine_nc3000_Laplace0100_noleak_greendlndantarcsgh30fac2.50_20250708.nc"
ncdata         = '/glade/campaign/cesm/cesmdata/inputdata/atm/cam/inic/se/c153_ne30pg3_FMTHIST_x02.cam.i.1990-01-01-00000_c240618.nc'
interpolate_output  =  .true.,  .true., .true., .false., .false., .true.,  .true.
interpolate_nlat    =     192,     192,    192,     192,     192,     192,   192
interpolate_nlon    =     288,     288,    288,     288,     288,     288,   288

empty_htapes = .true.
fincl2 = 'PRECT', 'PRECC', 'FLUT', 'U850', 'U200', 'V850', 'V200', 'OMEGA', 'PSL','OMEGA500','OMEGA850','U','V'
fincl3 = 'U','V'
nhtfrq              =       0,     -3, -3
ndens               =       2,       2
avgflag_pertape(2) = 'I'
avgflag_pertape(3) = 'I'
NL
else
  cat > "user_nl_cam" <<'NL'
bnd_topo = "/glade/campaign/cgd/amp/pel/topo/cesm3/ne30pg3_gmted2010_modis_bedmachine_nc3000_Laplace0100_noleak_greendlndantarcsgh30fac2.50_20250708.nc"
empty_htapes = .true.
NL
fi

echo "[fmt-ne30pg3] Wrote user_nl_cam with requested settings for RUN_PROFILE=${RUN_PROFILE}."

# If performance analysis requested, strip all fincl* lines to avoid I/O
if [[ "${PERF_ANALYSIS}" == "true" ]]; then
  if [[ -f user_nl_cam ]]; then
    # Remove lines that start with optional whitespace followed by fincl plus optional digits
    sed -i -E '/^[[:space:]]*fincl[0-9]*[[:space:]]*=.*/d' user_nl_cam
    echo "[fmt-ne30pg3] --performance_analysis: removed fincl* lines from user_nl_cam."
  fi
fi


# Now run setup
./case.setup

# If skipping build, do not build or submit
if [[ "${SKIP_BUILD}" == "true" ]]; then
  echo "[fmt-ne30pg3] --skip-build set: skipping case.build and case.submit."
  echo "[fmt-ne30pg3] Next steps:"
  echo "  cd ${CASEDIR}"
  echo "  ./case.build"
  echo "  ./case.submit"
  exit 0
fi

./case.build
./case.submit

echo "[fmt-ne30pg3] Case ${CASE_NAME} submitted successfully."
