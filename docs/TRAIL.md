# A beginner's path through the Warden project

Your goal is to turn the starter Warden proxy into a guard that blocks
forbidden Modbus requests while keeping the operator's normal traffic
working. You will also use SPARK to prove specific properties of the code,
and explain the design's strengths and limits in a written report.

A **proxy** is a program between a client and a server. Here, it sits between
the operator's workstation and the pumping station's controller. The starter
proxy already relays traffic, but its checks are deliberately incomplete.
Your work is to strengthen those checks; leave the simulated controller's
intentional weaknesses in place.

## Before you start

Read [PLANT.md](PLANT.md) to understand the tank, commands, safety interlock,
and operating rules. Then read [MODBUS.md](MODBUS.md) to see how those commands
become network messages. Follow the [README](../README.md) to install the
tools and run the three programs.

If Ada is new to you, keep [Ada_FOR_WARDEN.md](../Ada_FOR_WARDEN.md) nearby.
It explains packages, types, and contracts used throughout the project.
[ARCHITECTURE.md](../ARCHITECTURE.md) explains how those packages fit together.
Comments marked `OPEN:` identify unfinished parts of the starter code.

Run commands below from the repository root unless an exercise says
otherwise. These are the main checks you will use:

| Command | What it tells you |
|---|---|
| `alr build` | whether the Ada program compiles; rebuild after code changes |
| `python3 tools/gauntlet.py` | whether the current proxy passes the test cases |
| `python3 tools/gauntlet.py --log` | the same tests, with proxy output for diagnosis |
| `python3 tools/gauntlet.py --direct` | how the station behaves without Warden |
| `alr exec -- gnatprove -P warden.gpr` | whether GNATprove establishes the stated contracts and safety checks |

The **gauntlet** is the project's automatic test suite. It starts its own
station and proxy and resets the station between tests, so the manual demo
does not need to be running. Its security verdict comes from the station's
actual state, not Warden's printed decision. Some tests check attacks;
others check that legitimate traffic still works.

**SPARK** is a subset of Ada with rules and tools for formal reasoning.
**GNATprove** is the prover. A **contract** describes what must be true before
or after a code operation. A clean proof establishes the properties you
actually stated within the proof's scope and assumptions. It does not, by
itself, mean the proxy blocks all attacks: the starter code proves clean
while allowing dangerous requests.

## How to use the eight stops

A “stop” is a learning and implementation milestone. Stops 1–7 build on each
other. Stop 8 runs alongside them from the beginning: keep notes about
attacks, risks, and evidence as you work instead of reconstructing them at
the end.

Each stop contains:

- **Idea:** the concept you need to understand and why it matters here.
- **Where:** the code and documents to inspect.
- **Try:** a small experiment, where provided, before designing a fix.
- **Questions:** prompts for design decisions you must be able to explain.
- **Done when:** observable requirements for completing that milestone.

The stops define the outcome without prescribing a complete implementation.
Before changing code, explain the failure in plain language. After changing
it, check both hostile and legitimate traffic, then run the relevant proof.

## Choose a scope: floor, target, and stretch

| Level | Stops | What you can show |
|---|---|---|
| **Floor** | 1 to 5 | 9 of 10 gauntlet tests pass, the core proves clean, and you can state what "Accepted" guarantees |
| **Target** | 6 and 7 | the gauntlet is green, the proxy rewrites what it forwards and survives a hostile client |
| **Stretch** | the list at the end | your choice |

Stop 8 is not a level. It runs next to the others from the first week, and it
is where your written report comes from.

The **floor** is the complete minimum project. The **target** adds stronger
forwarding and availability protections. **Stretch** items are optional
extensions once the earlier work is finished. “The gauntlet is green” means
all its tests pass. At the floor, the expected remaining failure is
`silent_connection`, addressed in stop 7.

Reach the floor first, completely, before starting anything in the target.
A finished floor is a real project. A half-built target is not.

One way to share the work: one person builds the wall (stops 3 to 7), one
attacks it (stop 8, new attacks, new tests). Review each other's work, so that
everyone touches SPARK and everyone writes attacks.

---

## Stop 1. Understand the station and write a request

**Idea.** Modbus is how the operator's screen talks to the controller: read a
table, write a table. It was designed in 1979 for a serial cable inside one
cabinet, where everyone on the wire was trusted. The ordinary Modbus/TCP
used in this project carries those operations over TCP without built-in client authentication or permission checks. Being able
to reach the controller is enough to send it commands.

**Where.** [MODBUS.md](MODBUS.md), [PLANT.md](PLANT.md), `tools/plant.py`,
`tools/workstation.py`, `tools/modbus.py`.

**Try.** Start `python3 tools/plant.py` in one terminal and
`python3 tools/workstation.py --port 5020` in another. This connects the
operator directly to the controller. Watch how pump commands affect the level.

