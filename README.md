# hw-fans

Small handy scripts I use for fan monitoring and hardware diagnostics on Linux. Sharing in case they're useful to others.

**If you need updates to support your setup, feel free to open a PR or GitHub issue!**

## Example Output

### check-fans.sh

```
═══════════════════════════════════════════
       ThinkPad Fan & Temp Monitor
═══════════════════════════════════════════

🌀 FAN STATUS
   ─────────────────────────────
   Status:  enabled
   Speed:   2847 RPM
   Level:   auto

🔥 CPU TEMPERATURES
   ─────────────────────────────
   Package id 0: 68°C
   Core 0:      65°C
   Core 1:      67°C
   Core 2:      63°C
   Core 3:      66°C

🌡️  OTHER TEMPERATURES
   ─────────────────────────────
   PCH:         52°C
   WiFi:        48°C
   NVMe:        41°C

Legend: < 75°C | 75-90°C | > 90°C
```

### hw-diag.py

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ ThinkPad Hardware Diagnostics 2026-01-15 14:32:18                            │
╰──────────────────────────────────────────────────────────────────────────────╯

╭───────────────────────────── 📊 SYSTEM OVERVIEW ─────────────────────────────╮
│   Uptime    3d 7h 22m                                                        │
│   Load      1.24 0.89 0.76 (8 cores)                                         │
│   Memory    12.4G/32.0G 38.8%                                                │
│   Swap      1.2G/16.0G                                                       │
╰──────────────────────────────────────────────────────────────────────────────╯
╭─────────────────────────────── 🌀 FAN STATUS ────────────────────────────────╮
│   Status    enabled                                                          │
│   Level     auto                                                             │
│   Speed     2847 RPM ██████████░░░░░░░░░░                                    │
╰──────────────────────────────────────────────────────────────────────────────╯
╭────────────────────────────── 🔥 TEMPERATURES ───────────────────────────────╮
│   Package id 0      68°C          high: 100°                                 │
│   Core 0            65°C          high: 100°                                 │
│   Core 1            67°C          high: 100°                                 │
│   Core 2            63°C          high: 100°                                 │
│   Core 3            66°C          high: 100°                                 │
│   pch_cannonlake    52°C                                                     │
│   iwlwifi_1         48°C                                                     │
│   Composite         41°C                                                     │
│   CPU               64°C                                                     │
╰──────────────────────────────────────────────────────────────────────────────╯
╭───────────────────────────── ⚡ CPU/GPU STATUS ──────────────────────────────╮
│   CPU             2100/4000 MHz (powersave) 12.3%                            │
│   Intel GPU       350/1100 MHz                                               │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────── 📈 TOP CPU CONSUMERS ────────────────────────────╮
│  PID      CPU%     MEM%     Process                                          │
│  12847    8.2%     1.4%     firefox                                          │
│  15234    3.1%     0.8%     code                                             │
│  8921     2.4%     0.3%     htop                                             │
│  1        0.1%     0.0%     systemd                                          │
│  892      0.0%     0.1%     dbus-daemon                                      │
╰──────────────────────────────────────────────────────────────────────────────╯
╭────────────────────────── 📊 TOP MEMORY CONSUMERS ───────────────────────────╮
│  PID      RSS       MEM%     Process                                         │
│  12847    1.8G      5.6%     firefox                                         │
│  15234    924.1M    2.8%     code                                            │
│  18472    512.4M    1.6%     spotify                                         │
│  9124     384.2M    1.2%     alacritty                                       │
│  7821     256.8M    0.8%     nvim                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
╭────────────────────────────── 🖥️ GPU CONSUMERS ──────────────────────────────╮
│  PID      Process               CPU%     MEM%                                │
│  12847    firefox               8.2%     5.6%                                │
│  15234    code                  3.1%     2.8%                                │
│  18472    spotify               0.4%     1.6%                                │
╰────────────────────────── Tip: sudo intel_gpu_top ───────────────────────────╯
Temps: <75° 75-90° >90°  | CPU: <20% 20-50% >50%
```

## Scripts

| Script | Description | Language |
|--------|-------------|----------|
| `check-fans.sh` | Quick fan & temperature monitor | Bash |
| `hw-diag.sh` | Extended hardware diagnostics | Bash |
| `hw-diag.py` | Full diagnostics with rich UI | Python (uv) |

## Requirements

* Linux with `lm-sensors` installed
* Python 3.10+ and [uv](https://github.com/astral-sh/uv) for `hw-diag.py`

## Usage

```bash
# Quick fan check
./check-fans.sh

# Simple one-liner (for status bars, tmux, etc.)
./check-fans.sh -s

# Watch mode (auto-refresh every 2s)
./check-fans.sh -w

# Extended diagnostics
./hw-diag.sh

# Python version with rich UI
./hw-diag.py

# Show top 10 processes
./hw-diag.py -n 10
```

### Options

```
-w, --watch     Continuous monitoring (implies --clear)
-c, --clear     Clear screen before output
    --no-clear  Don't clear screen (overrides --watch default)
-s, --simple    One-line simple output
-n, --num NUM   Show top N processes (default: 5)
-h, --help      Show help
```

## Manual Fan Control

```bash
# Force full speed
echo level full-speed | sudo tee /proc/acpi/ibm/fan

# Return to auto
echo level auto | sudo tee /proc/acpi/ibm/fan
```

## Compatibility

These scripts were developed on a ThinkPad and use ThinkPad-specific paths for some features:

* **Fan control**: `/proc/acpi/ibm/fan` (requires `thinkpad_acpi` kernel module)
* **Fan status/level**: ThinkPad ACPI interface

However, most functionality should work on other Linux systems:

* **Temperature readings**: Uses `lm-sensors` which works on most hardware
* **CPU/GPU frequencies**: Reads from standard `/sys/` paths
* **Process monitoring**: Uses `psutil` (Python) or `ps` (Bash) - universal

**The scripts gracefully fall back** when ThinkPad-specific interfaces aren't available - you'll still get temperatures and process info, just without fan control.

If you're on a different system and want to add support for your hardware's fan interface, PRs are welcome!

## License

MIT
