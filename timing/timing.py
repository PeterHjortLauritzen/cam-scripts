
#!/usr/bin/env python3
import re
import sys
import argparse
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.lines as mlines
from pathlib import Path

def parse_esmf_summary(path: str):
    text = Path(path).read_text(errors="replace")
    lines = text.splitlines()
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
        rows.append({
            "indent": len(g["indent"]),
            "region": g["name"].strip(),
            "Mean (s)": float(g["mean"]),
            "Min (s)": float(g["min"]),
            "Max (s)": float(g["max"]),
        })
    return rows

def extract_named_regions(rows, names):
    return [row for row in rows if row["region"] in names]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("--optimized-summary")
    parser.add_argument("--timers", nargs="+", required=True)
    parser.add_argument("--timers_names_on_plot", nargs="+")
    parser.add_argument("--png")
    parser.add_argument("--title")
    parser.add_argument("--legend-label", default="Optimized")
    parser.add_argument("--baseline-label", default="Baseline")
    parser.add_argument("--annotate-threshold", type=float, default=5.0)
    parser.add_argument("--faster-label-offset", type=float, default=1.4)
    parser.add_argument('--use-times', action='store_true', help='Show speedup as N× faster/slower instead of percentage')
    args = parser.parse_args()

    base_rows = parse_esmf_summary(args.baseline)
    opt_rows = parse_esmf_summary(args.optimized_summary) if args.optimized_summary else []

    base_data = {r["region"]: r for r in extract_named_regions(base_rows, args.timers)}
    opt_data = {r["region"]: r for r in extract_named_regions(opt_rows, args.timers)} if opt_rows else {}

    labels = args.timers_names_on_plot if args.timers_names_on_plot else args.timers
    y = np.arange(len(labels))

    base_means = [base_data[r]["Mean (s)"] for r in args.timers]
    base_lows = [base_data[r]["Mean (s)"] - base_data[r]["Min (s)"] for r in args.timers]
    base_highs = [base_data[r]["Max (s)"] - base_data[r]["Mean (s)"] for r in args.timers]

    fig, ax = plt.subplots(figsize=(8, 4 + 0.4 * len(labels)))
#    ax.barh(y, base_means, xerr=[base_lows, base_highs], align='center', capsize=8, color='#88c2f0', label=args.baseline_label)
    ax.barh(y, base_means, color='#88c2f0', align='center', label=args.baseline_label)
    dy = 0.25  # or adjust as needed
    y_dot = y - dy  # shift UP for visual separation

    ax.errorbar(
        base_means,
        y_dot,
        xerr=[base_lows, base_highs],
        fmt='o',
        color='black',
        markersize=8,
        capsize=4, linewidth=2
    )
# Add dot markers to baseline bars

    y_offset = y-dy 
    ax.errorbar(base_means, y_offset, fmt='o', color='#88c2f0', markersize=8.)

#    ax.legend(handles=[minmax_legend, opt_legend])
    if opt_data:
        opt_means = [opt_data[r]["Mean (s)"] for r in args.timers]
        opt_lows = [opt_data[r]["Mean (s)"] - opt_data[r]["Min (s)"] for r in args.timers]
        opt_highs = [opt_data[r]["Max (s)"] - opt_data[r]["Mean (s)"] for r in args.timers]

        y_offset = y + dy
        ax.errorbar(opt_means, y_offset, xerr=[opt_lows, opt_highs], fmt='o', color='#8B0000', capsize=8, linewidth=2, label=args.legend_label)

        for i, label in enumerate(labels):
            base = base_means[i]
            opt = opt_means[i]
            if base > 0 and opt > 0:
                pct = 100 * (base - opt) / base
                if abs(pct) >= args.annotate_threshold:
                    xpos = max(base, opt) #* 1.10
                    xpos = opt-args.faster_label_offset
#                    xlim = ax.get_xlim()
#                    xpos = min(xpos, xlim[1] * 0.95)
                    label_text = f"{abs(pct):.1f}% {'faster' if pct > 0 else 'slower'}"

                    ax.text(
                        xpos,
                        y[i],
                        label_text,
                        va="center",
                        fontsize=15,
                        color="#8B0000"
                    )
                 #   ax.text(
                 #       xpos,
                 #       y[i],
                 #       f"{pct:+.1f}% faster",
                 #       va="center",
                 #       fontsize=15,
                 #       color="#8B0000"
                 #   )

    ax.set_yticks(y)
    ax.set_yticklabels(labels, fontsize=14)
    ax.invert_yaxis()
    ax.set_xlabel("time (s)")
    ax.set_title(args.title or "Baseline vs Optimized Timings", fontsize=16)

    new_handles = [
        mlines.Line2D([], [], color='#88c2f0', marker='o', linestyle='None', label=args.baseline_label, markersize=6),
        mlines.Line2D([], [], color='#8B0000', marker='o', linestyle='None', label=args.legend_label, markersize=6),
    ]
    ax.legend(handles=new_handles, loc="best", fontsize=14)
    fig.tight_layout()

    if args.png:
        fig.savefig(args.png, dpi=150)
        print(f"Wrote PNG: {args.png}")

if __name__ == "__main__":
    main()
