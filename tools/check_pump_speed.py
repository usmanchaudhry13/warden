
import threading
import plant
import modbus
from gauntlet import Range

station = plant.Plant()
server = plant.make_server(station, 0)
threading.Thread(target=server.serve_forever, daemon=True).start()

cases = [
    ("Single write: 1000 allowed",
     modbus.write_single_register(0, 1000), True),
    ("Single write: 1001 blocked",
     modbus.write_single_register(0, 1001), False),
    ("Multiple write: 1000 allowed",
     modbus.write_multiple_registers(0, [1000]), True),
    ("Multiple write: 1001 blocked",
     modbus.write_multiple_registers(0, [1001]), False),
]

try:
    for name, request, should_allow in cases:
        station.reset()
        with station.lock:
            station.holding[plant.HR_PUMP_SPEED] = 500

        proxy = Range(station, server.server_address[1], False)

        try:
            accepted = False
            try:
                with modbus.Client(proxy.port, timeout=3.0) as client:
                    client.request(request)
                accepted = True
            except (modbus.Refused, modbus.ModbusError):
                pass

            actual_speed = station.holding[plant.HR_PUMP_SPEED]
            expected_speed = 1000 if should_allow else 500

            passed = (accepted == should_allow
                      and actual_speed == expected_speed)

            print(("PASS" if passed else "FAIL"), name)
        finally:
            proxy.close()
finally:
    server.shutdown()
    server.server_close()