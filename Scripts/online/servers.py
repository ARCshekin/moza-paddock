"""Independent implementation of the public directory and Kunos INFO/JSON protocols."""
import json
import re
import time
from urllib.parse import urlsplit, parse_qs, urlencode
from urllib.request import Request, urlopen

DIRECTORY = 'https://acservers.online/servers'


def fetch(url, limit=2_000_000):
    request = Request(url, headers={'User-Agent': 'MozaPaddock/1.0', 'Accept': 'application/json,text/html'})
    with urlopen(request, timeout=10) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Слишком большой ответ сервера')
    return data.decode('utf-8')


def endpoint(address):
    address = address.strip()
    if any(ord(c) < 32 or ord(c) == 127 for c in address):
        raise ValueError('Некорректный адрес сервера')
    parsed = urlsplit(address if '://' in address else 'http://' + address)
    if parsed.scheme in ('acmanager', 'https') and parsed.query:
        query = parse_qs(parsed.query)
        if 'ip' in query and 'httpPort' in query:
            return endpoint(query['ip'][0] + ':' + query['httpPort'][0])
    if parsed.scheme not in ('http', 'https') or parsed.username or parsed.password:
        raise ValueError('Введите адрес сервера и HTTP-порт: host:8081')
    host = parsed.hostname or ''
    if not re.fullmatch(r'[A-Za-z0-9.-]{1,253}', host):
        raise ValueError('Некорректный адрес сервера')
    port = 8081 if parsed.port is None else parsed.port
    if not 1 <= port <= 65535:
        raise ValueError('Некорректный HTTP-порт')
    return host, port


def directory_document(text):
    # Decode JSON string literals only; never execute the site's JavaScript.
    chunks = re.findall(r'__VINEXT_RSC_CHUNKS__\.push\(("(?:[^"\\]|\\.)*")\)', text)
    stream = ''.join(json.loads(chunk) for chunk in chunks)
    marker = '"initialResult":'
    if marker not in stream:
        raise ValueError('Каталог изменил формат ответа; используйте прямой адрес сервера')
    result, _ = json.JSONDecoder().raw_decode(stream.split(marker, 1)[1])
    entries = []
    for item in result.get('items', []):
        try:
            host, port = endpoint(item['joinUrl'])
        except (KeyError, ValueError):
            continue
        entries.append(dict(id=f'{host}:{port}', host=host, httpPort=port,
                            name=str(item.get('name', host)), track=str(item.get('track', '')),
                            clients=int(item.get('players', 0)), capacity=int(item.get('capacity', 0)),
                            password=bool(item.get('passwordProtected', False)),
                            csp=bool(item.get('cspRequired', False)),
                            online=item.get('status') == 'Online'))
    return dict(items=entries, total=int(result.get('total', 0)), page=int(result.get('page', 1)))


def directory(query='', page=1):
    return directory_document(fetch(DIRECTORY + '?' + urlencode({'q': query[:200], 'page': max(1, page)})))


def asset_id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_. -]{1,160}', value) or value in ('.', '..'):
        raise ValueError('Сервер сообщил некорректный идентификатор контента')
    return value


def inspect(address):
    host, port = endpoint(address)
    base = f'http://{host}:{port}'
    started = time.monotonic()
    info = json.loads(fetch(base + '/INFO', 256_000))
    latency = int((time.monotonic() - started) * 1000)
    race_port = int(info.get('tport', info.get('port', 0)))
    if not 1 <= race_port <= 65535:
        raise ValueError('Сервер не сообщил TCP-порт игры')
    cars = [asset_id(car) for car in info.get('cars', [])]
    raw_track = info.get('track', '')
    csp = bool(re.fullmatch(r'csp/\d+/\.\./[^/]+', raw_track))
    track = asset_id(raw_track.rsplit('/', 1)[-1] if csp else raw_track)
    # No account ID is needed for browsing free car slots.
    slots = json.loads(fetch(base + '/JSON|0', 256_000))
    free = {}
    for slot in slots.get('Cars', []):
        if not slot.get('IsConnected', False) and not slot.get('IsRequestedGUID', False):
            model = asset_id(slot.get('Model', ''))
            free[model] = free.get(model, 0) + 1
    return dict(host=host, httpPort=port, racePort=race_port, name=str(info.get('name', host)),
                track=track, cars=cars, free=free, clients=int(info.get('clients', 0)),
                capacity=int(info.get('maxclients', 0)), password=bool(info.get('pass', False)),
                pickup=bool(info.get('pickup', False)), csp=csp, latency=latency)
