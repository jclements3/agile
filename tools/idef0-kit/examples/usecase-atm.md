# ATM Services — an IDEF0 plate carrying use-case-diagram semantics

One plate, same content as the classic SysML/UML ATM use case diagram,
plus the things a use case diagram cannot say: *what actually flows*
between actor and function, and how «include» really couples behavior.

Mapping: system boundary = plate boundary; use case = activity box;
primary-actor association = request input + value output + the actor
as mechanism; secondary actor (Bank Host) = mechanism; «include»
(Authenticate Customer) = a shared output consumed as a **control**
by every transaction; «extend» (card retention) = an exception output
gated by the security-policy control.

```idef0
tU ATM Services
## Equivalent of a SysML **use case diagram** for an ATM.\n Actors:
## Customer (primary), Bank Host (secondary), Service Technician.
## Every association line of the UML diagram appears here as a
## *typed flow*; every use case is decomposable into its scenario.
  a1 Authenticate Customer
  ## The UML "included" use case. Its output `Authenticated Session`
  ## steers every transaction box as a **control** -- the include
  ## relationship drawn as a real, checkable flow.
    i1 Card & PIN
    c1 Account Security Policy
    o1 Authenticated Session
    o2 Retained Card  ## The "extend" equivalent: exception outcome gated by the security policy.
    m1 Card Reader
    m2 Bank Host
  a2 Withdraw Cash
    i1 Withdrawal Request
    c1 Authenticated Session
    o1 Dispensed Cash
    o2 Transaction Record
    m1 Cash Dispenser
    m2 Customer
  a3 Deposit Funds
    i1 Deposit Items
    c1 Authenticated Session
    o1 Deposit Receipt
    o2 Transaction Record
    m1 Deposit Module
    m2 Customer
  a4 Check Balance
    i1 Balance Inquiry
    c1 Authenticated Session
    o1 Balance Statement
    m1 Bank Host
    m2 Customer
  a5 Maintain ATM
  ## The Service Technician's use case, outside the customer session
  ## entirely -- which the plate shows structurally: no
  ## `Authenticated Session` control enters this box.
    i1 Cash Cassettes & Supplies
    c1 Service Schedule
    o1 Service Report
    m1 Service Technician
```
