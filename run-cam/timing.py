#!/usr/bin/env python3
"""
ESMF timing summary parser & reporter with optional optimized overlay.

- Parses ESMF_Profile.summary "Region" table lines (with or without PETs/PEs columns)
- Identifies children of a region by indentation
- Prints a table, optionally writes CSV, and optionally plots top-N children
- Baseline: horizontal bars with min/max as error bars
- Optimized overlay: dark red line with filled circle markers
- Annotations: if optimized differs by >= 5.0% from baseline for a child, write
  "X.X% faster" or "X.X% slower" on the right-hand side in the white area

Examples
  python timing.py ESMF_Profile.summary --region dyn_run --top 12 --csv baseline.csv --png baseline.png
  python timing.py ESMF_Profile.summary --region dyn_run \
         --optimized-summary ESMF_Profile_optimized.summary \
         --top 15 --csv compare.csv --png compare.png
"""

import re
import sys
import csv
import argparse
from pathlib import Path
from typing import List, Dict, Tuple, Optional

ANNOTATE_THRESHOLD_PCT = 5.0  # percent

def parse_esmf_summary(path: str) -> List[Dict]:
    """Return list of dict rows parsed from an ESMF_Profile.summary Region table."""
    text = Path(path).read_text(errors="replace")
    lines = text.splitlines()

    # Pattern: optional PETs/PEs between name and Count
    pat = re.compile(
        r"^(?P<indent>\s*)(?P<name>\S.*?\S|\S)\s+"
        r"(?:(?P<PETs>\d+)\s+(?P<PEs>\d+)\s+)?"
        r"(?P<count>MULTIPLE|\d+)\s+"
        r"(?P<mean>\d+\.\d+)\s+"
        r"(?P<min>\d+\.\d+)\s+"
        r"(?P<minpet>\d+)\s+"
        r"(?P<max>\d+\.\d+)\s+"
        r"(?P<maxpet>\d+)\s*$"
    )

    rows = []
    for line in lines:
        m = pat.match(line)
        if not m:
            continue
        g = m.groupdict()
        row = {
            "indent": len(g["indent"] or ""),
            "region": (g["name"] or "").strip(),
            "PETs": int(g["PETs"]) if g.get("PETs") else None,
            "PEs": int(g["PEs"]) if g.get("PEs") else None,
            "Count": None if g["count"] == "MULTIPLE" else int(g["count"]),
            "Mean (s)": float(g["mean"]),
            "Min (s)": float(g["min"]),
            "Min PET": int(g["minpet"]),
            "Max (s)": float(g["max"]),
            "Max PET": int(g["maxpet"]),
        }
        rows.append(row)
    if not rows:
        raise RuntimeError("No Region rows parsed. Is this an ESMF_Profile.summary file?")
    return rows

def find_region_rows(rows: List[Dict], region: str) -> Tuple[Optional[Dict], Optional[int]]:
    """Return (parent_row, parent_index) for the given region name (exact match)."""
    for i, r in enumerate(rows):
        if r["region"] == region:
            return r, i
    return None, None

def collect_children(rows: List[Dict], parent_idx: int) -> List[Dict]:
    """Collect contiguous children with indent > parent_indent after parent_idx."""
    parent_indent = rows[parent_idx]["indent"]
    out = []
    for j in range(parent_idx + 1, len(rows)):
        if rows[j]["indent"] <= parent_indent:
            break
        out.append(rows[j])
    return out

def build_region_map(rows: List[Dict]) -> Dict[str, Dict]:
    """Map region name to its row (last occurrence wins if duplicates)."""
    m = {}
    for r in rows:
        m[r["region"]] = r
    return m

