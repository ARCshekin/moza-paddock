#!/usr/bin/env python3
"""Real loopback UDP/HTTP fixtures only; no broadcast or live game."""
import http.server
import json
import socket
import struct
import threading
from online.lan import parse_ports, decode_reply, discover

assert parse_ports('9600-9602,9601') == [9600, 9601, 9602]
for invalid in ['1', '9600-9700', '9601-9600', 'bad', '65536', '9600;9601']:
    try:
        parse_ports(invalid)
        raise AssertionError('invalid port list accepted')
    except ValueError:
        pass
assert decode_reply(b'\xc8\xff\xff', '127.0.0.1') == ('127.0.0.1', 65535)
assert decode_reply(b'\xc8\x00\x00', '127.0.0.1') is None
assert decode_reply(b'\x01\x01\x01', '127.0.0.1') is None
assert decode_reply(b'\xc8\x01\x01', '8.8.8.8') is None

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/INFO':
            body = dict(tport=19600, name='LAN fixture', track='magione', cars=['lotus_elise_sc'],
                        clients=0, maxclients=2, pickup=True)
        elif self.path == '/JSON|0':
            body = dict(Cars=[dict(Model='lotus_elise_sc', IsConnected=False)] * 2)
        else:
            self.send_error(404); return
        encoded = json.dumps(body).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(encoded)
    def log_message(self, *args):
        pass

http = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=http.serve_forever, daemon=True).start()
probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
probe.bind(('127.0.0.1', 0)); probe.settimeout(2)
port = probe.getsockname()[1]
def reply():
    request, peer = probe.recvfrom(128)
    assert request == struct.pack('<I', 200)
    packet = struct.pack('<BH', 200, http.server_port)
    # Duplicate replies must create one row, and the HTTP port need not match UDP.
    probe.sendto(packet, peer); probe.sendto(packet, peer)
worker = threading.Thread(target=reply); worker.start()
try:
    result = discover(str(port), ['127.0.0.1'], timeout=0.2)
    assert result['total'] == 1
    assert result['items'][0]['httpPort'] == http.server_port
    assert result['items'][0]['name'] == 'LAN fixture' and result['items'][0]['capacity'] == 2
    assert result['items'][0]['content']['track'] == result['items'][0]['track']
    assert result['items'][0]['content']['cars'] == result['items'][0]['carNames']
finally:
    worker.join(timeout=2); probe.close(); http.shutdown(); http.server_close()
print('PASS LAN UDP protocol, unsigned HTTP ports, bounds, duplicate filtering and real INFO/JSON verification')
