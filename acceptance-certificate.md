# Acceptance certificate: template

> **Empty template.** Copy it to the fleet repository next to the machine's record
> (`machines/<host address>-<host name>-certificate.md`), fill it in there from the
> record's **Acceptance** table, and hand it to the customer with the machine. Never
> fill it in here.

Issue it only when **every** check below passed. A check that failed is repeated
after the fix; the certificate shows the passing run. A check that does not apply
(for example network failover on a one-port machine) is marked "not applicable", never
left out silently.

Keep it to what the customer needs: no internal addresses, passwords, account names,
internal notes or problems found and fixed on the way. Those stay in the fleet record.

---

# onprem.ai S2: acceptance certificate

| | |
|---|---|
| Host name | `ain-_____` |
| Serial numbers | Board ___ ; GPU 0 ___ ; GPU 1 ___ ; NVMe ___ / ___ |
| Configuration | 2x RTX PRO 6000 Blackwell Server Edition, AMD Ryzen 9 9900X, ___ GB RAM, ___ TB NVMe (RAID 1) |
| Software at handoff | Rocky Linux / Ubuntu ___ , kernel ___ , NVIDIA driver ___ , BIOS ___ , BMC firmware ___ |
| Built and tested to | onprem.ai S2 build manual, revision ___ |

| Check | What was verified | Performed by | Date | Result |
|---|---|---|---|---|
| Memory | One full `memtester` / MemTest86 pass, no errors | | | Passed |
| GPU thermal | Both GPUs at full load (500 W each) for 10 minutes: below 80 C, no thermal slowdown, fans ramp up and down | | | Passed, max ___ C |
| GPU stability | Both GPUs at full load for 1 hour: no GPU errors, both GPUs present after | | | Passed |
| Disks | Health of both NVMe disks, mirror fully synced, write and read test | | | Passed |
| Power loss | Power restored after a cut: the machine starts by itself with both GPUs | | | Passed |
| Remote management | Power cycle and console through the BMC | | | Passed |
| Network failover | Each network cable pulled in turn: connection kept | | | Passed |
| Host configuration | Driver, kernel settings, security updates, firewall, SSH (root login off) as specified | | | Passed |
| Containers | GPUs available to containers; platform node connected and verified | | | Passed |

Approved for delivery:

| Name | Role | Date | Signature |
|---|---|---|---|
| | | | |
