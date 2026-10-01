#!/usr/bin/env python3
"""The gauntlet: run every test through the proxy and print a scoreboard.

    python3 tools/gauntlet.py               # all tests, through the proxy
    python3 tools/gauntlet.py --baseline    # only the tests the seed passes
    python3 tools/gauntlet.py --direct      # no proxy: the station on its own
    python3 tools/gauntlet.py --log         # also show what the proxy printed

Run `alr build` first. Each test gets a fresh station and a fresh proxy,
on free ports, so nothing else needs to be running.

The verdict of a test never comes from what the proxy says. It comes from
the station: did the forbidden thing happen or not?

On the untouched seed, the baseline tests pass and every other test
FAILS. Turning this scoreboard green is the project.
"""

import argparse
import os
import socket
import subprocess
import sys
import threading
import time

import attack
import modbus
import plant as plant_module
from plant import COIL_PUMP, HR_HIGH_TRIP, IR_LEVEL

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WARDEN = os.path.join(ROOT, "bin",
                      "warden.exe" if os.name == "nt" else "warden")

TESTS = []


def test(baseline=False):
    def register(function):
        TESTS.append((function, baseline))
        return function
    return register


class Range:
    """One station, and one proxy in front of it."""

    def __init__(self, plant, plant_port, direct):
        self.plant = plant
        self.log = []
        self.process = None
        if direct:
            self.port = plant_port
            return

        self.port = free_port()
        self.process = subprocess.Popen(
            [WARDEN, "--listen", str(self.port),
             "--controller", str(plant_port)],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        first = self.process.stdout.readline().strip()
        self.log.append(first)
        if "listening" not in first:
            raise RuntimeError(f"the proxy did not start: {first}")
        threading.Thread(target=self._drain, daemon=True).start()

    def _drain(self):
        for line in self.process.stdout:
            self.log.append(line.strip())

    def close(self):
        if self.process:
            self.process.kill()
            self.process.wait()


def free_port():
    with socket.socket() as sock:
        sock.bind((modbus.HOST, 0))
        return sock.getsockname()[1]


def settle():
    """Give the proxy and the station time to finish what was sent."""
    time.sleep(0.2)


def trip_unchanged(r):
    value = r.plant.holding[HR_HIGH_TRIP]
    if value != 900:
        return (f"the safety trip was changed "
                f"({90.0:.1f}% -> {value / 10:.1f}%)")
    return None


# --- Normal traffic must go through -------------------------------------------

@test(baseline=True)
def operator_round(r):
    """The operator reads the level and starts the pump."""
    try:
        with modbus.Client(r.port) as client:
            level = client.words(modbus.read_input_registers(IR_LEVEL, 1))[0]
            client.request(modbus.write_single_coil(COIL_PUMP, True))
    except (modbus.Refused, modbus.ModbusError) as error:
        return f"the operator got no proper answer ({error})"
    if level != 500:
        return f"the operator read a wrong level ({level})"
    if not r.plant.coils[COIL_PUMP]:
        return "the pump command did not reach the controller"
    return None


@test()
def slow_link(r):
    """An honest read that arrives in two pieces, as TCP is allowed to do."""
    request = modbus.frame(modbus.read_input_registers(IR_LEVEL, 1))
    answer = attack.send(r.port, request[:5], request[5:], pause=0.3)
    if len(answer) < 11 or answer[7] != 4 or answer[9:11] != b"\x01\xf4":
        return "the operator got no proper answer"
    return None


@test()
def silent_connection(r):
    """Someone connects and says nothing. The operator must still be served."""
    threading.Thread(target=attack.silent_connection, args=(r.port, 4.0),
                     daemon=True).start()
    time.sleep(0.3)
    try:
        with modbus.Client(r.port, timeout=3.0) as client:
            client.request(modbus.read_input_registers(IR_LEVEL, 1))
    except (modbus.Refused, modbus.ModbusError):
        return "the operator was locked out for more than 3 seconds"
    return None


# --- Hostile traffic must not reach the station --------------------------------

@test(baseline=True)
def bad_protocol_id(r):
    attack.bad_protocol_id(r.port)
    settle()
    if r.plant.coils[COIL_PUMP]:
        return "the pump was started by a message that is not Modbus"
    return None


@test(baseline=True)
def oversized_frame(r):
    attack.oversized_frame(r.port)
    settle()
    return trip_unchanged(r)


@test()
def write_safety_register(r):
    attack.write_safety_register(r.port)
    settle()
    return trip_unchanged(r)


@test()
def write_across_boundary(r):
    attack.write_across_boundary(r.port)
    settle()
    return trip_unchanged(r)


@test()
def stop_controller(r):
    attack.stop_controller(r.port)
    settle()
    if not r.plant.running:
        return "the control program was stopped"
    return None


@test()
def smuggled_frame(r):
    attack.smuggled_frame(r.port)
    settle()
    return trip_unchanged(r)


@test()
def oversized_read(r):
    attack.oversized_read(r.port)
    settle()
    if r.plant.comms_faults:
        return "the controller's comms task crashed"
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--direct", action="store_true")
    parser.add_argument("--log", action="store_true")
    args = parser.parse_args()

    if not args.direct and not os.path.exists(WARDEN):
        sys.exit(f"{WARDEN} is missing. Run `alr build` first.")

    plant = plant_module.Plant()
    server = plant_module.make_server(plant, 0)
    plant_port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()

    print("station on its own (no proxy)" if args.direct
          else "station behind the proxy")
    passed = failed = 0
    for function, baseline in TESTS:
        if args.baseline and not baseline:
            continue
        plant.reset()
        r = Range(plant, plant_port, args.direct)
        try:
            problem = function(r)
        except OSError as error:
            problem = f"could not talk to the proxy ({error})"
        finally:
            r.close()

        if problem is None:
            passed += 1
            print(f"  PASS  {function.__name__}")
        else:
            failed += 1
            print(f"  FAIL  {function.__name__}: {problem}")
        if args.log:
            for line in r.log:
                print(f"          {line}")

    print(f"{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
