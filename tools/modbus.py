"""Modbus/TCP on the laptop side: build messages, send them, read answers.

Standard library only. Shared by the plant, the operator, the attacks and
the gauntlet. The wire format is described in docs/MODBUS.md.
"""

import socket
import struct

HOST = "127.0.0.1"
PLANT_PORT = 5020      # the controller
WARDEN_PORT = 5021     # the proxy

HEADER = struct.Struct(">HHHB")   # transaction, protocol, length, unit


# --- Requests (the PDU: function code + data) -------------------------------

def read_coils(address, quantity):
    return struct.pack(">BHH", 1, address, quantity)


def read_discrete_inputs(address, quantity):
    return struct.pack(">BHH", 2, address, quantity)


def read_holding_registers(address, quantity):
    return struct.pack(">BHH", 3, address, quantity)


def read_input_registers(address, quantity):
    return struct.pack(">BHH", 4, address, quantity)


def write_single_coil(address, on):
    return struct.pack(">BHH", 5, address, 0xFF00 if on else 0x0000)


def write_single_register(address, value):
    return struct.pack(">BHH", 6, address, value)


def write_multiple_registers(address, values):
    # The byte count field is one byte: with more than 127 values it cannot
    # be right. The mask lets attacks build such a message anyway.
    return (struct.pack(">BHHB", 16, address, len(values),
                        (2 * len(values)) & 0xFF)
            + b"".join(struct.pack(">H", v) for v in values))


# --- Framing -----------------------------------------------------------------

def frame(pdu, transaction=1, unit=1, protocol=0, length=None):
    """Header + PDU. `protocol` and `length` can be forced, to build lies."""
    if length is None:
        length = len(pdu) + 1
    return HEADER.pack(transaction, protocol, length, unit) + pdu


def receive_exactly(sock, count):
    data = b""
    while len(data) < count:
        piece = sock.recv(count - len(data))
        if not piece:
            raise ConnectionError("connection closed")
        data += piece
    return data


def receive_frame(sock):
    """One whole message from a stream: (transaction, unit, pdu)."""
    transaction, _protocol, length, unit = HEADER.unpack(
        receive_exactly(sock, HEADER.size))
    return transaction, unit, receive_exactly(sock, length - 1)


class Refused(Exception):
    """No usable answer: the connection was closed or stayed silent."""


class ModbusError(Exception):
    """The other side answered with a Modbus exception code."""


class Client:
    """A well-behaved Modbus/TCP client."""

    def __init__(self, port, timeout=2.0):
        self.transaction = 0
        try:
            self.sock = socket.create_connection((HOST, port), timeout=timeout)
        except OSError as error:
            raise Refused(str(error)) from error

    def close(self):
        self.sock.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def send_raw(self, data):
        self.sock.sendall(data)

    def request(self, pdu):
        """Send one request, return the PDU of the answer."""
        self.transaction = (self.transaction + 1) & 0xFFFF
        try:
            self.sock.sendall(frame(pdu, self.transaction))
            _, _, answer = receive_frame(self.sock)
        except (OSError, ConnectionError, struct.error) as error:
            raise Refused(str(error)) from error
        if answer and answer[0] & 0x80:
            raise ModbusError(f"exception code {answer[1]}")
        return answer

    # Convenience readers, returning plain Python values.

    def bits(self, pdu, quantity):
        data = self.request(pdu)[2:]
        return [bool(data[i // 8] >> (i % 8) & 1) for i in range(quantity)]

    def words(self, pdu):
        data = self.request(pdu)[2:]
        return list(struct.unpack(f">{len(data) // 2}H", data))
