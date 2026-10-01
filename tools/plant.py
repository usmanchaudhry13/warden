#!/usr/bin/env python3
"""The pumping station: a tank, a pump, a valve, and their controller.

    python3 tools/plant.py

Listens for Modbus/TCP on port 5020 and prints the state of the station
once per second. The register map is in docs/PLANT.md.

This controller is trusting and sloppy ON PURPOSE, like a lot of equipment
in the field: it obeys anyone, it never checks who is asking, and some
malformed requests upset it. Do not fix it. The project is the proxy that
stands in front of it.
"""

import argparse
import socketserver
import struct
import threading
import time

import modbus

# Register map (docs/PLANT.md).
COIL_PUMP, COIL_VALVE = 0, 1
DI_HIGH_ALARM, DI_OVERFLOW = 0, 1
IR_LEVEL, IR_INFLOW, IR_OUTFLOW = 0, 1, 2
HR_PUMP_SPEED = 0
HR_HIGH_TRIP = 10
HOLDING_COUNT = 16

STOP_CONTROLLER = 0x5A     # vendor function: halt the control program

PUMP_RATE = 2.0            # % of tank per second at full speed
VALVE_RATE = 1.5           # % of tank per second when open


class Plant:
    def __init__(self):
        self.lock = threading.Lock()
        self.reset()

    def reset(self):
        with self.lock:
            self.level = 50.0                      # % of the tank
            self.coils = [False, True]             # pump off, valve open
            self.holding = [0] * HOLDING_COUNT
            self.holding[HR_PUMP_SPEED] = 1000     # 100.0 %
            self.holding[HR_HIGH_TRIP] = 900       # 90.0 %
            self.running = True                    # control program alive
            self.overflowed = False
            self.comms_faults = 0
            self.requests = 0                      # requests executed
            self.events = []

    def say(self, text):
        self.events.append(text)

    # --- Process: called 10 times per second ---------------------------------

    def step(self, dt):
        with self.lock:
            inflow = (PUMP_RATE * self.holding[HR_PUMP_SPEED] / 1000.0
                      if self.coils[COIL_PUMP] else 0.0)
            outflow = (VALVE_RATE
                       if self.coils[COIL_VALVE] and self.level > 0 else 0.0)
            self.level = max(0.0, self.level + (inflow - outflow) * dt)

            # Safety interlock: part of the control program.
            trip = self.holding[HR_HIGH_TRIP] / 10.0
            if self.running and self.level >= trip and self.coils[COIL_PUMP]:
                self.coils[COIL_PUMP] = False
                self.say(f"interlock: level reached {trip:.1f}%, pump stopped")

            if self.level >= 100.0:
                self.level = 100.0
                if not self.overflowed:
                    self.overflowed = True
                    self.say("*** OVERFLOW: water on the floor ***")

    def status(self):
        with self.lock:
            return (f"level {self.level:5.1f}%  "
                    f"pump {'ON ' if self.coils[COIL_PUMP] else 'OFF'}  "
                    f"valve {'OPEN  ' if self.coils[COIL_VALVE] else 'CLOSED'}"
                    f"  trip {self.holding[HR_HIGH_TRIP] / 10:.1f}%"
                    f"{'' if self.running else '  CONTROLLER STOPPED'}"
                    f"{'  OVERFLOW' if self.overflowed else ''}")

    # --- Modbus: one request in, one answer out --------------------------------

    def execute(self, pdu):
        """Answer PDU for a request PDU. Raises CommsFault on a crash."""
        with self.lock:
            self.requests += 1
            function = pdu[0]

            def error(code):
                return bytes([function | 0x80, code])

            def pack_bits(bits):
                out = bytearray((len(bits) + 7) // 8)
                for i, bit in enumerate(bits):
                    if bit:
                        out[i // 8] |= 1 << (i % 8)
                return bytes([function, len(out)]) + bytes(out)

            def pack_words(words):
                return (bytes([function, 2 * len(words)])
                        + b"".join(struct.pack(">H", w) for w in words))

            if function == STOP_CONTROLLER:
                self.running = False
                self.say("control program STOPPED by a network request")
                return bytes([function, 0])

            if len(pdu) < 5:
                return error(3)
            address, value = struct.unpack(">HH", pdu[1:5])

            if function in (1, 2, 3, 4):
                if value > 125:
                    # A real bug class: the firmware trusts the quantity.
                    self.comms_faults += 1
                    self.say("COMMS FAULT: a request crashed the comms task")
                    raise CommsFault()
                high = self.level >= self.holding[HR_HIGH_TRIP] / 10.0
                speed = self.holding[HR_PUMP_SPEED] / 1000.0
                table = {
                    1: self.coils,
                    2: [high, self.overflowed],
                    3: self.holding,
                    4: [round(self.level * 10),
                        round(PUMP_RATE * speed * 10)
                        if self.coils[COIL_PUMP] else 0,
                        round(VALVE_RATE * 10)
                        if self.coils[COIL_VALVE] else 0],
                }[function]
                if address + value > len(table) or value == 0:
                    return error(2)
                chosen = table[address:address + value]
                return pack_bits(chosen) if function < 3 else pack_words(chosen)

            if not self.running:
                return error(4)        # outputs frozen: writes fail

            if function == 5:
                if address >= len(self.coils):
                    return error(2)
                self.coils[address] = value == 0xFF00
                return pdu[:5]

            if function == 6:
                if address >= HOLDING_COUNT:
                    return error(2)
                self.holding[address] = value
                return pdu[:5]

            if function == 16:
                # Sloppy: writes what fits in the table, ignores the rest,
                # and never compares the count with the bytes it received.
                data = pdu[6:]
                for i in range(min(value, len(data) // 2)):
                    if address + i < HOLDING_COUNT:
                        self.holding[address + i], = struct.unpack(
                            ">H", data[2 * i:2 * i + 2])
                return pdu[:5]

            return error(1)


class CommsFault(Exception):
    pass


def make_server(plant, port):
    """Modbus/TCP server for `plant`. Port 0 picks a free port."""

    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            try:
                while True:
                    # Trusts the header: protocol and unit are not checked,
                    # and whatever follows a message is taken as the next one.
                    transaction, unit, pdu = modbus.receive_frame(self.request)
                    if not pdu:
                        continue
                    answer = plant.execute(pdu)
                    self.request.sendall(
                        modbus.frame(answer, transaction, unit))
            except (ConnectionError, OSError, CommsFault, struct.error):
                pass

    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True

    return Server((modbus.HOST, port), Handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=modbus.PLANT_PORT)
    args = parser.parse_args()

    plant = Plant()
    server = make_server(plant, args.port)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"plant: controller listening on port {args.port}", flush=True)

    try:
        tick = 0
        while True:
            time.sleep(0.1)
            plant.step(0.1)
            while plant.events:
                print("plant:", plant.events.pop(0), flush=True)
            tick += 1
            if tick % 10 == 0:
                print("plant:", plant.status(), flush=True)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
