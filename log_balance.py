# Close PuTTY first (it locks the COM port).
#   py -3.13 log_balance.py COM7 balance.csv
# or:
#   log_balance.bat COM7 balance.csv
import csv
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("This Python has no pyserial. Use Anaconda:")
    print(r"  C:\Users\DELL\anaconda3\python.exe log_balance.py COM7 balance.csv")
    print("or:  log_balance.bat COM7 balance.csv")
    sys.exit(1)


def s16(h):
    v = int(h, 16)
    return v - 65536 if v >= 32768 else v


def main():
    if len(sys.argv) < 2:
        print("Ports:")
        for p in list_ports.comports():
            print(" ", p.device, p.description)
        print("Usage: log_balance.bat COM7 balance.csv")
        sys.exit(1)
    port = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "balance.csv"
    ser = serial.Serial(port, 115200, timeout=1)
    time.sleep(0.2)
    ser.reset_input_buffer()
    print("logging", port, "->", out, "  Ctrl+C to stop")
    n = 0
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t_s", "ax", "ay", "az", "theta_deg", "uL", "uR", "armed", "killed"])
        f.flush()
        t0 = time.time()
        while True:
            line = ser.readline().decode("ascii", "ignore").strip()
            parts = line.split()
            if len(parts) < 7:
                continue
            try:
                ax, ay, az, th, ul, ur, fl = [s16(x) for x in parts[:7]]
            except ValueError:
                continue
            w.writerow(
                [
                    round(time.time() - t0, 3),
                    ax,
                    ay,
                    az,
                    th / 100.0,
                    ul,
                    ur,
                    fl & 1,
                    (fl >> 1) & 1,
                ]
            )
            n += 1
            if n % 25 == 0:
                f.flush()
                print("theta=%.2f uL=%d flags=%d" % (th / 100.0, ul, fl))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nsaved")
    except serial.SerialException as e:
        print("COM error:", e)
        print("Close PuTTY, then run again.")
        sys.exit(1)
