# Data-driven trim from a log. Not a neural net (will not fit on DE0-Nano at 200 Hz).
#   py fit_from_csv.py balance.csv
import csv
import sys


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "balance.csv"
    rows = list(csv.DictReader(open(path)))
    th = [float(r["theta_deg"]) for r in rows]
    ul = [float(r["uL"]) for r in rows]
    n = len(th)
    mean = sum(th) / n
    opp = sum(1 for a, b in zip(th, ul) if a * b < 0) / n
    print("n", n)
    print("mean theta_deg", round(mean, 2))
    print("frac u opposite theta", round(opp, 3))
    print("suggested OFFSET (0.01 deg) ", int(round(mean * 100)))
    print("  (comp_filter OFFSET = fused - this, so use that value as OFFSET)")
    if opp > 0.35:
        print("D is pushing through zero: keep KD_ANG small (4..8), do not raise it.")
    print("FPGA cannot run a large AI model in the 200 Hz loop.")
    print("This log-fit (offset + PD) is the on-device controller.")


if __name__ == "__main__":
    main()
