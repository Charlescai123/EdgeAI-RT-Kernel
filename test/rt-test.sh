#!/bin/bash

# ======== Default Values ========
cores=$(nproc)
duration=10
interrupted=false

# ======== Parse Arguments ========
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cores)
            cores="$2"
            shift 2
            ;;
        --duration)
            duration="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            exit 1
            ;;
    esac
done

# ======== Cleanup function for early exit ========
cleanup() {
    echo -e "\n[INFO] Cleaning up..."
    killall stress &>/dev/null
    rm -f histogram* output plotcmd
    if [ "$interrupted" = true ]; then
        echo "[INTERRUPTED] Script was terminated early. No plot generated."
        exit 130
    fi
}

# ======== Trap INT (Ctrl+C) and TERM ========
trap 'interrupted=true; cleanup' INT TERM

# ======== Dependency Check ========
echo "[INFO] Checking dependencies..."
for pkg in stress rt-tests gnuplot; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        echo "[WARN] $pkg not found. Installing..."
        sudo apt update
        sudo apt install -y "$pkg"
    else
        echo "[OK] $pkg is already installed."
    fi
done

# ======== Step 1: Start stress load ========
echo "[INFO] Starting stress with $cores CPU threads..."
stress --cpu "$cores" --io 1 --vm 1 --vm-bytes 128M -d 1 &

# ======== Step 2: Run cyclictest ========
echo "[INFO] Running cyclictest for $duration seconds..."
cyclictest -l $((duration * 50000)) -m -Sp99 -i200 -h400 -q > output

# ======== Step 3: Extract Max Latency ========
max=$(grep "Max Latencies" output | tr " " "\n" | sort -n | tail -1 | sed s/^0*//)

# ======== Step 4: Format histogram data ========
grep -v -e "^#" -e "^$" output | tr " " "\t" > histogram

# ======== Step 5: Split histogram per core ========
for i in $(seq 1 $cores); do
    column=$((i + 1))
    cut -f1,$column histogram > histogram$i
done

# ======== Step 6: Generate gnuplot command ========
cat <<EOF > plotcmd
set title "Latency Plot"
set terminal png
set xlabel "Latency (us), max $max us"
set logscale y
set xrange [0:400]
set yrange [0.8:*]
set ylabel "Number of latency samples"
set output "plot.png"
plot \\
EOF

for i in $(seq 1 $cores); do
    cpuno=$((i - 1))
    [[ $i -gt 1 ]] && echo -n ", " >> plotcmd
    echo -n "\"histogram$i\" using 1:2 title \"CPU$cpuno\" with histeps" >> plotcmd
done

# ======== Step 7: Plot and Cleanup ========
echo "[INFO] Plotting result to plot.png..."
gnuplot -persist < plotcmd

cleanup  # Normal exit

echo "[DONE] Test complete. Output saved to plot.png"

