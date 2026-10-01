# Architecture

## What is Warden?

Modbus is a very simple industrial protocol. It lets software read and write values in a controller, but the protocol itself has no authentication and almost no notion of permissions.

If a computer can reach the controller, it can usually ask the controller to do things.

In this project, we cannot change the controller. Instead, we put **Warden** in front of it.

Warden is a proxy:

1. It receives the Modbus request.
2. It checks that the request is valid.
3. It checks that the request is allowed.
4. Only then does it send the request to the controller.

So Warden has two jobs:

- block malformed or dangerous traffic;
- let legitimate operator traffic work normally.

That second point matters. A security system that stops attacks but also stops the operator is still broken.

---

## The system

```text
      laptop
 +------------------+        +-----------+        +--------------------+
 | workstation.py   | -----> |           |        | plant.py           |
 |   the operator   |        |  warden   | -----> |   controller       |
 +------------------+  5021  |   Ada     |  5020  |   tank, pump, valve|
 | attack.py        | -----> |           |        +--------------------+
 |   the attacker   |        +-----------+
 +------------------+
```

For the project, everything runs on the same machine using `127.0.0.1`.

- Warden listens on port `5021`.
- The simulated controller listens on port `5020`.

The normal path is therefore:

```text
client -> Warden -> controller
```

In a real plant, the network firewall would prevent clients from connecting directly to the controller.

In this project, we simulate that rule. The gauntlet's `--direct` option deliberately bypasses Warden so you can see why the proxy is needed.

---

## The main design idea

The code is divided into two parts:

```text
src/net                         src/core
outside world                   decisions

+------------------------+      +-----------------------------+
| Warden_Main            |      | Warden.Modbus               |
| main program loop      |      | decode Modbus bytes         |
|                        |      |                             |
| Warden.Wire            | ---> | Warden.Policy               |
| TCP connections        |      | is this operation allowed?  |
|                        |      |                             |
| Warden.Journal         |      | Warden.Gate                 |
| messages for humans    | <--- | accept or refuse request    |
|                        |      |                             |
| Warden.Settings        |      +-----------------------------+
| command-line settings  |
+------------------------+
```

The important rule is:

> **Network code moves bytes. Core code decides what those bytes mean and whether they are allowed.**

This separation is important for SPARK.

Code that talks to sockets and the operating system is difficult to prove completely.

Code that takes ordinary Ada values as input and returns ordinary Ada values is much easier for SPARK to reason about.

For example:

```ada
Gate.Inspect
```

does not need to know anything about TCP.

It receives bytes and answers:

```text
Is this request acceptable?
```

That keeps the security decision small and understandable.

---

## Where the code is

| Package | File | What it does | SPARK |
|---|---|---|---|
| `Warden` | `src/core/warden.ads` | Common basic types such as bytes, 16-bit values and byte arrays | yes |
| `Warden.Modbus` | `src/core/warden-modbus.ad[sb]` | Turns raw Modbus bytes into typed Ada values | yes, proved |
| `Warden.Policy` | `src/core/warden-policy.ad[sb]` | Decides whether an operation is permitted | yes, proved |
| `Warden.Gate` | `src/core/warden-gate.ad[sb]` | Inspects a request and accepts or refuses it | yes, proved |
| `Warden_Main` | `src/net/warden_main.adb` | Main program loop | yes, proved |
| `Warden.Wire` | `src/net/warden-wire.ad[sb]` | TCP communication with client and controller | specification only |
| `Warden.Journal` | `src/net/warden-journal.ad[sb]` | Prints what Warden is doing | specification only |
| `Warden.Settings` | `src/net/warden-settings.ad[sb]` | Reads ports and options from the command line | no |

### What does "specification only" mean?

An Ada package normally has two parts:

```text
.ads    specification
.adb    body
```

The specification describes what the package provides.

The body contains the implementation.

For `Warden.Wire` and `Warden.Journal`, the `.ads` specification is checked using SPARK contracts, but the `.adb` implementation is outside SPARK because it interacts with the operating system.

That code is therefore part of the **trusted code**.

SPARK does not prove that code correct.

Because of that, those bodies should stay small and simple enough that a human can review them directly.

---

## The most important type: `Approved`

This is the central security idea in the project.

```ada
--  Warden.Gate

type Approved is private;

procedure Inspect
  (Input   : Byte_Array;
   Result  : out Verdict;
   Request : out Approved)
with
  Post => Is_Valid (Request) = (Result = Accepted);
```

And later:

```ada
--  Warden.Wire

procedure Forward
  (Request   : Gate.Approved;
   Delivered : out Boolean)
with
  Pre => Gate.Is_Valid (Request);
```

At first this may look complicated. The idea is actually simple.

`Forward` is the function that sends something to the controller.

But `Forward` does **not** accept an arbitrary array of bytes.

It accepts:

```ada
Gate.Approved
```

That means the rest of the program cannot simply do this:

```text
receive bytes
send bytes
```

It must instead do:

```text
receive bytes
     |
     v
Gate.Inspect
     |
     v
Approved
     |
     v
Wire.Forward
```

### Why is `Approved` private?

The declaration says:

```ada
type Approved is private;
```

Code outside `Warden.Gate` cannot see how an `Approved` value is built internally.

That means other packages cannot casually create or modify one.

The gate controls the type.

So instead of relying only on programmers remembering:

> "Do not forward requests before checking them."

we make the program structure enforce it.

The type itself represents:

> "This request has gone through the gate."

---

## Where SPARK comes in

Look again at this contract:

```ada
Post => Is_Valid (Request) = (Result = Accepted);
```

A `Post` condition describes what must be true **after** a procedure finishes.

Here it says:

```text
Request is valid
exactly when
Result is Accepted
```

Now look at `Forward`:

```ada
Pre => Gate.Is_Valid (Request);
```

A `Pre` condition describes what must already be true **before** a procedure is called.

So before sending anything to the controller, SPARK wants proof that:

```text
Gate.Is_Valid (Request)
```

is true.

Together, the two contracts connect the operations:

```text
Inspect says Accepted
        |
        v
Approved request is valid
        |
        v
Forward may be called
```

That is one of the main ideas you should understand in this project.

We are using:

- Ada types;
- package visibility;
- preconditions;
- postconditions;

to make unsafe program states harder or impossible to express.

---

## Warden does not forward the original buffer

There is another important detail.

`Forward` does not receive the original client's byte array.

It receives an `Approved` request and sends:

```ada
Gate.Bytes (Request)
```

Those are the bytes stored inside the approved object.

Right now Warden mostly stores a copy of the request.

Later, the gate could do something stronger:

```text
raw bytes
   |
   v
decode fields
   |
   v
check fields
   |
   v
rebuild clean Modbus request
   |
   v
send rebuilt request
```

That gives us an important security property:

> Only information that Warden understood and checked needs to reach the controller.

Unknown or unchecked bytes cannot simply ride along with the request.

---

## What does `Accepted` mean today?

Not very much yet.

The starting code checks only a few basic things, such as:

- the request is not too short;
- the request is not too long;
- the Modbus protocol ID is `0`.

So today:

```text
Accepted
```

roughly means:

```text
"This looks somewhat like a Modbus request."
```

The project is to make `Accepted` mean something much stronger.

For example:

```text
This is a valid Modbus request,
using a function we support,
with valid lengths,
valid addresses,
valid quantities,
and an operation allowed by policy.
```

Ideally, the contracts in `Inspect` should eventually describe those guarantees.

---

# One request from beginning to end

The easiest file to read first is:

```text
src/net/warden_main.adb
```

It shows the whole program at a high level.

A request goes through the program like this.

### 1. Wait for a client

```ada
Wire.Wait_For_Client
```

Warden accepts a connection from a client.

It also opens a connection to the controller.

---

### 2. Read a request

```ada
Wire.Read_Request
```

Warden receives bytes from the client.

At this point they are just bytes.

Warden has not yet decided whether they make sense.

---

### 3. Inspect the request

```ada
Gate.Inspect
```

The gate uses:

```ada
Modbus.Decode
```

to understand the Modbus fields.

Then it uses:

```ada
Policy.Permits
```

to decide whether the operation is allowed.

The result is something like:

```text
Accepted
```

or a specific refusal reason.

If accepted, the gate also produces an `Approved` request.

---

### 4. Record the decision

`Warden_Main` sends the decision to the journal.

For example:

```text
warden: accepted request
```

or:

```text
warden: refused invalid protocol id
```

These messages are for humans.

They are not the security mechanism.

---

### 5. Forward accepted traffic

If the request is approved:

```ada
Wire.Forward
```

sends it to the controller.

It then waits for the controller's response and sends that response back to the client.

---

### 6. Repeat

Warden returns to step 2 and waits for the next request.

The loop continues until the client disconnects.

---

# What is deliberately incomplete?

The starter project is not a finished Modbus security proxy.

