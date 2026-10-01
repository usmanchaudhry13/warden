# Understanding the pumping station

The station is the system Warden protects. It contains a water tank, a pump
that fills it, a valve that drains it, and a controller that operates the
pump and valve. Everything is simulated in [tools/plant.py](../tools/plant.py):
there is no physical equipment, and all measurements are synthetic.

The operator's workstation sends Modbus requests to the controller to read
measurements and change commands. Warden sits between them and decides which
requests may reach the controller. [MODBUS.md](MODBUS.md) explains that
message format; this page explains what the messages mean for the station.

## What makes the water level change?

```text
            pump                    valve
 supply ----(P)---->  [  tank  ] ----|><|----> drain
                       level 0 to 100 %
```

The level is the percentage of the tank that is full. A level of 50 % means
half full. Inflow adds water; outflow removes water.

| Command state | Effect on tank level |
|---|---|
| Pump on at full speed | adds 2 percentage points per second |
| Pump off | adds no water |
| Valve open, with water available | removes 1.5 percentage points per second |
| Valve closed | removes no water |

When both the pump and valve are active, their effects combine. At full pump
speed with the valve open, the tank gains `2 − 1.5 = 0.5` percentage points
per second. With the valve closed, the same pump fills it faster: 2 points
per second. Lower pump speed reduces inflow proportionally.

The simulator starts with the tank at **50 %**, the pump **off**, the valve
**open**, the pump speed set to **100 %**, and the safety trip set to **90 %**.
The level therefore falls until someone starts the pump. The workstation
normally keeps the level between 40 % and 60 % by starting and stopping it.

## What prevents an overflow?

The controller runs a **control program**: software that checks the station
and operates its outputs. Part of that program is a **safety interlock**, an
automatic rule that stops the pump when the tank reaches the high level trip.

The **high level trip** is the threshold for that rule, initially 90 %. It
is a setting, not a measurement. The **high level alarm** reports whether the
current level is at or above that threshold; the alarm is a status value,
not the mechanism that stops the pump.

At 100 %, the simulator records an **overflow**. Its overflow flag is
**latched**: once set, it stays true even if the water level later falls.
Restarting the standalone simulator resets the station, including this flag.

Two network operations can defeat the interlock:

- Raising the high level trip above 100 % prevents the tank from reaching the
  shutdown threshold before it overflows.
- Stopping the control program prevents the interlock from running. The pump
  and valve commands stay in their current states, and ordinary writes fail.
  Water continues to move according to those states; stopping the program
  does not stop the physical process being simulated.

Reads still work after the control program stops. That distinction matters:
an operator may still see the level rise while being unable to stop the pump
with an ordinary write.

## How Modbus addresses the station

The controller exposes four numbered tables. A **coil** is an on/off command;
a **discrete input** is an on/off status; a **register** holds a two-byte
number. Input registers are read-only measurements. Holding registers are
settings that the protocol allows a client to read or write.

Each table has its own addresses, starting at zero. Input register 0 and
holding register 0 are different items. A Modbus function code selects the
table and operation; an address selects the item within that table.

| Table | Address | Meaning | Unit of raw value | Read function | Write function |
|---|---:|---|---|---|---|
| Coil | 0 | pump run command | off/on | 1 | 5 |
| Coil | 1 | valve open command | off/on | 1 | 5 |
| Discrete input | 0 | high level alarm | false/true | 2 | none |
| Discrete input | 1 | overflow, latched | false/true | 2 | none |
| Input register | 0 | tank level | 0.1 % | 4 | none |
| Input register | 1 | inflow | 0.1 percentage points/s | 4 | none |
| Input register | 2 | outflow | 0.1 percentage points/s | 4 | none |
| Holding register | 0 | pump speed | 0.1 % | 3 | 6 or 16 |
| Holding register | 1–9 | unused | — | 3 | 6 or 16 |
| Holding register | 10 | **high level trip** | 0.1 % | 3 | 6 or 16 |
| Holding register | 11–15 | unused | — | 3 | 6 or 16 |

The units tell you how to interpret a raw number. For example:

- Tank level `500` means 50.0 %.
- Pump speed `1000` means 100.0 % of full speed.
- High level trip `900` means 90.0 %.
- Inflow `20` means 2.0 percentage points per second.