Next, use the byte-building example in [MODBUS.md](MODBUS.md). Identify each
field of a read request, then build a request that starts the pump. Use
`modbus.Client(5020)` from the helpers in `tools/modbus.py` to send your request
and read the level yourself. The raw level uses tenths of a percent.

**Questions.**

- Which bytes of a message say how long it is? How many different fields carry
  that information, and what if they disagree?
- What does the controller know about who sent a request?
- Run `python3 tools/gauntlet.py --direct`. For each failure, what would the
  consequence be in a real station?
- Why can you not simply fix the controller?

**Done when.** Each of you can write a valid request by hand, in hex, and say
what the station will do with it.

---

## Stop 2. Understand how the gate controls forwarding

**Idea.** A proxy is a program that sits between two parties and relays what
they say. Because everything goes through it, it can also read, check, refuse
and rewrite. That position is the whole value of the project, and it has a
price: if the proxy is wrong or down, the operator is blind.

**Where.** `src/net/warden_main.adb`, `src/core/warden-gate.ads`,
`src/net/warden-wire.ads`, [ARCHITECTURE.md](../ARCHITECTURE.md).

The gate produces an **`Approved` value** when it accepts a request. This
private Ada type hides its representation from other packages. Forwarding
also requires proof that `Gate.Is_Valid` is true: merely declaring a variable
of type `Approved` is not enough. The postcondition of `Inspect` and the
precondition of `Forward` connect the gate's decision to the send operation.

**Try.** Run the full setup from the README and follow one request through
the three terminals. Then, in `warden_main.adb`, try to call `Wire.Forward`
with an `Approved` you build yourself: read what the compiler says. Then,
as a temporary experiment, remove the `exit when not Gate.Is_Valid (Request);`
line and run GNATprove. Restore the line after examining the failed proof.

**Questions.**

- Draw the path of one request and its answer. Which package touches it at
  each step?
- What exactly is sent to the controller: the client's bytes, or something
  else? Where in the code is the answer?
- The seed hangs up on a refused request. What does the operator's screen
  show? What else could the proxy do?
- If the proxy crashes, should traffic flow around it or stop? Who is hurt in
  each case?

**Done when.** Each of you can explain, to someone outside the project,
how `Warden.Gate` controls approval and why the proved call to
`Wire.Forward` requires a valid approved request. Explain also that the socket
implementation is trusted code outside the core proof: types and contracts
do not independently prove every network action.

---

## Stop 3. Separate messages from the TCP byte stream

**Idea.** TCP gives you bytes in order. It does not give you messages. One
read can return half a request, or a request and a half, or three requests.
A program that treats "one read" as "one message" works on a quiet local
network and fails everywhere else. It also offers an attacker a hiding place:
whatever sits behind the part that was checked.

**Framing** means finding each complete message within that stream. For
Modbus/TCP, the header's length field gives a claimed boundary. You must
validate that claim, wait for missing bytes, and retain any bytes belonging
to the next message. For example, two complete requests in one socket read
need two separate gate decisions.

**Where.** `Wire.Read_Request` and its `OPEN:` note, `Gate.Inspect`, the
attacks `smuggled_frame` and the test `slow_link` in `tools/gauntlet.py`.
[MODBUS.md](MODBUS.md) for the length field.

**Try.** Run `python3 tools/gauntlet.py --log` and read what the proxy printed
for `slow_link` and for `smuggled_frame`. Explain both results from the code.

**Questions.**

- Given a pile of bytes received so far, how do you know whether a whole
  message is there? Which field tells you, and can you trust it?
- Bytes that arrived but do not yet make a message must wait somewhere. How
  big is that place? What happens when a client sends a header announcing a
  message that never comes?
- This logic has no socket in it: bytes in, messages out. Which side of the
  architecture does it belong to? What would its contract say?
- What can SPARK prove about it, for every possible sequence of bytes?

**Done when.** `slow_link` and `smuggled_frame` pass, a request split at any
byte still works, and GNATprove reports no unproved check in the new code.

---

## Stop 4. Check that every field forms a valid request

**Idea.** The proxy and the controller both read the same bytes, with two
different programs. Wherever they understand a message differently, an
attacker can write a message that looks harmless to one and does harm in the
other. This is called a **parser differential**. The cure is to accept only
messages that have exactly one possible reading, as defined by the
specification, and to refuse everything else.

This step checks **syntax and protocol rules**, before asking whether the
station permits the operation. A correctly sized write to the safety trip
can pass this step and still be refused by policy in stop 5. A read with an
impossible quantity fails here regardless of who sends it.

A **typed field** is an Ada value that represents a specific concept, such
as a register address or a quantity restricted to the legal range. A
**`Verdict`** is a named outcome explaining acceptance or a refusal reason.

