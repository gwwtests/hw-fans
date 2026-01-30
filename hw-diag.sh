#!/bin/bash
# ThinkPad Hardware Diagnostics - Extended View
# Shows fans, temps, and top CPU/GPU consumers
# Usage: ./hw-diag.sh [-w|--watch] [-c|--clear] [-n NUM] [-h|--help]

set -euo pipefail

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Defaults
TOP_N=5
TEMP_WARN=75
TEMP_CRIT=90

colorize_temp() {
    local temp=$1
    if (( temp >= TEMP_CRIT )); then
        echo -e "${RED}${temp}°C${NC}"
    elif (( temp >= TEMP_WARN )); then
        echo -e "${YELLOW}${temp}°C${NC}"
    else
        echo -e "${GREEN}${temp}°C${NC}"
    fi
}

colorize_percent() {
    local pct=${1%.*}  # Remove decimals
    if (( pct >= 80 )); then
        echo -e "${RED}${1}%${NC}"
    elif (( pct >= 50 )); then
        echo -e "${YELLOW}${1}%${NC}"
    else
        echo -e "${GREEN}${1}%${NC}"
    fi
}

show_header() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║         ThinkPad Hardware Diagnostics                         ║${NC}"
    echo -e "${BOLD}${CYAN}║         ${DIM}${timestamp}${NC}${BOLD}${CYAN}                              ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_system_overview() {
    echo -e "${BOLD}${BLUE}📊 SYSTEM OVERVIEW${NC}"
    echo -e "   ────────────────────────────────────────────"

    # Uptime & Load
    local uptime=$(uptime -p 2>/dev/null | sed 's/up //')
    local load=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    local cpu_cores=$(nproc)

    echo -e "   Uptime:     ${uptime}"
    echo -e "   Load avg:   ${load} ${DIM}(${cpu_cores} cores)${NC}"

    # Memory
    local mem_info=$(free -h | awk '/^Mem:/ {print $3 "/" $2 " (" int($3/$2*100) "%)"}')
    echo -e "   Memory:     ${mem_info}"

    # Swap
    local swap_info=$(free -h | awk '/^Swap:/ {if($2 != "0B" && $2 != "0") print $3 "/" $2; else print "disabled"}')
    echo -e "   Swap:       ${swap_info}"
    echo ""
}

show_fan_status() {
    echo -e "${BOLD}${BLUE}🌀 FAN STATUS${NC}"
    echo -e "   ────────────────────────────────────────────"

    if [[ -r /proc/acpi/ibm/fan ]]; then
        local status=$(grep "status:" /proc/acpi/ibm/fan | awk '{print $2}')
        local speed=$(grep "speed:" /proc/acpi/ibm/fan | awk '{print $2}')
        local level=$(grep "level:" /proc/acpi/ibm/fan | awk '{print $2}')

        # Visual RPM bar
        local max_rpm=5500
        local bar_width=20
        local filled=$((speed * bar_width / max_rpm))
        local bar=""
        for ((i=0; i<bar_width; i++)); do
            if ((i < filled)); then
                bar+="█"
            else
                bar+="░"
            fi
        done

        echo -e "   Status:  ${GREEN}${status}${NC}  |  Level: ${level}"
        echo -e "   Speed:   ${BOLD}${speed} RPM${NC}  [${CYAN}${bar}${NC}]"
    else
        local rpm=$(sensors 2>/dev/null | grep -i "fan1:" | awk '{print $2}')
        if [[ -n "$rpm" ]]; then
            echo -e "   Speed:   ${BOLD}${rpm} RPM${NC}"
        else
            echo -e "   ${YELLOW}No fan data available${NC}"
        fi
    fi
    echo ""
}

show_temperatures() {
    echo -e "${BOLD}${BLUE}🔥 TEMPERATURES${NC}"
    echo -e "   ────────────────────────────────────────────"

    if command -v sensors &>/dev/null; then
        # CPU Package
        local pkg_temp=$(sensors coretemp-isa-0000 2>/dev/null | grep "Package" | grep -oP '\+\K[0-9]+' | head -1)
        if [[ -n "$pkg_temp" ]]; then
            printf "   %-14s $(colorize_temp $pkg_temp)\n" "CPU Package:"
        fi

        # CPU Cores - compact view
        local cores=""
        local core_num=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^Core ]]; then
                local temp=$(echo "$line" | grep -oP '\+\K[0-9]+' | head -1)
                if [[ -n "$temp" ]]; then
                    if [[ -n "$cores" ]]; then cores+=", "; fi
                    cores+="C${core_num}:${temp}°"
                    ((core_num++))
                fi
            fi
        done < <(sensors coretemp-isa-0000 2>/dev/null)
        if [[ -n "$cores" ]]; then
            echo -e "   Cores:        ${DIM}${cores}${NC}"
        fi

        # Other temps in a row
        local pch=$(sensors pch_cannonlake-virtual-0 2>/dev/null | grep "temp1:" | grep -oP '\+\K[0-9]+' | head -1)
        local wifi=$(sensors iwlwifi_1-virtual-0 2>/dev/null | grep "temp1:" | grep -oP '\+\K[0-9]+' | head -1)
        local nvme=$(sensors nvme-pci-3d00 2>/dev/null | grep "Composite:" | grep -oP '\+\K[0-9]+' | head -1)

        echo -n "   Other:        "
        [[ -n "$pch" ]] && echo -n "PCH:${pch}° "
        [[ -n "$wifi" ]] && echo -n "WiFi:${wifi}° "
        [[ -n "$nvme" ]] && echo -n "NVMe:${nvme}°"
        echo ""
    fi
    echo ""
}

