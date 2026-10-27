# CLAUDE.md

## Two repositories, one strict split

| | **This repository: s2-server** (generic, read by outsiders) | **server-fleet** (private fleet inventory) |
|---|---|---|
| Holds | **How** to build and run **any** S2: steps, settings, rules, pitfalls, the empty record template | Facts about **specific machines**: addresses, host names, serial numbers, GPU UUIDs, versions found, test results, production log |
| Never | Anything about a specific machine, customer or person | Generic how-to steps |

Rule of thumb for every line you write: *would it still be true for the next S2 we
build?* Yes: here. No (it names, numbers or describes one machine): the fleet
repository. A finding on one machine usually needs both: the fact there, and the
lesson here, written with placeholders.

**No customer data in either repository**: no customer names, contacts, addresses or
anything a customer told us.

## This is the generic S2 server repository

This repository describes how to build and set up **any** onprem.ai S2 server: parts,
assembly, BIOS, operating system, checks, operations. It is read by people outside the
team. It is **not** a log or inventory of specific machines.

**Never write anything about a specific machine into this repository.** That includes:

- IP addresses, host names (`ain-...`), MAC addresses, serial numbers
- passwords, password hints, account names of a particular machine's owner
- which machine is where, who has it, its current state or problems
- BIOS, firmware, driver or OS versions *as found on one machine*
- notes like "on the lab S2", "the reference machine", "this node", "machine 2"
- screenshots, logs or command output copied from one machine

Use placeholders in commands instead: `<host address>`, `<bmc address>`, `<gateway>`,
`<mac>`, `<host name>`.

Per-machine data goes in **the fleet repository**, a separate repository that holds one
record per machine. Never in this one. [machine-record.md](machine-record.md) is only
the empty template for those records: copy it to the fleet repository and fill it in
there. Never fill it in here, and never add a `machines/` folder to this repository.

While working on a real machine (debugging, installing, checking), keep its details in
the conversation. Bring back to this repository only what is true for **every** S2:
a step, a setting, a rule, a pitfall, written generically.

## Working on a machine together with a person

When a step needs both of you (the person types a password, you run and read the
commands), use one shared `tmux` session on the machine
([04](04-provisioning.md) Phase 1, "Admin tools") instead of copy and paste. The
person stays in control of every `sudo` and never shows a password; you type the
commands and read every line of output yourself, nothing is lost in copying.

- Ask the person to start it once: `tmux new -A -s work` (as `ops`). They type `sudo`
  and other passwords there; never ask for a password in the conversation.
- Before that, switch on scrolling with the mouse wheel and a long history, so the
  person can scroll back through the output:
  `printf 'set -g mouse on\nset -g history-limit 50000\n' > ~/.tmux.conf`
  (a running session takes it with `tmux source-file ~/.tmux.conf`). With the mouse on,
  text is selected with Shift held down.
- You run the commands: type them into the session yourself, so the person only types
  passwords. Over SSH as the same user (no terminal needed):

  ```sh
  # 1. look: join read-only for 3 seconds and record what the screen shows
  ssh <host> "TERM=xterm-256color timeout 3 script -qfc 'tmux attach -r -t work' /dev/null </dev/null" \
    | sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b[()][0-9A-Z]//g' | tail -c 2000
  # 2. type: only when step 1 shows a free shell prompt
  ssh <host> "tmux send-keys -t work '<command> 2>&1 | tee ~/<step>.log' Enter"
  # 3. look again (step 1): at a [sudo] password prompt, tell the person to type it
  ```

- Never `tmux capture-pane`: it crashes the tmux server shipped with Rocky Linux 10
  (tmux 3.3a git snapshot) and ends the person's session. `attach -r` is only the
  safe way to look; typing goes through `send-keys`.
- Always look right before typing: a prompt waiting for a password takes your command
  as the password (a failed `sudo` or a lock screen login attempt).
- When a `[sudo] password` prompt appears, tell the person at once: `sudo` gives up
  after 5 minutes ("timed out reading password") and the command must be typed again.
  Put all root steps of a phase in one script, so one password covers them.
- Long steps (upgrades, driver builds, memory tests) run in that session or with
  `tee` to a log file, so a dropped connection loses nothing.

## Checking a machine: no false alarms

- Verify with the repository's scripts (`scripts/host-checks.sh`), as root, in the
  shared session. Never improvise a check list, and never report a check run as
  another user: as `ops`, `dnf` reads `ops`'s own cache and asks to import repository
  keys root already has; `dmesg`, `sshd -T`, `firewall-cmd` and the Docker socket are
  refused. That once produced a false "repository key missing" alarm.
- What `ops` may read over SSH without `sudo` is for a quick look only (is a service
  active, a temperature, a log tail). It is not a check result.
- Before reporting a problem, confirm it the way the system itself sees it (as root,
  the service's own log, the state the failing component reads). Report it as a
  problem only then; until then it is "unconfirmed".
- A check that cannot be run (needs root, needs a cable, needs a person) is reported as
  "not run", never as passed or failed.
- When a check gives a wrong result, fix the check (the script and the runbook) in the
  same session, not only the conclusion.

## Writing scripts for the runbook

- A script written while working on one machine has hidden help there: packages,
  directories, images, modules left by earlier steps or by hand. Before it goes into
  `scripts/`, list every command's prerequisites and make the script install or create
  each one itself, or stop with `STOP: ... run <script> first`. A fan2go build script
  once failed on the second machine because `/etc/fan2go` had only been created by hand
  on the first.
- Run a new or changed script on a machine that has not run it before, before calling
  it done.

## Also keep out

- Internal projects and their names (other repositories, internal tools, internal
  decision records, earlier internal setups). Link only to public sources.
- One-off workarounds for a single machine's situation. If it is useful in general,
  write it as a generic step or as an incident note in `learnings/`.

## Learnings

`learnings/` holds incident notes that the manual cites as evidence. Write them
generically: date, hardware class, versions that matter, exact error messages, cause,
fix, how to check, public references. No machine names, addresses or internal
references. When the manual cites a heading or fact from a note, keep it there.

## Before committing

Search the changes for addresses and names, for example:

```sh
git diff --cached | grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}|([0-9a-f]{2}:){5}[0-9a-f]{2}|ain-[a-z0-9]{5}'
```

The only allowed hits are product facts (for example the IPMI card's factory fixed
address `10.10.10.10`) and the placeholder MACs `aa:bb:cc:dd:ee:..`.