**Where.** `src/core/warden-modbus.ads` and its two `OPEN:` notes, section 6
of the Modbus specification (linked from [MODBUS.md](MODBUS.md)), the list of
the controller's weaknesses in [PLANT.md](PLANT.md), the attacks
`oversized_read` and `stop_controller`.

**Try.** For function 16, list every field that says something about the size
of the message. Write, by hand, a message where they disagree. Send it to the
controller directly and see which one it believed.

**Questions.**

- For each function the station uses: what are the fields, their legal ranges,
  and the exact length of a correct message?
- A function code that is not in your list arrives. Is that a malformed
  message or a forbidden one? Does the difference matter?
- After checking, the request is no longer "some bytes". What Ada type
  describes "a checked request", so that later code cannot receive an
  unchecked one?
- Which checks belong to "is it Modbus" and which to "is it allowed here"?

**Done when.** Every request the gate accepts is exactly as long as its
function says, every field is in its legal range, each reason to refuse has
its own `Verdict`, and `oversized_read` passes.

---

## Stop 5. Enforce the station’s operating rules

**Idea.** A perfectly formed request can be one that nobody should send.
“Write holding register 10” can be valid Modbus; at this station it changes
the safety threshold, and a value above 100 % defeats the trip. The rules
about who may do what are the **policy**. The safe way to
write a policy is an allowlist: name what is permitted, refuse the rest. The
unsafe way is to list what is forbidden and hope the list is complete.

Apply the allowlist to the whole operation. A permitted starting address
is insufficient if a block write extends into forbidden addresses. Also
remember that the starter proxy has no verified client identity: a function
and address policy cannot tell the operator's request from an attacker's
identical request.

**Where.** `src/core/warden-policy.ads`, the operating rules in
[PLANT.md](PLANT.md), the postcondition of `Gate.Inspect`, the attacks
`write_safety_register`, `write_across_boundary`, `stop_controller`.

**Try.** Write the station's five operating rules as a table: function,
address range, allowed or not. Find a request that your table does not cover.

**Questions.**

- A block write covers registers 0 to 10. Register 0 is allowed, register 10
  is not. What is the rule for a range?
- Where should the policy live: in code, in a constant table, in a file read
  at start? What does each choice cost when the station changes? When someone
  tampers with it?
- What would you like the postcondition of `Inspect` to say? Write the
  sentence in English first: "a request is approved only if ...".
- The brief asks you to prove that a denied function code cannot produce a
  forwarding decision. With the `Approved` type, what is left to prove?

**Done when.** Nine of the ten gauntlet tests pass, GNATprove is clean, and
the postcondition of `Inspect` states your security claim. That is the floor.

---

## Stop 6. Rebuild requests from checked fields

**Idea.** Today the gate copies the client's bytes into the `Approved` value.
A stronger design throws the client's bytes away: once a request is checked,
the gate writes a new message from the checked fields only. This is
**canonical re-encoding**. Whatever the gate did not understand cannot
survive it, because it was never copied.

For example, after checking a two-register write, generate its byte count
and header length from the two checked values. Do not preserve the client's
size claims just because they appeared in the input. The transaction ID can
still be retained as a decoded field so the client can match the response.

**Where.** Step 3 of `Gate.Inspect` and its `OPEN:` note.

**Questions.**

- Which fields do you keep from the client, and which do you compute yourself?
  Think about `length`, `byte count`, the transaction id, the unit id.
- Two different inputs produce the same output message. Is that a problem or
  the goal?
- Decode, then encode, then decode again: what should be true? Can you state
  it as a contract, and prove it?
- Can you name an attack that passes every check of stops 4 and 5 and is
  still stopped by re-encoding?

**Done when.** No byte sent to the controller is copied from the input without
going through a typed field, and you have a test that shows it.

---

## Stop 7. Keep the operator served under hostile traffic

**Idea.** An attacker who cannot get a bad request through can still try to
make the proxy useless: hold connections, send floods, send headers and never
finish. For an operator, a proxy that stops answering is as bad as no
controller. Every resource the proxy uses must have a limit decided in
advance: connections, buffers, waiting time, requests per second.

This is **availability**: the operator must get service within a useful
time. A **timeout** limits waiting; a **connection limit** bounds the number
of clients; a **rate limit** bounds how quickly requests are handled. Choose
limits you can justify and demonstrate. A flood is a sustained burst of
requests intended to consume resources, even when each request is refused.

**Where.** The `OPEN:` notes in `warden_main.adb`, `Wire.Read_Request` and
`Warden.Journal`. The test `silent_connection`, the attack `flood`.

This stop is the least built in the seed, on purpose: the design is yours.
Bring a one-page proposal to your mentor before writing code.

**Questions.**

- The seed serves one client at a time. What are the ways to serve several,
  and what does each one do to the proof and to the limits?
- How long may a client stay silent? Send half a message? What happens when
  the time is up?
