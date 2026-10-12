# -*- coding: utf-8 -*-
"""CI: загрузка AAB в Google Play (edits -> bundles -> track -> commit).

Env: PLAY_JSON_PATH, AAB_PATH, TRACK (internal/alpha/beta/production), RELEASE_NOTES, PACKAGE
"""
import base64, http.client, json, os, sys, time, urllib.request, urllib.error
import urllib.parse

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

PKG = os.environ.get('PACKAGE', 'com.dictapro.app')
TRACK = os.environ.get('TRACK', 'internal')
AAB = os.environ.get('AAB_PATH', '/tmp/app.aab')
KEYF = os.environ.get('PLAY_JSON_PATH', '/tmp/play.json')
NOTES = os.environ.get('RELEASE_NOTES', '')

BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3'
UP = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3'


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()


def token():
    key = json.load(open(KEYF, encoding='utf-8'))
    now = int(time.time())
    h = b64url(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode())
    c = b64url(json.dumps({'iss': key['client_email'],
                           'scope': 'https://www.googleapis.com/auth/androidpublisher',
                           'aud': 'https://oauth2.googleapis.com/token',
                           'exp': now + 3600, 'iat': now}).encode())
    si = (h + '.' + c).encode()
    priv = serialization.load_pem_private_key(key['private_key'].encode(), password=None)
    sig = priv.sign(si, padding.PKCS1v15(), hashes.SHA256())
    jwt = si.decode() + '.' + b64url(sig)
    data = ('grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=' + jwt).encode()
    rq = urllib.request.Request('https://oauth2.googleapis.com/token', data=data,
                                headers={'Content-Type': 'application/x-www-form-urlencoded'})
    with urllib.request.urlopen(rq, timeout=60) as r:
        return json.loads(r.read().decode())['access_token']


def call(at, url, method='GET', body=None, ctype='application/json'):
    data = json.dumps(body).encode() if body is not None else None
    rq = urllib.request.Request(url, data=data, method=method,
                                headers={'Authorization': 'Bearer ' + at, 'Content-Type': ctype})
    try:
        with urllib.request.urlopen(rq, timeout=300) as r:
            b = r.read()
            return (json.loads(b) if b else {}), r.status
    except urllib.error.HTTPError as e:
        return {'error': e.read().decode()[:800]}, e.code


def main() -> int:
    size = os.path.getsize(AAB)
    print(f'AAB: {AAB} ({size / 1048576:.1f} МБ); track={TRACK}')
    at = token()
    print('токен получен')

    ed, code = call(at, f'{BASE}/applications/{PKG}/edits', 'POST', {})
    print('create edit:', code, ed.get('id') if code < 300 else ed)
    if code >= 300:
        return 1
    eid = ed['id']

    # resumable upload
    start = f'{UP}/applications/{PKG}/edits/{eid}/bundles?uploadType=resumable'
    rq = urllib.request.Request(start, data=b'{}', method='POST', headers={
        'Authorization': 'Bearer ' + at,
        'Content-Type': 'application/json',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': str(size)})
    try:
        with urllib.request.urlopen(rq, timeout=120) as r:
            loc = r.headers.get('Location')
            st = r.status
    except urllib.error.HTTPError as e:
        print('start upload: HTTP', e.code, e.read().decode()[:800])
        return 1
    print('upload session:', st, 'Location получен')

    u = urllib.parse.urlparse(loc)
    conn = http.client.HTTPSConnection(u.netloc, timeout=1200)
    path = u.path + ('?' + u.query if u.query else '')
    with open(AAB, 'rb') as f:
        conn.putrequest('PUT', path)
        conn.putheader('Content-Type', 'application/octet-stream')
        conn.putheader('Content-Length', str(size))
        conn.endheaders()
        sent = 0
        while True:
            chunk = f.read(4 * 1024 * 1024)
            if not chunk:
                break
            conn.send(chunk)
            sent += len(chunk)
            print(f'\r  загружено {sent / 1048576:6.1f} / {size / 1048576:.1f} МБ', end='', flush=True)
    resp = conn.getresponse()
    body = resp.read().decode()
    print()
    print('bundle upload: HTTP', resp.status)
    if resp.status >= 300:
        print(body[:800])
        return 1
    b = json.loads(body)
    vc = b.get('versionCode')
    print('versionCode:', vc)

    rel = {'status': 'completed', 'versionCodes': [str(vc)]}
    if NOTES:
        rel['releaseNotes'] = [{'language': 'ru-RU', 'text': NOTES},
                               {'language': 'en-US', 'text': NOTES}]
    tr, code = call(at, f'{BASE}/applications/{PKG}/edits/{eid}/tracks/{TRACK}', 'PUT',
                    {'track': TRACK, 'releases': [rel]})
    print('track update:', code, '' if code < 300 else tr)

    cm, code = call(at, f'{BASE}/applications/{PKG}/edits/{eid}:commit', 'POST', {})
    print('commit:', code)
    print('ГОТОВО' if code < 300 else str(cm)[:600])
    return 0 if code < 300 else 1


if __name__ == '__main__':
    sys.exit(main())
