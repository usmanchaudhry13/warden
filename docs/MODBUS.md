# Understanding Modbus/TCP in Warden

Modbus is the language the operator's workstation uses to talk to the pumping
station's controller. It lets the workstation ask questions such as “What is
the tank level?” and send commands such as “Start the pump.”

This page explains those conversations, then shows how they become bytes on
the network. You do not need prior knowledge of industrial controllers or
network protocols. [PLANT.md](PLANT.md) describes the simulated station and
its operating rules; [TRAIL.md](TRAIL.md) describes the project exercises.

## Why Warden sits in the middle

The **controller** is the computer that operates the pump and valve. The
**workstation** is the operator's interface. In Modbus terminology, the
workstation is the **client**: it sends requests. The controller is the
**server**: it processes requests and sends responses.

```text
workstation              Warden proxy                controller
   client  -- request --> checks and forwards ------> server
           <-- response - relays the response <-----
```

**Modbus/TCP** carries Modbus messages over a TCP network connection. The
ordinary Modbus/TCP used here has no built-in login, permission checks, or
encryption. A transaction ID matches a response to a request; it does not
identify or authenticate the sender.

That matters because a network command can change the physical station. A
request to change the high level trip might be valid Modbus, but the station's
rules forbid it: that setting protects against overflow. Warden's job is to
check both the message format and the station's policy before forwarding a
request. The deliberately vulnerable controller stays as it is.

## What can the workstation read or change?

Modbus presents a device's data as four separate **tables**. Think of each
table as a numbered list of values. The names are historical; a “coil” here
is a stored on/off value, not something you need to wire yourself.

| Table | Each item holds | Client can | Example at this station |
|---|---|---|---|
| Coils | 1 bit: off or on | read and write | pump run command |
| Discrete inputs | 1 bit: false or true | read | high level alarm |
| Input registers | 16 bits: two bytes | read | tank level measurement |
| Holding registers | 16 bits: two bytes | read and write | pump speed or high level trip |

An **address** selects an item within a table. Addresses in messages start at
zero. Each table has its own address 0: coil 0 is the pump command, input
register 0 is the tank level, and holding register 0 is the pump speed. The
operation being requested determines which table the address refers to.

A **register map** explains what each address means for a particular device.
Modbus itself does not know that a value means “tank level” or what its unit
is. At this station, the tank level register uses tenths of a percent: a raw
value of `450` means **45.0 %**. See the full map in [PLANT.md](PLANT.md).

Some equipment manuals use labels such as `30001` or `40001`. Those are
reference labels, not the addresses to copy into our messages. Use the
zero-based addresses in this project's register map.

## How to read the numbers below

A **byte** contains 8 bits. Two bytes can carry an unsigned integer from 0 to
65,535. The byte listings below use **hexadecimal** (base 16): each pair of
characters is one byte. For example, `0A` is decimal 10, and `10` is decimal
16. The prefix `0x` also means hexadecimal, so `0x10` and decimal `16` are the
same function code.

Multi-byte Modbus fields put the most significant byte first, called
**big-endian**. For example, decimal 450 is hexadecimal `01 C2`:
`1 × 256 + 194 = 450`. This byte order does not describe the packing of
individual coil bits; read responses pack the first requested coil into the
least significant bit of the first data byte.

## A complete example: read the tank level

The workstation wants one value from input register address 0. It sends this
12-byte request:

```text
00 01  00 00  00 06  01  04  00 00  00 01
```

Read it from left to right:

| Bytes (hex) | Field | Meaning in this request |
|---|---|---|
| `00 01` | Transaction ID | request number 1, chosen by the client |
| `00 00` | Protocol ID | 0 means Modbus |
| `00 06` | Length | six bytes follow this field |
| `01` | Unit ID | device identifier 1, used by our tools |
| `04` | Function code | read input registers |
| `00 00` | Starting address | start at input register 0 |
| `00 01` | Quantity | read one register |

If the level is 45.0 %, a successful response is:

```text
00 01  00 00  00 05  01  04  02  01 C2
```

The transaction ID is still 1, so the client can match the response to its
request. The function code is still 4. The next byte, `02`, says that two
bytes of register data follow. Those bytes, `01 C2`, represent 450. The
workstation applies the station's scale and displays 45.0 %.

Notice that the response has a different length and data layout from the
request. A request carries an address and quantity; this read response
carries a byte count and the values that were read.

## The structure shared by all messages

Each Modbus/TCP message has a seven-byte **header**, followed by a function
code and the data for that function. An **offset** is a byte's position,
counting from zero at the start of the message.

| Offset | Size in bytes | Field | Purpose |
|---:|---:|---|---|
| 0 | 2 | Transaction ID | client chooses it; server copies it into the response |
| 2 | 2 | Protocol ID | must be 0 for Modbus |
| 4 | 2 | Length | number of bytes after this field, including the unit ID |
| 6 | 1 | Unit ID | selects a device behind a gateway; not a user identity |
| 7 | 1 | Function code | selects the operation |
| 8 | varies | Function data | addresses, quantities, values, or response data |

The specification calls the header **MBAP** (Modbus Application Protocol
header). It calls the function code plus function data the **PDU** (Protocol
Data Unit). The whole message is the **ADU** (Application Data Unit).

```text
complete message (ADU) = 7-byte header (MBAP) + function code and data (PDU)
```

The PDU is at most 253 bytes, so a complete Modbus/TCP message is at most
260 bytes. The length field can therefore be at most 254: one byte for the
unit ID plus up to 253 bytes for the PDU. The total message size is
**6 + length**, because the length field counts everything after byte 5.

