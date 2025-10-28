python3 timing.py data/ESMF_Profile.MTt4s5400_baseline \
  --png output/MTt4s5400_OptDennisOptSFOptReconLau_polished.png \
  --timers "dyn_run" "prim_advec_tracers_fvm" "prim_advance_exp" \
  "bc_physics" "ac_physics" "p_d_coupling" "d_p_coupling"\
  --timers_names_on_plot \
    "dynamics (total)" "dynamics (tracer advection)" "dynamics (solve u,v,T,p)" \
         "physics before coupler" \
    "physics after coupler" \
    "physics->dynamics coupling" \
    "dynamics->physics coupling" \
  --optimized-summary data/ESMF_Profile.MTt4s5400_OptDennisOptSFOptReconLau \
  --legend-label "Optimized B4B" \
  --baseline-label "Baseline" \
  --title "MTt4s (139 tracers; 93 levels), PEs=5400" \
  --annotate-threshold 5

python3 timing.py data/ESMF_Profile.MTt4s5400_baseline \
  --png output/MTt4s5400_OptDennisOptSFOptReconLau_hypervis1_polished.png \
  --timers "dyn_run" "prim_advec_tracers_fvm" "prim_advance_exp" \
  "bc_physics" "ac_physics" "p_d_coupling" "d_p_coupling"\
  --timers_names_on_plot \
    "dynamics (total)" "dynamics (tracer advection)" "dynamics (solve u,v,T,p)" \
         "physics before coupler" \
    "physics after coupler" \
    "physics->dynamics coupling" \
    "dynamics->physics coupling" \
  --optimized-summary data/ESMF_Profile.MTt4s5400_OptDennisOptSFOptReconLau_hypervis1 \
  --legend-label "Optimized B4B + reduced div damp" \
  --baseline-label "Baseline" \
  --title "MTt4s (139 tracers; 93 levels), PEs=5400" \
  --annotate-threshold 5

python3 timing.py data/ESMF_Profile.MTso5400_baseline \
  --png output/MTso5400_OptDennisOptSFOptReconLau_polished.png \
  --timers "dyn_run" "prim_advec_tracers_fvm" "prim_advance_exp" \
  "bc_physics" "ac_physics" "p_d_coupling" "d_p_coupling"\
  --timers_names_on_plot \
    "dynamics (total)" "dynamics (tracer advection)" "dynamics (solve u,v,T,p)" \
         "physics before coupler" \
    "physics after coupler" \
    "physics->dynamics coupling" \
    "dynamics->physics coupling" \
  --optimized-summary data/ESMF_Profile.MTso5400_OptDennisOptSFOptReconLau \
  --legend-label "Optimized B4B" \
  --baseline-label "Baseline" \
  --title "MTso (41 tracers; 93 levels), PEs=5400" \
  --annotate-threshold 5 --faster-label-offset -1.4

python3 timing.py data/ESMF_Profile.MTso5400_baseline \
  --png output/MTso5400_OptDennisOptSFOptReconLau_hypervis1_polished.png \
  --timers "dyn_run" "prim_advec_tracers_fvm" "prim_advance_exp" \
  "bc_physics" "ac_physics" "p_d_coupling" "d_p_coupling"\
  --timers_names_on_plot \
    "dynamics (total)" "dynamics (tracer advection)" "dynamics (solve u,v,T,p)" \
         "physics before coupler" \
    "physics after coupler" \
    "physics->dynamics coupling" \
    "dynamics->physics coupling" \
  --optimized-summary data/ESMF_Profile.MTso5400_OptDennisOptSFOptReconLau_hypervis1 \
  --legend-label "Optimized B4B + reduced div damp" \
  --baseline-label "Baseline" \
  --title "MTso (41 tracers; 93 levels), PEs=5400" \
  --annotate-threshold 5 --faster-label-offset 0

python3 timing.py data/ESMF_Profile.MTso5400_baseline \
  --png output/MTso_versus_t4s_5400_physics_only_baseline \
  --timers "ac_physics" "macrop_tend" "chemdr" "microp_tend" "gw_tend" "radiation" "microp_aero_run" \
  --timers_names_on_plot \
      "physics after coupler" \
      "CLUBB (macrophysics)" \
      "chemdr (MOZART chemistry)" \
      "PUMAS (microphysics)" \
      "gravity wave drag" \
      "radiation" \
      "aerosol activation processes" \
  --optimized-summary data/ESMF_Profile.MTt4s5400_baseline \
  --legend-label "Baseline MTt4s" \
  --baseline-label "Baseline MTso" \
  --title "MTso (41 tracers; 93 levels), PEs=5400" \
  --annotate-threshold 5 --faster-label-offset 0  --use-times

python3 timing.py data/ESMF_Profile.MTso5400_baseline \
	--png output/MTso_versus_t4s_5400_baseline \
  --timers "dyn_run" "prim_advec_tracers_fvm" "prim_advance_exp" \
  "bc_physics" "ac_physics" "p_d_coupling" "d_p_coupling"\
  --timers_names_on_plot \
    "dynamics (total)" "dynamics (tracer advection)" "dynamics (solve u,v,T,p)" \
         "physics before coupler" \
    "physics after coupler" \
    "physics->dynamics coupling" \
    "dynamics->physics coupling" \
  --optimized-summary data/ESMF_Profile.MTt4s5400_baseline \
  --legend-label "Optimized B4B + reduced div damp" \
  --baseline-label "Baseline" \
  --title "MTso (41 tracers; 93 levels), PEs=5400" \
  --annotate-threshold 5 --faster-label-offset 0  --use-times






