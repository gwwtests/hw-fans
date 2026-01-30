# Agent Guidelines

## Privacy & Anonymization

When creating documentation, README files, or example outputs that will be committed to the repository:

* **Never include real system data** - PIDs, process names, memory values, temperatures, uptime, load averages, etc. should be pseudo-randomized
* **Anonymize hardware parameters** - CPU frequencies, GPU stats, fan speeds should use plausible but not actual values
* **Use generic process names** - Replace actual running processes (e.g., `rust-analyzer`, `Telegram`, `claude`) with common generic ones (`firefox`, `code`, `spotify`, `nvim`)
* **Randomize identifiers** - PIDs, timestamps, IP addresses, hostnames should not reflect the real system
* **Avoid revealing system configuration** - Memory size, swap size, core count, uptime duration can fingerprint a system

### Why This Matters

Example outputs in documentation become part of the public git history. Real system data can:

* Fingerprint the developer's machine
* Reveal installed software and usage patterns
* Expose hardware specifications
* Leak timing information (uptime, timestamps)

### Checklist Before Committing Examples

- [ ] PIDs are randomized (not sequential from 1)
- [ ] Process names are generic/common applications
- [ ] Memory/CPU values are plausible but fictional
- [ ] Timestamps use a generic date (not current)
- [ ] Hardware specs don't match actual system
- [ ] No usernames or paths visible
