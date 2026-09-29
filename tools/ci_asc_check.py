# -*- coding: utf-8 -*-
"""CI: проверка App Store Connect (apps / bundleIds / builds).

Env: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER
Запуск на раннере (ubuntu): python3 tools/ci_asc_check.py
"""
import base64, json, os, subprocess, sys, time, urllib.request, urllib.error

KEY = os.environ.get('ASC_KEY_PATH', '/tmp/AuthKey.p8')
KEY_ID = os.environ.get('ASC_KEY_ID', '')
ISSUER = os.environ.get('ASC_ISSUER', '')


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def der_to_raw(der: bytes) -> bytes:
    i = 1
    assert der[0] == 0x30, 'не DER'
    if der[i] & 0x80:
        i += 1 + (der[i] & 0x7f)
    else:
        i += 1
    out = []
    for _ in range(2):
        i += 1
        ln = der[i]
        i += 1
        v = der[i:i + ln].lstrip(b'\x00')
        i += ln
        out.append(v.rjust(32, b'\x00'))
    return out[0] + out[1]


def jwt() -> str:
    now = int(time.time())
    h = {'alg': 'ES256', 'kid': KEY_ID, 'typ': 'JWT'}
    p = {'iss': ISSUER, 'iat': now, 'exp': now + 900, 'aud': 'appstoreconnect-v1'}
    si = (b64(json.dumps(h, separators=(',', ':')).encode()) + '.' +
          b64(json.dumps(p, separators=(',', ':')).encode())).encode()
    r = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', KEY, '-binary'],
                       input=si, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError('openssl: ' + r.stderr.decode()[:300])
    return si.decode() + '.' + b64(der_to_raw(r.stdout))


def api(method: str, path: str):
    rq = urllib.request.Request(
        'https://api.appstoreconnect.apple.com' + path, method=method,
        headers={'Authorization': 'Bearer ' + jwt(), 'Accept': 'application/json'})
    try:
        with urllib.request.urlopen(rq, timeout=90) as resp:
            return json.loads(resp.read().decode()), resp.status
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode() or '{}'), e.code


def main() -> int:
    print('=== /v1/apps ===')
    d, c = api('GET', '/v1/apps?limit=50')
    print('HTTP', c)
    if c != 200:
        print(json.dumps(d, ensure_ascii=False)[:500])
        return 1
    for a in d.get('data', []):
        at = a['attributes']
        print(f"APP id={a['id']} bundle={at.get('bundleId')} name={at.get('name')} locale={at.get('primaryLocale')}")

    print('=== /v1/bundleIds ===')
    d2, c2 = api('GET', '/v1/bundleIds?limit=50')
    print('HTTP', c2)
    for b in d2.get('data', []):
        bt = b['attributes']
        print(f"BID id={b['id']} ident={bt.get('identifier')} platform={bt.get('platform')}")

    if d.get('data'):
        aid = d['data'][0]['id']
        print('=== TestFlight builds ===')
        d3, c3 = api('GET', f'/v1/builds?filter[app]={aid}&limit=10&sort=-uploadedDate')
        print('HTTP', c3)
        for b in d3.get('data', []):
            bt = b['attributes']
            print(f"BUILD v{bt.get('version')} state={bt.get('processingState')} uploaded={bt.get('uploadedDate')}")
        if not d3.get('data'):
            print('(сборок TestFlight нет)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
