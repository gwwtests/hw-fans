#!/bin/bash
# ThinkPad Fan & Temperature Monitor
# Usage: ./check-fans.sh [-w|--watch] [-c|--clear] [-s|--simple] [-h|--help]

set -euo pipefail

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Temperature thresholds
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

show_header() {
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}       ThinkPad Fan & Temp Monitor${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
    echo ""
}

show_fan_status() {
    echo -e "${BOLD}${BLUE}🌀 FAN STATUS${NC}"
    echo -e "   ─────────────────────────────"

    if [[ -r /proc/acpi/ibm/fan ]]; then
        local status=$(grep "status:" /proc/acpi/ibm/fan | awk '{print $2}')
        local speed=$(grep "speed:" /proc/acpi/ibm/fan | awk '{print $2}')
        local level=$(grep "level:" /proc/acpi/ibm/fan | awk '{print $2}')

        echo -e "   Status:  ${GREEN}${status}${NC}"
        echo -e "   Speed:   ${BOLD}${speed} RPM${NC}"
        echo -e "   Level:   ${level}"
    else
        # Fallback to sensors
        local rpm=$(sensors 2>/dev/null | grep -i "fan1:" | awk '{print $2}')
        if [[ -n "$rpm" ]]; then
            echo -e "   Speed:   ${BOLD}${rpm} RPM${NC}"
        else
            echo -e "   ${YELLOW}No fan data available${NC}"
        fi
    fi
    echo ""
}

show_cpu_temps() {
    echo -e "${BOLD}${BLUE}🔥 CPU TEMPERATURES${NC}"
    echo -e "   ─────────────────────────────"

    if command -v sensors &>/dev/null; then
        # Get coretemp readings
        while IFS= read -r line; do
            if [[ "$line" =~ ^(Package|Core) ]]; then
                local name=$(echo "$line" | cut -d: -f1 | xargs)
                local temp=$(echo "$line" | grep -oP '\+\K[0-9]+' | head -1)
                if [[ -n "$temp" ]]; then
                    printf "   %-12s $(colorize_temp $temp)\n" "$name:"
                fi
            fi
        done < <(sensors coretemp-isa-0000 2>/dev/null)
    else
        echo -e "   ${YELLOW}Install lm_sensors for detailed readings${NC}"
    fi
    echo ""
}

show_other_temps() {
    echo -e "${BOLD}${BLUE}🌡️  OTHER TEMPERATURES${NC}"
    echo -e "   ─────────────────────────────"

    if command -v sensors &>/dev/null; then
        # PCH
        local pch=$(sensors pch_cannonlake-virtual-0 2>/dev/null | grep "temp1:" | grep -oP '\+\K[0-9]+' | head -1)
        if [[ -n "$pch" ]]; then
            printf "   %-12s $(colorize_temp $pch)\n" "PCH:"
        fi

        # WiFi
        local wifi=$(sensors iwlwifi_1-virtual-0 2>/dev/null | grep "temp1:" | grep -oP '\+\K[0-9]+' | head -1)
        if [[ -n "$wifi" ]]; then
            printf "   %-12s $(colorize_temp $wifi)\n" "WiFi:"
        fi

        # NVMe
        local nvme=$(sensors nvme-pci-3d00 2>/dev/null | grep "Composite:" | grep -oP '\+\K[0-9]+' | head -1)
        if [[ -n "$nvme" ]]; then
            printf "   %-12s $(colorize_temp $nvme)\n" "NVMe:"
        fi
    fi
    echo ""
}

show_simple() {
    local speed="?"
    local cpu_temp="?"

    if [[ -r /proc/acpi/ibm/fan ]]; then
        speed=$(grep "speed:" /proc/acpi/ibm/fan | awk '{print $2}')
    fi

    if command -v sensors &>/dev/null; then
        cpu_temp=$(sensors coretemp-isa-0000 2>/dev/null | grep "Package" | grep -oP '\+\K[0-9]+' | head -1)
    fi

    echo "Fan: ${speed} RPM | CPU: ${cpu_temp}°C"
}

show_all() {
    $CLEAR && clear
    show_header
    show_fan_status
    show_cpu_temps
    show_other_temps
    echo -e "${CYAN}Legend: ${GREEN}< ${TEMP_WARN}°C${NC} | ${YELLOW}${TEMP_WARN}-${TEMP_CRIT}°C${NC} | ${RED}> ${TEMP_CRIT}°C${NC}"
    echo ""
}

show_help() {
    echo "ThinkPad Fan & Temperature Monitor"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -w, --watch     Continuous monitoring (updates every 2s, implies --clear)"
    echo "  -c, --clear     Clear screen before output"
    echo "      --no-clear  Don't clear screen (overrides --watch default)"
    echo "  -s, --simple    One-line simple output"
    echo "  -h, --help      Show this help"
    echo ""
    echo "Examples:"
    echo "  $0              Show current status"
    echo "  $0 -w           Watch mode with auto-refresh"
    echo "  $0 -s           Simple output for scripting"
}

# Parse arguments
WATCH=false
SIMPLE=false
CLEAR=false
NO_CLEAR=false

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
        -s|--simple)
            SIMPLE=true
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
if $SIMPLE; then
    if $WATCH; then
        while true; do
            show_simple
            sleep 2
        done
    else
        show_simple
    fi
elif $WATCH; then
    while true; do
        show_all
        echo -e "${CYAN}Press Ctrl+C to exit${NC}"
        sleep 2
    done
else
    show_all
fi
