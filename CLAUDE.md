# CLAUDE.md

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
([04](04-provisioning.md) Phase 1, "Admin tools") instead of copy and paste:

- Ask the person to start it once: `tmux new -A -s work` (as `ops`). They type `sudo`
  and other passwords there; never ask for a password in the conversation.
- Read the result yourself over SSH: `tmux capture-pane -p -t work -S -200`.
- Type into it only when agreed, and look at the pane right before typing: a prompt
  waiting for a password takes your command as the password.
- Long steps (upgrades, driver builds, memory tests) run in that session or with
  `tee` to a log file, so a dropped connection loses nothing.

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
