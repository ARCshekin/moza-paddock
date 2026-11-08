#!/usr/bin/env python3
"""Offline protocol tests with local HTTP fixtures; no accounts or game required."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from unittest.mock import patch
from online.servers import directory_document, endpoint, inspect, clear_session

item = dict(joinUrl='acmanager://race/online/join?ip=127.0.0.1&httpPort=8081',
            name='Test', track='Magione', players=1, capacity=12, status='Online')
result = {'items': [item], 'total': 1, 'page': 2}
stream = '1:["$","view",null,{"initialResult":' + json.dumps(result) + '}]'
html = '<script>self.__VINEXT_RSC_CHUNKS__.push(' + json.dumps(stream) + ')</script>'
parsed = directory_document(html)
assert parsed['page'] == 2 and parsed['items'][0]['id'] == '127.0.0.1:8081'
assert endpoint('https://acstuff.club/s/q:race/online/join?ip=example.com&httpPort=9090') == ('example.com', 9090)
for invalid in ('http://user:pass@example.com', 'file:///tmp/a', 'host:70000', 'host:0', 'host\nname:8081'):
    try:
        endpoint(invalid)
    except ValueError:
        pass
    else:
        raise AssertionError(invalid)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        if self.path == '/INFO':
            body = dict(name='Fixture', tport=9600, track='ks_nurburgring-layout_gp_a',
                        cars=['ks_audi_r8_plus'], clients=1, maxclients=3, pickup=True)
        elif self.path == '/JSON|0':
            body = {'Cars': [dict(Model='ks_audi_r8_plus', IsConnected=taken, IsRequestedGUID=reserved)
                             for taken, reserved in ((False, False), (True, False), (False, True))]}
        else:
            self.send_error(404); return
        data = json.dumps(body).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(data)

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = Thread(target=server.serve_forever, daemon=True); thread.start()
try:
    details = inspect(f'127.0.0.1:{server.server_port}')
    assert details['racePort'] == 9600 and details['httpPort'] == server.server_port
    assert details['free'] == {'ks_audi_r8_plus': 1}
    with patch('online.servers.fetch', return_value=json.dumps(dict(track='../escape', cars=[], tport=9600))):
        try: inspect('127.0.0.1:8081')
        except ValueError: pass
        else: raise AssertionError('unsafe track accepted')
finally:
    server.shutdown(); server.server_close(); thread.join()
print('PASS online: directory decoding, invites, bounded local INFO/JSON, reserved slots and input validation')

from pathlib import Path
from tempfile import TemporaryDirectory
with TemporaryDirectory() as root:
    cfg = Path(root) / 'cfg'; cfg.mkdir()
    race = cfg / 'race.ini'
    race.write_text('[REMOTE]\nACTIVE=1\nPASSWORD=secret\nGUID=76561198000000000\n[CAR_0]\nMODEL=test\n')
    clear_session(root)
    assert 'secret' not in race.read_text() and 'ACTIVE=0' in race.read_text() and 'MODEL=test' in race.read_text()
print('PASS online: launcher cleanup survives closing the native UI')
