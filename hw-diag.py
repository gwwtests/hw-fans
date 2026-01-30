#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "rich>=13.0",
#     "psutil>=5.9",
# ]
# ///
"""ThinkPad Hardware Diagnostics - Extended View

Shows fans, temps, CPU/GPU status, and top resource consumers.
"""

import argparse
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

import psutil
from rich.console import Console
from rich.panel import Panel
from rich.progress import BarColumn, Progress, TextColumn
from rich.table import Table
from rich.text import Text

console = Console()

# Temperature thresholds
TEMP_WARN = 75
TEMP_CRIT = 90


@dataclass
class FanInfo:
    status: str = "unknown"
    speed: int = 0
    level: str = "unknown"


@dataclass
class TempReading:
    name: str
    current: float
    high: float | None = None
    critical: float | None = None


def colorize_temp(temp: float) -> Text:
    """Return colored temperature text."""
    text = f"{temp:.0f}°C"
    if temp >= TEMP_CRIT:
        return Text(text, style="bold red")
    elif temp >= TEMP_WARN:
        return Text(text, style="bold yellow")
    return Text(text, style="bold green")


def colorize_percent(pct: float, warn: float = 20, crit: float = 50) -> Text:
    """Return colored percentage text."""
    text = f"{pct:.1f}%"
    if pct >= crit:
        return Text(text, style="bold red")
    elif pct >= warn:
        return Text(text, style="bold yellow")
    return Text(text, style="green")


def get_fan_info() -> FanInfo:
    """Read ThinkPad fan status from ACPI."""
    fan_path = Path("/proc/acpi/ibm/fan")
    info = FanInfo()

    if fan_path.exists():
        try:
            content = fan_path.read_text()
            for line in content.splitlines():
                if line.startswith("status:"):
                    info.status = line.split()[1]
                elif line.startswith("speed:"):
                    info.speed = int(line.split()[1])
                elif line.startswith("level:"):
                    info.level = line.split()[1]
        except (PermissionError, ValueError):
            pass

    return info


def get_temperatures() -> dict[str, list[TempReading]]:
    """Get all temperature readings using psutil."""
    temps: dict[str, list[TempReading]] = {}

    try:
        sensor_temps = psutil.sensors_temperatures()
        for name, readings in sensor_temps.items():
            temps[name] = [
                TempReading(
                    name=r.label or name,
                    current=r.current,
                    high=r.high,
                    critical=r.critical
                )
                for r in readings
            ]
    except AttributeError:
        pass  # sensors_temperatures not available on all platforms

    return temps


def get_gpu_freq() -> tuple[int, int]:
    """Get Intel GPU current and max frequency."""
    cur_freq = 0
    max_freq = 0

    drm_path = Path("/sys/class/drm")
    for card in drm_path.glob("card*"):
        cur_file = card / "gt_cur_freq_mhz"
        max_file = card / "gt_max_freq_mhz"

        if cur_file.exists():
            try:
                cur_freq = int(cur_file.read_text().strip())
                max_freq = int(max_file.read_text().strip()) if max_file.exists() else 0
                break
            except (ValueError, PermissionError):
                pass

    return cur_freq, max_freq


def get_cpu_freq() -> tuple[float, float, str]:
    """Get CPU current freq, max freq, and governor."""
    freq = psutil.cpu_freq()
    cur_mhz = freq.current if freq else 0
    max_mhz = freq.max if freq else 0

    # Get governor
    governor = "unknown"
    gov_path = Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
    if gov_path.exists():
        try:
            governor = gov_path.read_text().strip()
        except PermissionError:
            pass

    return cur_mhz, max_mhz, governor


def get_gpu_consumers(top_n: int = 5) -> list[tuple[int, str, float, float]]:
    """Get processes using the GPU via DRI."""
    gpu_procs = []

    try:
        result = subprocess.run(
            ["lsof", "/dev/dri/renderD128"],
            capture_output=True, text=True, timeout=2
        )
        pids = set()
        for line in result.stdout.splitlines()[1:]:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    pids.add(int(parts[1]))
                except ValueError:
                    pass

        for pid in list(pids)[:top_n]:
            try:
                proc = psutil.Process(pid)
                gpu_procs.append((
                    pid,
                    proc.name(),
                    proc.cpu_percent(),
                    proc.memory_percent()
                ))
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return gpu_procs


def human_bytes(b: int) -> str:
    """Convert bytes to human readable format."""
    for unit in ["B", "K", "M", "G", "T"]:
        if b < 1024:
            return f"{b:.1f}{unit}"
        b /= 1024
    return f"{b:.1f}P"


