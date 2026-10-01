#!/usr/bin/env python3
"""The operator's workstation: watches the tank and runs the pump.

    python3 tools/workstation.py                # through the proxy (port 5021)
    python3 tools/workstation.py --port 5020    # straight to the controller

Once per second it reads the level and keeps it between 40 % and 60 %:
pump on below 40, pump off above 60. That is all an honest operator does
here, and it is the traffic the proxy must never break.
"""

import argparse
import time

import modbus
from plant import COIL_PUMP, IR_LEVEL

LOW, HIGH = 40.0, 60.0


def read_level(client):
    return client.words(modbus.read_input_registers(IR_LEVEL, 1))[0] / 10.0


def read_pump(client):
    return client.bits(modbus.read_coils(COIL_PUMP, 1), 1)[0]


def set_pump(client, on):
    client.request(modbus.write_single_coil(COIL_PUMP, on))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=modbus.WARDEN_PORT)
    args = parser.parse_args()

    print(f"operator: talking to port {args.port}", flush=True)
    try:
        while True:
            # One short connection per round, like many supervision screens.
            try:
                with modbus.Client(args.port) as client:
                    level = read_level(client)
                    pump = read_pump(client)
                    action = ""
                    if level < LOW and not pump:
                        set_pump(client, True)
                        action = "  -> pump ON"
                    elif level > HIGH and pump:
                        set_pump(client, False)
                        action = "  -> pump OFF"
                print(f"operator: level {level:5.1f}%  "
                      f"pump {'ON ' if pump else 'OFF'}{action}", flush=True)
            except modbus.Refused:
                print("operator: NO ANSWER", flush=True)
            except modbus.ModbusError as error:
                print(f"operator: COMMAND FAILED ({error})", flush=True)
            time.sleep(1.0)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