A register's two-byte capacity is not a safe operating range. The deliberately
sloppy controller accepts pump-speed values above 1000; do not assume it
clamps them to 100 %. Deciding and documenting any additional value limits
belongs to the proxy's policy design.

“Write function” in the map describes what the controller can execute. It
does **not** mean Warden should permit that write. Unused registers exist in
the simulator, but the operating rules do not authorize writing them.

There is also a custom function code, **`0x5A`** (decimal 90), that stops the
control program. This is a simulator-specific operation outside the standard
Modbus functions listed in [MODBUS.md](MODBUS.md). It represents the kind of
engineering command a vendor might provide.

## The operating rules Warden must enforce

These requirements come from the station's operators. They define the
starting policy: the rules for deciding which requests are permitted.

1. Anyone on the operations network may **read** any existing table item.
2. The operator may start and stop the pump, open and close the valve, and
   set the pump speed.
3. **Nobody changes the high level trip over the network.** It is configured
   once, on site.
4. Nobody stops the control program over the network.
5. Operations not authorized above are unnecessary and must be refused.

A permitted read must still be a correctly formed request for an existing
range. “Anyone may read” does not authorize malformed or oversized requests.
For a block write, every addressed item must be permitted. Starting a write
at the allowed pump-speed register does not authorize continuing through the
unused registers and into the safety trip.

Use an **allowlist**: explicitly describe permitted operations and refuse
anything else. How you represent those rules in the proxy is your design.

The starter proxy does not authenticate clients. Calling a program “the
operator” does not give it a verified identity: an attacker can send the same
bytes. A policy based on functions and addresses can protect the trip and
block the stop command, but distinguishing an authorized operator from other
clients requires additional identity information.

## Why the controller is deliberately vulnerable

The controller is part of the exercise, not the component you are asked to
repair. Its implementation intentionally:

- accepts commands from anyone who can connect;
- ignores the protocol ID and unit ID in the Modbus header;
- processes successive messages in the TCP stream, including a second
  message attached after an apparently harmless first one;
- closes the affected connection and records a communication fault when a
  read requests more than 125 items;
- accepts a multiple-register write without checking that its quantity,
  byte count, and actual data agree, and writes the values that fit.

Processing several messages on one connection is normal TCP behavior. The
security problem arises if Warden checks only the first message but forwards
additional unchecked bytes with it.

**Do not fix the controller.** The project models a situation where you
cannot change the device's firmware: it belongs to a vendor, and replacement
or recertification may be difficult. Improve the proxy in front of it.

The communication fault in this simulator does not stop the water model or
shut down the whole server. Keep that distinction in mind when describing
what an attack actually demonstrated and what it might imply for real
hardware.

## Watch the station yourself

From the repository root, open two terminals. In the first, start the station:

```console
python3 tools/plant.py
```

In the second, connect the workstation directly to the station:

```console
python3 tools/workstation.py --port 5020
```

Port `5020` is the controller. This direct connection is useful for learning
its behavior. The normal protected path goes through Warden on port `5021`;
follow the [README](../README.md) to run that setup.

Watch the station's printed level, pump state, valve state, and trip setting.
Stop each program with Ctrl+C. Restarting `plant.py` restores the initial
state, which is how you recover the standalone demo after sabotage.

To examine the controller's weaknesses automatically, run:

```console
python3 tools/gauntlet.py --direct
```

This command creates its own test station and resets it between cases; you
do not need the two demo terminals running. A failed security test means the
unprotected station suffered the action the test expected to prevent. These
failures establish what Warden needs to stop.

## What needs protection?

For each item, ask three questions: who may see it (**confidentiality**), who
may change it (**integrity**), and when it must be usable (**availability**).
The operating rules allow reads, so secrecy is not the main concern for every
item.

| Item | Why it matters |
|---|---|
| Pump and valve commands | changes affect water movement |
| High level trip | changes can disable overflow protection |
| Tank level measurement | the operator relies on it to make decisions |
| Control program | it must keep running for the interlock to work |
| Proxy policy | tampering could authorize dangerous requests |
| Proxy journal (decision log) | trustworthy records help explain an incident |

This is a starting list for your threat analysis. Explain the protection each
item needs, how you will test it, and which risks your design leaves outside
its scope. [TRAIL.md](TRAIL.md), stop 8, turns that analysis into report material.
