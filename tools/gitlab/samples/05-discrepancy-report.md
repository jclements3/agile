## Discrepancy

| | |
|---|---|
| DR number | DR-3 |
| Prime tracking | NMS-SM-0147 |
| Found in drop | v1.0, delivered 2026-10-02 |
| v1 element | `Requirements::System Requirements::Functions::Bulletin` (xmi:id `_22_1_7f3a0c1_…`) |
| DOORS id | TW-SYS-006 |
| Severity | 2 — wrong with a workaround |

## What we found

The text of TW-SYS-006 differs between the two sources the prime delivered:

| Source | Text |
|---|---|
| DOORS (`tidewater.reqif`) | The data center shall publish a marine bulletin **twice a day**, on a fixed schedule. |
| Cameo model (`tidewater.xmi`) | The data center shall publish a marine bulletin on a fixed schedule. |

The trace job on !24 reported it:

```text
text differs from DOORS                            1
drift: TW-SYS-006
```

## What we ask the prime to do

Synchronize the Cameo requirement with DOORS (DOORS is the requirements authority) and deliver it in the next drop.

## Closure

- [x] Sent to the prime on 2026-11-20 by @jim
- [ ] Fixed in drop v1.1, confirmed by the intake issue #<!-- next drop -->

Workaround until then: the government model cites the DOORS text (`model/doors/`), which is authoritative.
