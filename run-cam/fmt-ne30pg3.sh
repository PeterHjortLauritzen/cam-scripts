#!/usr/bin/env bash
# fmt-ne30pg3.sh — create/run an NE30pg3 CAM case with sane arg parsing
# Usage:
#   ./fmt-ne30pg3.sh [--use-fork PATH] [--short|--long] [--skip-build] CASE_NAME
#
# Frequently used:
#
#  ./fmt-ne30pg3.sh --use-fork /glade/u/home/pel/src/cam_development --short --skip-build test001
#

set -euo pipefail

# ---- Defaults ----
RUN_PROFILE="long"
STOP_OPTION_DEFAULT="ndays"
STOP_N_SHORT_DEFAULT=1
STOP_N_LONG_DEFAULT=5

CAM_FORK_PATH=""
CASE_NAME=""
SKIP_BUILD="false"

# Derecho/NCAR environment defaults
PROJECT="P03010039"                     # default project code
CESM_ROOT="/glade/work/$USER/cesm"      # fallback CESM root
MACHINE="derecho"
QUEUE="main"
WALLTIME="00:30:00"

COMPSET="FHISTC_MTso"
RES="ne30pg3_ne30pg3_mg17"
#RES="f09_f09_mg17"
# ---- Helpers ----
usage() {
  cat <<EOF
Usage: $(basename "$0") [--use-fork PATH] [--short|--long] [--skip-build] CASE_NAME

Options:
  --use-fork PATH   Path to your CESM/CAM fork (uses its cime/scripts if present).
  --short           One-day smoke test (STOP_N=${STOP_N_SHORT_DEFAULT}).
  --long            Longer run (STOP_N=${STOP_N_LONG_DEFAULT}).
  --skip-build      Create and setup the case, but DO NOT build or submit.
  -h, --help        Show this help.

Defaults:
  PROJECT=${PROJECT}
  CESM_ROOT=${CESM_ROOT}
  MACHINE=${MACHINE}, QUEUE=${QUEUE}, WALLTIME=${WALLTIME}
  COMPSET=${COMPSET}, RES=${RES}

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
STOP_OPTION="${STOP_OPTION_DEFAULT}"
if [[ "${RUN_PROFILE}" == "short" ]]; then
  STOP_OPTION="ndays"; STOP_N="${STOP_N_SHORT_DEFAULT}"
else
  STOP_N="${STOP_N_LONG_DEFAULT}"
fi

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

# ---- Echo config ----
echo "[fmt-ne30pg3] CASE_NAME=${CASE_NAME}"
echo "[fmt-ne30pg3] RUN_PROFILE=${RUN_PROFILE}"
echo "[fmt-ne30pg3] SKIP_BUILD=${SKIP_BUILD}"
echo "[fmt-ne30pg3] CAM_FORK_PATH=${CAM_FORK_PATH:-<none>}"
echo "[fmt-ne30pg3] STOP_OPTION=${STOP_OPTION}, STOP_N=${STOP_N}"
echo "[fmt-ne30pg3] PROJECT=${PROJECT}, CESM_ROOT=${CESM_ROOT}"
echo "[fmt-ne30pg3] CIME_SCRIPTS=${CIME_SCRIPTS}"
echo "[fmt-ne30pg3] MACHINE=${MACHINE}, QUEUE=${QUEUE}, WALLTIME=${WALLTIME}"
echo "[fmt-ne30pg3] COMPSET=${COMPSET}, RES=${RES}"
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
interpolate_type = 1,0,1,1,1,1,1

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

mfilt        =       0,       0,     20,      40,      12,       120,      1,   1
nhtfrq              =       0,       0,    -24,      -3,       0,       -2,      0,  -8760
ndens               =       2,       2,      2,       2,       2,       1,      2,   1
interpolate_output  =  .true.,  .false., .true., .true., .false., .true.,  .true.
interpolate_nlat    =     192,     192,    192,     192,     192,     192,   192
interpolate_nlon    =     288,     288,    288,     288,     288,     288,   288 

empty_htapes = .true.

fincl1 = 'ACTNI', 'ACTNL', 'ACTREI', 'ACTREL', 'AODDUST', 'AODVIS', 'AODVISdn','BURDENBC',
'BURDENDUST', 'BURDENPOM', 'BURDENSEASALT',
'BURDENSO4', 'BURDENSOA', 'CAPE', 'CCN3', 'CDNUMC', 'CH4', 'CLDHGH', 'CLDICE', 'CLDLIQ', 'CLDLOW',
'CLDMED', 'CLDTOT', 'CLOUD', 'CMFMC_DP',
'CT_H2O', 'DCQ', 'DQCORE', 'DTCOND', 'DTCORE', 'DTV', 'EVAPPREC', 'EVAPSNOW', 'FCTI', 'FCTL', 'FICE', 'FLDS', 'FLNS', 'FLNSC', 'FLNT', 'FLNTC', 'FLUT',
'FREQZM', 'FSDS', 'FSDSC', 'FSNS', 'FSNSC', 'FSNT', 'FSNTC', 'FSNTOA', 'ICEFRAC', 'LANDFRAC', 'LHFLX', 'LWCF', 'MPDICE', 'MPDLIQ', 'MPDQ', 'MPDT',
'OCNFRAC', 'OMEGA', 'OMEGA500', 'PBLH', 'PHIS', 'PINT', 'PMID', 'PRECC', 'PRECL', 'PRECSC', 'PRECSL', 'PRECT', 'PS', 'PSL', 'PTEQ', 'PTTEND', 'Q',
'QFLX', 'QRL', 'QRS', 'QTGW', 'RCMTEND_CLUBB', 'RELHUM', 'RVMTEND_CLUBB', 'SHFLX', 'SOLIN', 'SST',
'STEND_CLUBB', 'SWCF',
'T', 'TAUX', 'TAUY', 'TFIX', 'TGCLDIWP', 'TGCLDLWP', 'TMQ', 'TREFHT', 'TS', 'TTGW', 'U', 'U10',
'UBOT', 'UTGWORO', 'UTGW_TOTAL',
'V', 'VBOT', 'VTGWORO', 'VTGW_TOTAL', 'WPRTP_CLUBB', 'WPTHLP_CLUBB', 'Z3', 'ZMDQ', 'ZMDT', 'N2O',
 'CO2','CFC11','CFC12',
'AODVISdn','AODDUSTdn','CCN3', 'CDNUMC', 'H2O', 'NUMICE', 'NUMLIQ','OMEGA500',
 'AQSO4_H2O2','AQSO4_O3', 'bc_a1', 'bc_a4', 'dst_a1', 'dst_a2', 'dst_a3', 'ncl_a1',
'ncl_a1', 'ncl_a2', 'ncl_a3', 'pom_a1', 'pom_a4', 'so4_a1', 'so4_a2', 'so4_a3', 'soa_a2' ,
'soa_a1', 'num_a1', 'num_a2', 'num_a3', 'num_a4',
'bc_a1SFWET', 'bc_a4SFWET', 'dst_a1SFWET', 'dst_a2SFWET', 'dst_a3SFWET', 'ncl_a1SFWET',
'ncl_a2SFWET', 'ncl_a3SFWET', 'pom_a1SFWET', 'pom_a4SFWET', 'so4_a1SFWET', 'so4_a2SFWET', 'so4_a3SFWET', 'soa_a1SFWET',
'soa_a2SFWET', 'bc_c1SFWET', 'bc_c4SFWET', 'dst_c1SFWET', 'dst_c2SFWET', 'dst_c3SFWET', 'ncl_c1SFWET', 'ncl_c2SFWET',
'ncl_c3SFWET', 'pom_c1SFWET', 'pom_c4SFWET', 'so4_c1SFWET', 'so4_c2SFWET', 'so4_c3SFWET', 'soa_c1SFWET', 'soa_c2SFWET',
'bc_a1DDF', 'bc_a4DDF', 'dst_a1DDF', 'dst_a2DDF', 'dst_a3DDF', 'ncl_a1DDF', 'ncl_a2DDF', 'ncl_a3DDF',
'pom_a1DDF', 'pom_a4DDF', 'so4_a1DDF', 'so4_a2DDF', 'so4_a3DDF', 'soa_a1DDF', 'soa_a2DDF',
'so4_a1_CLXF', 'so4_a2_CLXF', 'SFbc_a4', 'SFpom_a4', 'SFso4_a1', 'SFso4_a2',
'so4_a1_sfgaex1', 'so4_a2_sfgaex1', 'so4_a3_sfgaex1', 'soa_a1_sfgaex1', 'soa_a2_sfgaex1',
'SFdst_a1','SFdst_a2', 'SFdst_a3', 'SFncl_a1', 'SFncl_a2', 'SFncl_a3',
'num_a2_sfnnuc1', 'SFSO2', 'OCN_FLUX_DMS', 'SAD_SULFC', 'SAD_TROP', 'SAD_AERO', 'vIVT'
fincl2 ='FISCCP1_COSP','CLDTOT_ISCCP','MEANCLDALB_ISCCP','CLDLOW_CAL','CLDMED_CAL','CLDHGH_CAL','CLDTOT_CAL',
'CLDTOT_CAL_ICE','CLDTOT_CAL_LIQ','CLDTOT_CAL_UN','CLD_CAL','CLD_CAL_LIQ','CLD_CAL_ICE','CLD_CAL_UN',
'CLDTOT_CALCS','CLDTOT_CS','CLD_MISR','CLTMODIS','CLWMODIS','CLIMODIS','CLHMODIS','CLMMODIS','CLLMODIS',
'LWPMODIS','IWPMODIS','CLMODIS'

fincl3 = 'PRECT', 'PRECC', 'FLUT', 'U850', 'U200', 'V850', 'V200', 'OMEGA500', 'TS', 'SST', 'PSL'
fincl4 =  'PRECC','PRECL'
fincl5 = 'Uzm','Vzm','Wzm','THzm', 'VTHzm','WTHzm','UVzm','UWzm'
phys_grid_ctem_nfreq=-6
phys_grid_ctem_zm_nbas=120
phys_grid_ctem_za_nlat=90

solar_irrad_data_file= '/glade/campaign/cesm/development/cross-wg/inputdata/SolarForcingCMIP7piControl_c20250103.nc'

micro_mg_dcs= 600.D-6
cldfrc_dp1 =  0.05
clubb_c8 = 4.6
NL
fi

echo "[fmt-ne30pg3] Wrote user_nl_cam with requested settings for RUN_PROFILE=${RUN_PROFILE}."

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
