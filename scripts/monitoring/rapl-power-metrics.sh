#!/bin/bash
# RAPL Power Metrics Collector for Prometheus Node Exporter Textfile Collector
# Reads CPU/package power consumption from RAPL (Intel/AMD)
#
# Usage:
#   ./rapl-power-metrics.sh > /path/to/textfile_collector/rapl.prom

POWERCAP_PATH="/sys/class/powercap"

# Helper to read energy file
read_energy() {
    local file="$1"
    if [ -f "$file" ] && [ -r "$file" ]; then
        cat "$file" 2>/dev/null
    fi
}

# Print header once
echo "# HELP rapl_energy_joules_total Total energy consumed in joules (RAPL)"
echo "# TYPE rapl_energy_joules_total counter"

# Find all RAPL zones
for zone_path in "$POWERCAP_PATH"/intel-rapl:*; do
    [ -d "$zone_path" ] || continue

    zone_name=$(basename "$zone_path")
    # Skip subzones (they have : in the middle like intel-rapl:0:0)
    [[ "$zone_name" == *:*:* ]] && continue

    name_file="$zone_path/name"
    energy_file="$zone_path/energy_uj"

    if [ -f "$name_file" ] && [ -f "$energy_file" ]; then
        domain=$(cat "$name_file" 2>/dev/null)
        energy_uj=$(read_energy "$energy_file")

        if [ -n "$energy_uj" ] && [ -n "$domain" ]; then
            # Convert microjoules to joules using awk
            energy_j=$(awk "BEGIN {printf \"%.6f\", $energy_uj / 1000000}")
            echo "rapl_energy_joules_total{domain=\"$domain\",zone=\"$zone_name\"} $energy_j"
        fi
    fi

    # Also get subzones (cores, uncore, dram)
    for subzone_path in "$zone_path"/intel-rapl:*; do
        [ -d "$subzone_path" ] || continue

        subzone_name=$(basename "$subzone_path")
        sub_name_file="$subzone_path/name"
        sub_energy_file="$subzone_path/energy_uj"

        if [ -f "$sub_name_file" ] && [ -f "$sub_energy_file" ]; then
            sub_domain=$(cat "$sub_name_file" 2>/dev/null)
            sub_energy_uj=$(read_energy "$sub_energy_file")

            if [ -n "$sub_energy_uj" ] && [ -n "$sub_domain" ]; then
                sub_energy_j=$(awk "BEGIN {printf \"%.6f\", $sub_energy_uj / 1000000}")
                echo "rapl_energy_joules_total{domain=\"$sub_domain\",zone=\"$subzone_name\"} $sub_energy_j"
            fi
        fi
    done
done
