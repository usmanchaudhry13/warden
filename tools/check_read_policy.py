
import threading
import plant
import modbus
from gauntlet import Range

station = plant.Plant()
server = plant.make_server(station, 0)
threading.Thread(target=server.serve_forever, daemon=True).start()

cases = [
    ("Coils: valid read", modbus.read_coils(0, 2), True),
    ("Coils: out of range", modbus.read_coils(1, 2), False),
    ("Coils: zero quantity", modbus.read_coils(0, 0), False),

    ("Discrete inputs: valid read",
     modbus.read_discrete_inputs(1, 1), True),
    ("Discrete inputs: out of range",
     modbus.read_discrete_inputs(2, 1), False),
    ("Discrete inputs: zero quantity",
     modbus.read_discrete_inputs(0, 0), False),

    ("Input registers: valid read",
     modbus.read_input_registers(0, 3), True),
    ("Input registers: out of range",
     modbus.read_input_registers(2, 2), False),
    ("Input registers: zero quantity",
     modbus.read_input_registers(0, 0), False),

    ("Holding registers: valid read",
     modbus.read_holding_registers(15, 1), True),
    ("Holding registers: out of range",
     modbus.read_holding_registers(15, 2), False),
    ("Holding registers: zero quantity",
     modbus.read_holding_registers(0, 0), False),
]

try:
    for name, request, should_allow in cases:
        station.reset()
        proxy = Range(station, server.server_address[1], False)

        try:
            accepted = False
            try:
                with modbus.Client(proxy.port, timeout=3.0) as client:
                    response = client.request(request)
                accepted = bool(response and response[0] == request[0])
            except (modbus.Refused, modbus.ModbusError):
                pass

            with station.lock:
                forwarded = station.requests

            expected_forwarded = 1 if should_allow else 0
            passed = (accepted == should_allow
                      and forwarded == expected_forwarded)

            print(("PASS" if passed else "FAIL"), name)
        finally:
            proxy.close()
finally:
    server.shutdown()
    server.server_close()