show_cpu_info() {
    echo -e "${BOLD}${BLUE}⚡ CPU STATUS${NC}"
    echo -e "   ────────────────────────────────────────────"

    # CPU frequency
    local freq_cur=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    local freq_max=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null)
    local governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)

    if [[ -n "$freq_cur" ]]; then
        local freq_mhz=$((freq_cur / 1000))
        local freq_max_mhz=$((freq_max / 1000))
        echo -e "   Frequency:  ${BOLD}${freq_mhz} MHz${NC} / ${freq_max_mhz} MHz  (${governor})"
    fi

    # Overall CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    if [[ -n "$cpu_usage" ]]; then
        printf "   Usage:      $(colorize_percent ${cpu_usage})\n"
    fi
    echo ""
}

show_gpu_info() {
    echo -e "${BOLD}${BLUE}🎮 GPU STATUS (Intel UHD 620)${NC}"
    echo -e "   ────────────────────────────────────────────"

    # GPU frequency
    local gpu_cur=$(cat /sys/class/drm/card*/gt_cur_freq_mhz 2>/dev/null | head -1)
    local gpu_max=$(cat /sys/class/drm/card*/gt_max_freq_mhz 2>/dev/null | head -1)

    if [[ -n "$gpu_cur" ]]; then
        echo -e "   Frequency:  ${BOLD}${gpu_cur} MHz${NC} / ${gpu_max} MHz"
    fi

    # GPU render busy percentage (if available)
    local gpu_busy=$(cat /sys/class/drm/card*/gt_busy_time 2>/dev/null | head -1)
    if [[ -n "$gpu_busy" ]]; then
        echo -e "   Busy:       ${gpu_busy}"
    fi

    # Try to get RC6 (power saving) percentage
    local rc6=$(cat /sys/class/drm/card*/gt_rc6_residency_ms 2>/dev/null 2>&1 | head -1)
    if [[ -n "$rc6" && "$rc6" != "0" ]]; then
        echo -e "   RC6 idle:   ${rc6} ms"
    fi
    echo ""
}

show_top_cpu_consumers() {
    echo -e "${BOLD}${MAGENTA}📈 TOP ${TOP_N} CPU CONSUMERS${NC}"
    echo -e "   ────────────────────────────────────────────"

    ps -eo pid,%cpu,%mem,comm --sort=-%cpu | head -$((TOP_N + 1)) | tail -n $TOP_N | \
    awk -v red="$RED" -v yellow="$YELLOW" -v nc="$NC" '{
        pid=$1; cpu=$2; mem=$3; cmd=$4;
        if(length(cmd) > 25) cmd=substr(cmd, 1, 22)"...";
        color = "";
        if(cpu+0 >= 50) color = red;
        else if(cpu+0 >= 20) color = yellow;
        printf "   %s%5s  %5.1f%%  %5.1f%%  %-25s%s\n", color, pid, cpu, mem, cmd, nc
    }'

    echo -e "   ${DIM}(PID    CPU%   MEM%   COMMAND)${NC}"
    echo ""
}

show_top_mem_consumers() {
    echo -e "${BOLD}${MAGENTA}📊 TOP ${TOP_N} MEMORY CONSUMERS${NC}"
    echo -e "   ────────────────────────────────────────────"

    ps -eo pid,rss,%mem,comm --sort=-rss | head -$((TOP_N + 1)) | tail -n $TOP_N | \
    awk '{
        pid=$1; rss=$2; mem=$3; cmd=$4;
        # Convert RSS (KB) to human readable
        if(rss > 1048576) rss_h=sprintf("%.1fG", rss/1048576);
        else if(rss > 1024) rss_h=sprintf("%.0fM", rss/1024);
        else rss_h=sprintf("%dK", rss);
        if(length(cmd) > 25) cmd=substr(cmd, 1, 22)"...";
        printf "   %5s  %6s  %5.1f%%  %-25s\n", pid, rss_h, mem, cmd
    }'

    echo -e "   ${DIM}(PID    RSS     MEM%   COMMAND)${NC}"
    echo ""
}

