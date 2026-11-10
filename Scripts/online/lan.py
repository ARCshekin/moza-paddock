"""Bounded AC LAN discovery: UDP query 200, then verified INFO/JSON.
Protocol reference: Content Manager KunosApiProvider.Lan.cs (gro-ove/actools).
"""
import concurrent.futures
import ipaddress
import select
import socket
import struct
import time
from .servers import inspect


def parse_ports(value):
    result = set()
    for part in value.split(','):
        bounds = part.strip().split('-')
        if len(bounds) not in (1, 2) or not all(x.isdigit() for x in bounds):
            raise ValueError('Порты: например, 9600-9610 или 9600,19600')
        first, last = int(bounds[0]), int(bounds[-1])
        if not 1024 <= first <= last <= 65535 or last - first > 63:
            raise ValueError('Не больше 64 игровых UDP-портов в диапазоне 1024–65535')
        result.update(range(first, last + 1))
        if len(result) > 64:
            raise ValueError('Не больше 64 игровых UDP-портов за поиск')
    return sorted(result)


def decode_reply(data, host):
    address = ipaddress.IPv4Address(host)
    if len(data) != 3 or data[0] != 200 or address.is_unspecified or address.is_multicast or address.is_global:
        return None
    port = struct.unpack_from('<H', data, 1)[0]
    return (str(address), port) if port else None


def discover(ports='9600-9610', targets=None, timeout=1.0):
    ports = parse_ports(ports)
    targets = targets or ['127.0.0.1', '255.255.255.255']
    if len(targets) > 32:
        raise ValueError('Слишком много сетевых интерфейсов')
    targets = sorted({str(ipaddress.IPv4Address(x)) for x in targets})
    found = set()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        probe.bind(('0.0.0.0', 0))
        for host in targets:
            for port in ports:
                try:
                    probe.sendto(struct.pack('<I', 200), (host, port))
                except OSError:
                    continue
        deadline = time.monotonic() + min(2.0, max(0.1, timeout))
        while len(found) < 16:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([probe], [], [], remaining)[0]:
                break
            data, peer = probe.recvfrom(1024)
            reply = decode_reply(data, peer[0])
            if reply:
                found.add(reply)
    def verify(endpoint):
        host, port = endpoint
        try:
            info = inspect(f'{host}:{port}')
            return dict(id=f'{host}:{port}', host=host, httpPort=port, name=info['name'], track=info['track'],
                        clients=info['clients'], capacity=info['capacity'], password=info['password'], csp=info['csp'], online=True)
        except Exception:
            return None
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        rows = [row for row in pool.map(verify, sorted(found)) if row]
    rows.sort(key=lambda row: (row['name'].casefold(), row['id']))
    return dict(items=rows, total=len(rows), page=1)
