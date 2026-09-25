# -*- coding: utf-8 -*-
"""Проверка: нет ли секретов в ассетах и исходниках приложения (перед релизной сборкой).

Запуск:  python tools/check_no_secrets.py <путь к проекту>
Выход:   0 — чисто, 1 — найдены секреты (сборку не делать).
"""
import os
import re
import sys

PATTERNS = [
    ('Cloudflare-токен', re.compile(rb'cfut_[A-Za-z0-9_\-]{20,}')),
    ('OpenAI-подобный ключ', re.compile(rb'sk-[A-Za-z0-9]{20,}')),
    ('Google API-ключ', re.compile(rb'AIza[0-9A-Za-z\-_]{20,}')),
    ('GitHub-токен', re.compile(rb'gh[pousr]_[A-Za-z0-9]{20,}')),
    ('Приватный ключ', re.compile(rb'-----BEGIN [A-Z ]*PRIVATE KEY-----')),
    ('Общий sync-ключ (нужен ключ на устройство)', re.compile(rb'"(?:sync_key|syncKey)"\s*:\s*"[0-9a-fA-F]{16,}"')),

]

SCAN_DIRS = ['assets', 'lib', 'android/app/src', 'ios/Runner']
SKIP_EXT = {'.png', '.jpg', '.jpeg', '.webp', '.ttf', '.otf', '.onnx', '.wav', '.mp3', '.aab', '.apk', '.ipa'}
ALLOW_NAMES = {'google-services.json'}  # клиентский конфиг Firebase — допустим


def scan(root):
    bad = []
    for sub in SCAN_DIRS:
        d = os.path.join(root, sub)
        if not os.path.isdir(d):
            continue
        for dp, dn, fn in os.walk(d):
            dn[:] = [x for x in dn if x not in ('build', '.dart_tool', 'Pods', '.git')]
            for f in fn:
                p = os.path.join(dp, f)
                if os.path.splitext(f)[1].lower() in SKIP_EXT:
                    continue
                if f in ALLOW_NAMES:
                    continue
                try:
                    if os.path.getsize(p) > 2_000_000:
                        continue
                    data = open(p, 'rb').read()
                except Exception:
                    continue
                for name, pat in PATTERNS:
                    if pat.search(data):
                        bad.append((p, name))
    return bad


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    bad = scan(root)
    if not bad:
        print('OK: секретов в ассетах и исходниках не найдено (%s)' % root)
        return 0
    print('НАЙДЕНЫ СЕКРЕТЫ — релизную сборку не делать:')
    for p, name in bad:
        print('  %s  <- %s' % (p, name))
    return 1


if __name__ == '__main__':
    sys.exit(main())