def show_system_overview():
    """Display system overview panel."""
    table = Table(show_header=False, box=None, padding=(0, 2))
    table.add_column("Label", style="dim")
    table.add_column("Value")

    # Uptime
    boot_time = psutil.boot_time()
    uptime_secs = time.time() - boot_time
    days = int(uptime_secs // 86400)
    hours = int((uptime_secs % 86400) // 3600)
    mins = int((uptime_secs % 3600) // 60)
    uptime_str = f"{days}d {hours}h {mins}m" if days else f"{hours}h {mins}m"
    table.add_row("Uptime", uptime_str)

    # Load
    load1, load5, load15 = psutil.getloadavg()
    cores = psutil.cpu_count()
    table.add_row("Load", f"{load1:.2f} {load5:.2f} {load15:.2f} ({cores} cores)")

    # Memory
    mem = psutil.virtual_memory()
    mem_text = Text()
    mem_text.append(f"{human_bytes(mem.used)}/{human_bytes(mem.total)} ")
    mem_text.append_text(colorize_percent(mem.percent, warn=70, crit=90))
    table.add_row("Memory", mem_text)

    # Swap
    swap = psutil.swap_memory()
    if swap.total > 0:
        table.add_row("Swap", f"{human_bytes(swap.used)}/{human_bytes(swap.total)}")

    console.print(Panel(table, title="[bold blue]📊 SYSTEM OVERVIEW[/]", border_style="blue"))


def show_fan_status():
    """Display fan status panel."""
    fan = get_fan_info()

    table = Table(show_header=False, box=None, padding=(0, 2))
    table.add_column("Label", style="dim")
    table.add_column("Value")

    status_style = "green" if fan.status == "enabled" else "yellow"
    table.add_row("Status", Text(fan.status, style=status_style))
    table.add_row("Level", fan.level)

    # Speed with visual bar
    max_rpm = 5500
    pct = min(fan.speed / max_rpm * 100, 100)
    speed_text = Text()
    speed_text.append(f"{fan.speed} RPM ", style="bold")

    bar_width = 20
    filled = int(pct / 100 * bar_width)
    speed_text.append("█" * filled, style="cyan")
    speed_text.append("░" * (bar_width - filled), style="dim")

    table.add_row("Speed", speed_text)

    console.print(Panel(table, title="[bold blue]🌀 FAN STATUS[/]", border_style="blue"))


def show_temperatures():
    """Display temperature readings."""
    temps = get_temperatures()

    table = Table(show_header=False, box=None, padding=(0, 2))
    table.add_column("Sensor", style="dim", width=14)
    table.add_column("Temp", width=10)
    table.add_column("Details", style="dim")

    # CPU temps (coretemp)
    if "coretemp" in temps:
        for reading in temps["coretemp"]:
            details = ""
            if reading.high:
                details = f"high: {reading.high:.0f}°"
            table.add_row(reading.name, colorize_temp(reading.current), details)

    # Other sensors
    other_sensors = ["pch_cannonlake", "iwlwifi_1", "nvme", "thinkpad"]
    for sensor in other_sensors:
        for name, readings in temps.items():
            if sensor in name.lower():
                for r in readings[:1]:  # Just first reading
                    label = r.name if r.name else sensor.split("_")[0].upper()
                    table.add_row(label, colorize_temp(r.current), "")

    console.print(Panel(table, title="[bold blue]🔥 TEMPERATURES[/]", border_style="blue"))


def show_cpu_gpu_status():
    """Display CPU and GPU frequency/usage."""
    table = Table(show_header=False, box=None, padding=(0, 2))
    table.add_column("", style="dim", width=12)
    table.add_column("", width=50)

    # CPU
    cur_freq, max_freq, governor = get_cpu_freq()
    cpu_pct = psutil.cpu_percent(interval=0.1)

    cpu_text = Text()
    cpu_text.append(f"{cur_freq:.0f}/{max_freq:.0f} MHz ", style="bold")
    cpu_text.append(f"({governor}) ", style="dim")
    cpu_text.append_text(colorize_percent(cpu_pct))
    table.add_row("CPU", cpu_text)

    # GPU
    gpu_cur, gpu_max = get_gpu_freq()
    if gpu_cur > 0:
        gpu_text = Text()
        gpu_text.append(f"{gpu_cur}/{gpu_max} MHz", style="bold")
        table.add_row("Intel GPU", gpu_text)

    console.print(Panel(table, title="[bold blue]⚡ CPU/GPU STATUS[/]", border_style="blue"))


def show_top_processes(top_n: int = 5):
    """Display top CPU and memory consumers."""
    # Get process list
    procs = []
    for p in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent', 'memory_info']):
        try:
            info = p.info
            procs.append(info)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    # CPU consumers
    cpu_table = Table(box=None, padding=(0, 1))
    cpu_table.add_column("PID", style="dim", width=7)
    cpu_table.add_column("CPU%", width=7)
    cpu_table.add_column("MEM%", width=7)
    cpu_table.add_column("Process", width=25)

    cpu_sorted = sorted(procs, key=lambda x: x['cpu_percent'] or 0, reverse=True)[:top_n]
    for p in cpu_sorted:
        name = (p['name'] or "")[:25]
        cpu_table.add_row(
            str(p['pid']),
            colorize_percent(p['cpu_percent'] or 0),
            f"{p['memory_percent']:.1f}%",
            name
        )

    console.print(Panel(cpu_table, title="[bold magenta]📈 TOP CPU CONSUMERS[/]", border_style="magenta"))

    # Memory consumers
    mem_table = Table(box=None, padding=(0, 1))
    mem_table.add_column("PID", style="dim", width=7)
    mem_table.add_column("RSS", width=8)
    mem_table.add_column("MEM%", width=7)
    mem_table.add_column("Process", width=25)

    mem_sorted = sorted(procs, key=lambda x: (x.get('memory_info') or type('', (), {'rss': 0})).rss, reverse=True)[:top_n]
    for p in mem_sorted:
        name = (p['name'] or "")[:25]
        rss = (p.get('memory_info') or type('', (), {'rss': 0})).rss
        mem_table.add_row(
            str(p['pid']),
            human_bytes(rss),
            f"{p['memory_percent']:.1f}%",
            name
        )

    console.print(Panel(mem_table, title="[bold magenta]📊 TOP MEMORY CONSUMERS[/]", border_style="magenta"))


def show_gpu_consumers(top_n: int = 5):
    """Display processes using the GPU."""
    gpu_procs = get_gpu_consumers(top_n)

    table = Table(box=None, padding=(0, 1))
    table.add_column("PID", style="dim", width=7)
    table.add_column("Process", width=20)
    table.add_column("CPU%", width=7)
    table.add_column("MEM%", width=7)

    if gpu_procs:
        for pid, name, cpu, mem in gpu_procs:
            table.add_row(str(pid), name[:20], f"{cpu:.1f}%", f"{mem:.1f}%")
    else:
        table.add_row("", "[dim]No GPU-active processes[/]", "", "")

    # Add tip
    console.print(Panel(table, title="[bold magenta]🖥️ GPU CONSUMERS[/]", border_style="magenta",
                       subtitle="[dim]Tip: sudo intel_gpu_top[/]"))


def show_legend():
    """Display color legend."""
    legend = Text()
    legend.append("Temps: ", style="dim")
    legend.append(f"<{TEMP_WARN}° ", style="green")
    legend.append(f"{TEMP_WARN}-{TEMP_CRIT}° ", style="yellow")
    legend.append(f">{TEMP_CRIT}° ", style="red")
    legend.append(" | ", style="dim")
    legend.append("CPU: ", style="dim")
    legend.append("<20% ", style="green")
    legend.append("20-50% ", style="yellow")
    legend.append(">50%", style="red")

    console.print(legend)


def show_all(top_n: int = 5, clear: bool = False):
    """Display all diagnostics."""
    if clear:
        console.clear()

    from datetime import datetime
    title = f"[bold cyan]ThinkPad Hardware Diagnostics[/] [dim]{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}[/]"
    console.print(Panel(title, style="cyan"))
    console.print()

    show_system_overview()
    show_fan_status()
    show_temperatures()
    show_cpu_gpu_status()
    show_top_processes(top_n)
    show_gpu_consumers(top_n)
    show_legend()


def main():
    parser = argparse.ArgumentParser(description="ThinkPad Hardware Diagnostics")
    parser.add_argument("-w", "--watch", action="store_true", help="Continuous monitoring (updates every 3s, implies --clear)")
    parser.add_argument("-c", "--clear", action="store_true", help="Clear screen before output")
    parser.add_argument("--no-clear", action="store_true", help="Don't clear screen (overrides --watch default)")
    parser.add_argument("-n", "--num", type=int, default=5, help="Show top N processes (default: 5)")
    parser.add_argument("-s", "--simple", action="store_true", help="Simple one-line output")
    args = parser.parse_args()

    # Watch mode implies clear unless --no-clear
    do_clear = args.clear or (args.watch and not args.no_clear)

    if args.simple:
        fan = get_fan_info()
        temps = get_temperatures()
        cpu_temp = 0
        if "coretemp" in temps:
            for r in temps["coretemp"]:
                if "Package" in r.name:
                    cpu_temp = r.current
                    break
        print(f"Fan: {fan.speed} RPM | CPU: {cpu_temp:.0f}°C | Load: {psutil.getloadavg()[0]:.2f}")
        return

    if args.watch:
        try:
            while True:
                show_all(args.num, clear=do_clear)
                console.print("\n[cyan]Refreshing every 3s. Press Ctrl+C to exit[/]")
                time.sleep(3)
        except KeyboardInterrupt:
            console.print("\n[dim]Exiting...[/]")
    else:
        show_all(args.num, clear=do_clear)


if __name__ == "__main__":
    main()