- Monitoring matters more than control when things go wrong. Could reads keep
  working while writes are refused (a degraded, read-only mode)? Who decides
  to enter and leave it?
- The journal is a print statement. After an incident, what must be in it?
  Can a flood of refused requests fill the disk, or hide the one line that
  matters?
- The controller does not answer. What does the proxy do, and for how long?

**Done when.** The gauntlet is green, and a demo shows: a silent client and a
flood, with the operator still served; the proxy killed and restarted, with
the station back under control in a time you announced beforehand.

---

## Stop 8. Test the design as an attacker and record the evidence

**Idea.** You cannot claim a guard works if you never tried to get past it. A
**threat model** is the organised version of that: who attacks, what they
control, what they want, and for each combination, what stops them or why you
accept the risk. A good one ends with an honest list of what is not covered.

For example, a network attacker may try to change the safety trip. Record
what access they need, the request they send, the consequence without
Warden, the check that should block it, and the test that confirms the trip
stayed unchanged. If a risk remains, state why and what additional protection
would be needed.

Keep separate evidence for tests and proofs. Tests demonstrate particular
executions. A proof covers the stated property for the inputs and assumptions
in its scope. Neither a passing scoreboard nor a clean proof replaces an
explicit account of the design's limits.

**Where.** `tools/attack.py`, `tools/gauntlet.py`, "What needs protection?"
in [PLANT.md](PLANT.md).

**Try.** Run `python3 tools/attack.py --list`. Read two attacks, then write a
new one and its test. Make it one the current proxy does not stop.

**Questions.**

- Three adversaries: someone on the network, a compromised operator
  workstation, an insider. What can each one do that the others cannot?
- The attacker records the operator's "start pump" and sends it again later
  (a **replay**). The bytes are identical. What can a proxy do about that,
  and what would it need to know about its clients?
- The compromised workstation sends only requests the policy allows, but at
  the wrong moment: valve closed, pump on. Is that the proxy's job?
- Ten hand-written tests are a sample. How would you generate thousands of
  random or mutated messages, and what would you check on each one?
- Which attacks does this design not stop at all? Saying so clearly is part
  of the result.

**The written part.** Use your notes to explain the problem, design,
evidence, and remaining risks. A **risk matrix** compares likelihood and
impact; the direct and protected test results provide evidence for it, but
pass/fail counts alone are not a risk assessment. A **contingency plan** says
what to do while an incident is happening. A **recovery plan** says how to
restore operation afterward.

Your course brief asks for eight items. They are not extra work next to the
code; each one is a way of writing down what the stops
made you find out.

| Item in the brief | Where the material comes from |
|---|---|
| Threat analysis | this stop: adversaries, goals, attacks |
| Vulnerability analysis | stops 1, 3 and 4: the controller's weaknesses, streams, parser differentials |
| Risk matrix | `gauntlet.py --direct` against your final scoreboard: before and after |
| Mitigation plan | stops 3 to 7, with the proof results |
| Named protected data items | "What needs protection?" in PLANT.md, completed |
| Applied security standard | NIST SP 800-82 for the vocabulary, the Modbus specification for stop 4 |
| Contingency plan | stop 7: what the proxy and the people do under each attack |
| Recovery plan | stop 7: the kill and restart demo, with measured times |

**Done when.** There is a threat table (adversary, goal, attack, mitigation or
accepted risk), every line that has a mitigation has a test, and the list of
what is *not* covered is written down.

---

## Optional extensions after the target

Pick by interest, not in order.

- **Check the answers too.** A compromised controller, or a confused one, can
  lie to the operator.
- **Know who is asking.** Give clients an identity (TLS with client
  certificates, for example) so that policy can depend on the client, and
  replay becomes harder.
- **Policy as a file**, with a way to detect that it was tampered with, and a
  last known good copy to fall back to.
- **Fuzzing.** Automatically generate thousands of random or mutated messages,
  with the station's state and legitimate traffic as the judges.
- **On a board.** The core has no operating system in it. Run the proxy on a
  microcontroller with two network ports.

## Reading

- [Learn SPARK](https://learn.adacore.com/courses/intro-to-spark/index.html),
  chapters 1 to 4 are enough to start.
- [Learn Ada](https://learn.adacore.com/courses/intro-to-ada/index.html),
  especially strong typing, records, arrays, packages and privacy.
- The two Modbus documents linked from [MODBUS.md](MODBUS.md).
- [NIST SP 800-82 Rev. 3](https://csrc.nist.gov/pubs/sp/800/82/r3/final),
  *Guide to Operational Technology Security*. Long; read the overview of OT
  systems and the chapter on security architecture.
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework), for
  the vocabulary of the written part.
- [LangSec](https://langsec.org): why input handling is where security fails,
  and why "recognise fully before you process" is the rule behind stops 3
  and 4.