def main(argv=None):
    ap = argparse.ArgumentParser(description="Parse ESMF timing summary and report children of a region, with optional optimized overlay.")
    ap.add_argument("summary", help="Path to baseline ESMF_Profile.summary file")
    ap.add_argument("--region", default=None, help="Region to inspect (default: dyn_run if present, else first row)")
    ap.add_argument("--top", type=int, default=12, help="Show top N children by baseline mean time (default: 12)")
    ap.add_argument("--csv", default=None, help="Write selected children (baseline & optional optimized) to CSV")
    ap.add_argument("--png", default=None, help="Write bar chart of top N children to PNG")
    ap.add_argument("--optimized-summary", default=None, help="Path to optimized ESMF_Profile.summary to overlay as a line")
    args = ap.parse_args(argv)

    base_rows = parse_esmf_summary(args.summary)

    # choose region
    region = args.region
    if region is None:
        region = "dyn_run" if any(r["region"] == "dyn_run" for r in base_rows) else base_rows[0]["region"]

    parent, pidx = find_region_rows(base_rows, region)
    if parent is None:
        raise SystemExit(f"Region '{region}' not found in baseline.\nExamples: {', '.join(sorted(set(r['region'] for r in base_rows[:30])))}")

    base_children = collect_children(base_rows, pidx)
    if not base_children:
        print(f"No children found under region '{region}' in baseline.")
        return 0

    pmean = parent["Mean (s)"]
    for r in base_children:
        r["% of parent (mean)"] = 100.0 * (r["Mean (s)"] / pmean) if pmean > 0 else float("nan")

    # Sort baseline children by mean and truncate to top N
    base_children_sorted = sorted(base_children, key=lambda r: r["Mean (s)"], reverse=True)[: args.top]

    # Prepare optimized overlay if provided: restrict to same child list & same order
    opt_map = {}
    if args.optimized_summary:
        opt_rows = parse_esmf_summary(args.optimized_summary)
        opt_parent, opt_pidx = find_region_rows(opt_rows, region)
        if opt_parent is None:
            print(f"Warning: region '{region}' not found in optimized file; overlay will be empty.", file=sys.stderr)
        opt_map = build_region_map(opt_rows)

    # Print table header
    print(f"Region: {region} (baseline parent mean = {pmean:.6f} s) — Top {args.top} children by mean time")
    header_cols = ["Region", "BaseMean(s)", "BaseMin(s)", "BaseMax(s)"]
    if args.optimized_summary:
        header_cols += ["OptMean(s)", "OptMin(s)", "OptMax(s)", "Speedup(Base/Opt)"]
    print("{:40s} {:>12s} {:>12s} {:>12s}{}".format(
        header_cols[0], header_cols[1], header_cols[2], header_cols[3],
        "" if not args.optimized_summary else " {:>14s} {:>12s} {:>12s} {:>16s}".format(header_cols[4], header_cols[5], header_cols[6], header_cols[7])
    ))

    # Assemble CSV rows and plotting vectors
    csv_rows = []
    labels = []
    base_means = []
    base_xerr_low = []   # mean - min
    base_xerr_high = []  # max - mean
    opt_means = []       # will keep None when missing

    for r in base_children_sorted:
        name = r["region"]
        base_mean = r["Mean (s)"]
        base_min = r["Min (s)"]
        base_max = r["Max (s)"]
        labels.append(name)
        base_means.append(base_mean)
        base_xerr_low.append(max(0.0, base_mean - base_min))
        base_xerr_high.append(max(0.0, base_max - base_mean))

        row_out = {
            "region": name,
            "baseline_mean_s": base_mean,
            "baseline_min_s": base_min,
            "baseline_max_s": base_max,
            "baseline_count": r.get("Count"),
            "baseline_PETs": r.get("PETs"),
            "baseline_PEs": r.get("PEs"),
        }

        if args.optimized_summary and name in opt_map:
            o = opt_map[name]
            opt_mean = o["Mean (s)"]
            opt_min = o["Min (s)"]
            opt_max = o["Max (s)"]
            opt_means.append(opt_mean)
            speedup = (base_mean / opt_mean) if opt_mean and opt_mean > 0 else None
            row_out.update({
                "optimized_mean_s": opt_mean,
                "optimized_min_s": opt_min,
                "optimized_max_s": opt_max,
                "optimized_count": o.get("Count"),
                "optimized_PETs": o.get("PETs"),
                "optimized_PEs": o.get("PEs"),
                "speedup_base_over_opt": speedup,
            })
            print("{:40s} {:12.6f} {:12.6f} {:12.6f} {:14.6f} {:12.6f} {:12.6f} {:16.3f}".format(
                name[:40], base_mean, base_min, base_max, opt_mean, opt_min, opt_max, speedup if speedup else float('nan')
            ))
        else:
            opt_means.append(None if args.optimized_summary else 0.0)
            if args.optimized_summary:
                print("{:40s} {:12.6f} {:12.6f} {:12.6f} {:>14s} {:>12s} {:>12s} {:>16s}".format(
                    name[:40], base_mean, base_min, base_max, "-", "-", "-", "-"
                ))
        csv_rows.append(row_out)

    # Write CSV if requested
    if args.csv:
        fieldnames = ["region",
                      "baseline_mean_s", "baseline_min_s", "baseline_max_s",
                      "baseline_count", "baseline_PETs", "baseline_PEs"]
        if args.optimized_summary:
            fieldnames += ["optimized_mean_s", "optimized_min_s", "optimized_max_s",
                           "optimized_count", "optimized_PETs", "optimized_PEs",
                           "speedup_base_over_opt"]
        with open(args.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fieldnames)
            w.writeheader()
            for row in csv_rows:
                w.writerow(row)
        print(f"Wrote CSV: {args.csv}")

    # Plot if requested
    if args.png:
        import matplotlib.pyplot as plt

        # Horizontal bars for baseline mean; show min/max uncertainty as xerr
        means_for_plot = list(reversed(base_means))
        xerr_low = list(reversed(base_xerr_low))
        xerr_high = list(reversed(base_xerr_high))
        labs_for_plot = list(reversed(labels))

        fig, ax = plt.subplots()
        ax.barh(labs_for_plot, means_for_plot, xerr=[xerr_low, xerr_high])

        # Overlay optimized means as a dark red line with filled circles
        if args.optimized_summary:
            opt_vals_plot = [opt_means[labels.index(lbl)] if opt_means[labels.index(lbl)] is not None else float('nan') for lbl in labs_for_plot]
            ax.plot(opt_vals_plot, labs_for_plot, marker='o', linewidth=1.5, label="Optimized (mean)", color='darkred')
            ax.legend()

            # Annotate percent faster/slower when >= threshold; right-hand margin, right-aligned
            fig.canvas.draw()
            xmin, xmax = ax.get_xlim()
            xmax_annot = xmax * 0.995
            for y_idx, lbl in enumerate(labs_for_plot):
                base_val = means_for_plot[y_idx]
                opt_val = opt_vals_plot[y_idx]
                # skip missing/NaN
                if isinstance(opt_val, float) and (opt_val != opt_val):  # NaN
                    continue
                if opt_val is None:
                    continue
                if base_val and base_val > 0:
                    pct = (base_val - float(opt_val)) / base_val * 100.0
                    if abs(pct) >= ANNOTATE_THRESHOLD_PCT:
                        text = f"{abs(pct):.1f}% {'faster' if pct > 0 else 'slower'}"
                        ax.text(xmax_annot, labs_for_plot[y_idx], text, va='center', ha='right')

            # Expand x-limits slightly in case labels clip
            xmin2, xmax2 = ax.get_xlim()
            ax.set_xlim(xmin2, xmax2 * 1.15)

        ax.set_xlabel("Mean time (s)")
        ax.set_title(f"ESMF timing: children of {region} — baseline bars (min/max) + optimized line (dark red)")
        fig.tight_layout()
        fig.savefig(args.png, dpi=150)
        print(f"Wrote PNG: {args.png}")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