show_gpu_consumers() {
    echo -e "${BOLD}${MAGENTA}🖥️  GPU CONSUMERS${NC}"
    echo -e "   ────────────────────────────────────────────"

    # Check for processes using GPU via DRI (with timeout)
    local gpu_procs=$(timeout 2 lsof /dev/dri/renderD128 2>/dev/null | awk 'NR>1 {print $2}' | sort -u | head -$TOP_N)

    if [[ -n "$gpu_procs" ]]; then
        for pid in $gpu_procs; do
            local info=$(ps -p $pid -o comm=,%cpu=,%mem= 2>/dev/null | tr -s ' ')
            if [[ -n "$info" ]]; then
                local cmd=$(echo "$info" | awk '{print $1}')
                local cpu=$(echo "$info" | awk '{print $2}')
                local mem=$(echo "$info" | awk '{print $3}')
                printf "   %-20s PID:%-6s CPU:%5s%% MEM:%5s%%\n" "$cmd" "$pid" "$cpu" "$mem"
            fi
        done
    else
        echo -e "   ${DIM}No GPU-active processes detected${NC}"
    fi

    # intel_gpu_top hint
    if command -v intel_gpu_top &>/dev/null; then
        echo -e "   ${DIM}Tip: Run 'sudo intel_gpu_top' for detailed GPU stats${NC}"
    fi
    echo ""
}

show_io_stats() {
    echo -e "${BOLD}${BLUE}💾 DISK I/O (top writers)${NC}"
    echo -e "   ────────────────────────────────────────────"

    # Use pidstat if available (faster), otherwise skip
    if command -v pidstat &>/dev/null; then
        pidstat -d 1 1 2>/dev/null | tail -n +4 | head -$TOP_N | \
            awk '{if($5 > 0) printf "   %-20s PID:%-6s Write: %.1f KB/s\n", $9, $4, $5}'
    else
        echo -e "   ${DIM}Install sysstat for I/O stats (pidstat)${NC}"
    fi
    echo ""
}

show_legend() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "Temps: ${GREEN}<${TEMP_WARN}°${NC} | ${YELLOW}${TEMP_WARN}-${TEMP_CRIT}°${NC} | ${RED}>${TEMP_CRIT}°${NC}  |  CPU: ${GREEN}<20%${NC} | ${YELLOW}20-50%${NC} | ${RED}>50%${NC}"
    echo ""
}

show_all() {
    $CLEAR && clear
    show_header
    show_system_overview
    show_fan_status
    show_temperatures
    show_cpu_info
    show_gpu_info
    show_top_cpu_consumers
    show_top_mem_consumers
    show_gpu_consumers
    show_legend
}

show_help() {
    echo "ThinkPad Hardware Diagnostics - Extended View"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -w, --watch      Continuous monitoring (updates every 3s, implies --clear)"
    echo "  -c, --clear      Clear screen before output"
    echo "      --no-clear   Don't clear screen (overrides --watch default)"
    echo "  -n, --num NUM    Show top N processes (default: 5)"
    echo "  -i, --io         Include disk I/O stats"
    echo "  -h, --help       Show this help"
    echo ""
    echo "Examples:"
    echo "  $0               Full diagnostic view"
    echo "  $0 -w            Watch mode"
    echo "  $0 -n 10         Show top 10 consumers"
    echo "  $0 -w -i         Watch mode with I/O stats"
    echo ""
    echo "Related tools:"
    echo "  intel_gpu_top    Detailed Intel GPU monitoring (needs sudo)"
    echo "  htop             Interactive process viewer"
    echo "  iotop            I/O monitoring (needs sudo)"
}

# Parse arguments
WATCH=false
CLEAR=false
NO_CLEAR=false
SHOW_IO=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--watch)
            WATCH=true
            shift
            ;;
        -c|--clear)
            CLEAR=true
            shift
            ;;
        --no-clear)
            NO_CLEAR=true
            shift
            ;;
        -n|--num)
            TOP_N="$2"
            shift 2
            ;;
        -i|--io)
            SHOW_IO=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Watch mode implies clear unless --no-clear
if $WATCH && ! $NO_CLEAR; then
    CLEAR=true
fi

# Main
if $WATCH; then
    while true; do
        show_all
        if $SHOW_IO; then
            show_io_stats
        fi
        echo -e "${CYAN}Refreshing every 3s. Press Ctrl+C to exit${NC}"
        sleep 3
    done
else
    show_all
    if $SHOW_IO; then
        show_io_stats
    fi
fi