Several assumptions are intentionally wrong.

Look for comments beginning with:

```text
OPEN:
```

These identify areas you are expected to improve.

---

## 1. One TCP read is assumed to equal one Modbus request

This is false.

TCP is a **stream of bytes**.

Imagine sending this request:

```text
01 00 00 00 00 06 01 03 00 10 00 02
```

A TCP read might return:

```text
01 00 00
```

and then the next read:

```text
00 00 06 01 03 00 10 00 02
```

Or two requests might arrive in the same read.

So this assumption is wrong:

```text
one Read() == one Modbus message
```

Eventually Warden needs proper message framing.

---

## 2. Only part of the Modbus request is understood

The starter code mostly examines the header.

But a real request contains fields after the function code.

For example:

```text
Function 03
Read Holding Registers

address  = 100
quantity = 10
```

Warden eventually needs to understand those fields too.

Otherwise it cannot distinguish:

```text
read 10 registers
```

from:

```text
read 50,000 registers
```

or distinguish safe addresses from sensitive ones.

---

## 3. The policy currently allows everything

Currently:

```ada
Policy.Permits
```

returns `True`.

That is obviously not a useful security policy.

Eventually you might have rules such as:

```text
Read register 100-199       allowed
Write register 100-110      allowed
Write register 500          refused
Stop controller             refused
```

The exact policy is part of the project.

---

## 4. One client can hold Warden forever

The starter design handles one client at a time.

If that client stays connected forever, other clients cannot use the proxy.

You will need to think about timeouts, connection limits or concurrency.

---

## 5. Controller responses are trusted

The request is inspected.

The response currently is not.

A stronger design could also validate responses from the controller before returning them to the client.

---

## 6. Refused requests simply close the connection

Right now, a bad request may simply cause Warden to disconnect the client.

Later you may decide that some failures should produce a valid Modbus exception response instead.

---

# How the tests work

The main test tool is:

```text
tools/gauntlet.py
```

The gauntlet does something important:

> It checks what actually happened to the simulated plant.

It does not trust Warden's log messages.

For example, imagine Warden prints:

```text
warden: DENIED
```

but accidentally forwards the request anyway.

The test will look at the plant and notice that the controller changed.

The test therefore fails.

This is intentional.

Security is about what the system **does**, not what it says it did.

For example, tests may check:

- Did the trip setpoint change?
- Did the controller program stop?
- Did the operator receive the expected response?
- Did the malicious operation reach the controller?

The journal output:

```text
warden: ...
```

is just for humans.

You may change it freely unless a test explicitly says otherwise.

---

# Rules for working on Warden

These rules are intentionally simple.

## 1. No sockets in `src/core`

Core code should not know anything about networking.

If you find yourself writing:

```ada
with GNAT.Sockets;
```

inside `src/core`, something is probably in the wrong layer.

The core should work with Ada values such as:

```text
Byte_Array
Register_Address
Function_Code
Verdict
Approved
```

not sockets.

---

## 2. Use types to express rules

Ada is very good at this.

Do not write:

```ada
Address : Integer;
```

if what you actually mean is:

```text
a Modbus register address
```

Create a type or subtype for it.

Similarly, if Modbus says a quantity must be from `1` to `125`, do not accept every integer and remember to check it everywhere.

Prefer something like:

```ada
subtype Read_Quantity is U16 range 1 .. 125;
```

Now the rule exists in the program's type system.

The compiler and prover can help you enforce it.

---

## 3. Every refusal should have a reason

Avoid:

```text
Rejected
```

Prefer specific results such as:

```text
Invalid_Length
Invalid_Protocol
Unsupported_Function
Address_Not_Permitted
Quantity_Too_Large
Malformed_Request
```

Specific verdicts make the code:

- easier to debug;
- easier to test;
- easier to review.

---

## 4. Every new attack needs a test

If you add a new attack to:

```text
tools/attack.py
```

add the corresponding test to:

```text
tools/gauntlet.py
```

in the same change.

Otherwise we have no permanent proof that the problem stays fixed.

---

## 5. Do not break normal operation

Blocking attacks is only half the job.

Every security change must continue to allow valid operator traffic.

If a patch stops the attack but also stops normal workstation traffic, it is not a successful fix.

---

## 6. Understand the code you commit

You should be able to explain every line you submit.

It does not matter whether the first draft came from:

- you;
- another student;
- documentation;
- an AI tool.

If the code enters the project under your name, you should understand what it does and why it is there.