## The operations this station uses

A **function code** is the number that tells the controller what to do. In
this table, codes and limits are decimal; numbers in parentheses are field
sizes in bytes. An address is a starting address, and a quantity counts
consecutive items, not bytes.

| Code | Operation | Data after the function code | Valid values |
|---:|---|---|---|
| 1 | Read Coils | address (2), quantity (2) | quantity 1–2000 |
| 2 | Read Discrete Inputs | address (2), quantity (2) | quantity 1–2000 |
| 3 | Read Holding Registers | address (2), quantity (2) | quantity 1–125 |
| 4 | Read Input Registers | address (2), quantity (2) | quantity 1–125 |
| 5 | Write Single Coil | address (2), value (2) | hex `FF 00` for on, `00 00` for off |
| 6 | Write Single Register | address (2), value (2) | raw value 0–65,535 |
| 16 (`0x10`) | Write Multiple Registers | address (2), quantity (2), byte count (1), values (2 each) | quantity 1–123; byte count = 2 × quantity |

Functions 1–6 above have a five-byte request PDU and a 12-byte complete
request. Function 16 has a request PDU of `6 + 2 × quantity` bytes and a
complete request of `13 + 2 × quantity` bytes.

These are protocol limits, not promises that the station has that many
items or permits every value. The requested range must exist in the device's
map, and Warden must apply the operating rules to the **entire range**. A
block write starting at register 0 with quantity 11 reaches register 10,
which is the protected high level trip.

The simulator also accepts a custom function, `0x5A`, that stops its control
program. It is outside the standard operations listed above and is forbidden
by the station's policy. See [PLANT.md](PLANT.md) for its consequences.

## Successful responses and errors

A successful response uses the request's function code. Its data depends on
the operation:

- Reads (1–4) return a byte count followed by the requested bits or registers.
- Single writes (5 and 6) echo the address and value written.
- A multiple-register write (16) returns the starting address and quantity
  written, without repeating all the values.

If a server reports a Modbus error, it sends an **exception response**: the
request's function code with `0x80` added, followed by one exception byte.
For example, a rejected function-4 read has PDU `84 02` if the address is
illegal.

| Exception code (decimal) | Meaning |
|---:|---|
| 1 | Illegal function: this operation is not supported |
| 2 | Illegal data address: the requested range is not available |
| 3 | Illegal data value: a request field has an unacceptable value |
| 4 | Server device failure: the server could not perform the operation |

An exception response is still a message. A closed connection or timeout is
different: no usable response arrived. The starter Warden proxy closes the
client connection when it refuses a request; it does not send a Modbus
exception explaining its policy decision.

## Why the length fields are a security problem

A client supplies every byte of its request, including the fields that claim
how large the request is. An attacker can make those claims disagree.

For a function-16 request writing two registers, all of these must agree:

| Check | Expected value |
|---|---|
| Quantity | 2 registers |
| Byte count | 4 bytes of values |
| PDU size | 10 bytes: function (1) + address (2) + quantity (2) + byte count (1) + values (4) |
| Header length field | 11 bytes: unit ID (1) + PDU (10) |
| Complete message size | 17 bytes: header (7) + PDU (10) |

A well-behaved sender produces consistent fields. A receiver must check them;
receiving bytes does not make their contents trustworthy. The simulated
controller deliberately misses some checks. If Warden checks one claimed
size while the controller follows another, they may disagree about what the
request does. [TRAIL.md](TRAIL.md), stops 3 and 4, explores that problem.

There is another complication: **TCP delivers a stream of bytes, not one
Modbus message per socket read**. One read may return part of a message, one
whole message, or several messages together. Warden must accumulate enough
bytes to read the header, validate the announced length, and then collect
exactly that message. Remaining bytes belong to the next message and need
their own checks. A connection can carry many request/response exchanges.

## Try building a request yourself

From the repository root, run:

```console
python3 - <<'PY'
import sys
sys.path.insert(0, 'tools')
import modbus

# The PDU says what to do: read one input register, starting at address 0.
pdu = modbus.read_input_registers(0, 1)
# Add the TCP header. Defaults are transaction 1, unit 1, protocol 0.
message = modbus.frame(pdu)
print(message.hex(' '))
PY
```

Expected output:

```text
00 01 00 00 00 06 01 04 00 00 00 01
```

This only builds and prints bytes; no running station is needed. To build a
“start pump” request instead, replace the `pdu` assignment with
`pdu = modbus.write_single_coil(0, True)`. The function becomes `05` and the
value becomes `FF 00`.

[tools/modbus.py](../tools/modbus.py) contains the message builders. Follow
the [README](../README.md) to run the workstation, proxy, and controller and
see real exchanges in the simulation.

## Specification references

The field layouts and protocol limits above come from the Modbus Organization's
specifications:

- [Modbus Application Protocol Specification V1.1b3](https://www.modbus.org/file/secure/modbusprotocolspecification.pdf):
  sections 4.2–4.4 explain encoding, tables, and addressing; section 6 describes
  each function; section 7 describes exceptions.
- [Modbus Messaging on TCP/IP Implementation Guide V1.0b](https://www.modbus.org/file/secure/messagingimplementationguide.pdf):
  explains the TCP header and request/response exchanges over a connection.

The [official specifications page](https://www.modbus.org/modbus-specifications)
is another route to those documents. When this page and the specification
disagree about Modbus, the specification wins. The station's register meanings
and operating policy are defined separately in [PLANT.md](PLANT.md).
