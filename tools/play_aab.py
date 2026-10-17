# -*- coding: utf-8 -*-
"""Сборка AAB для Google Play (task 108).

Task 108: asset pack gigaam_pack убран — модели (GigaAM v3 + Whisper)
всегда в base через flutter-ассеты. Модели никуда не перекладываются:
AAB собирается как есть, Play отдаёт всё при установке.

Запуск:  python tools/play_aab.py        (из корня проекта)
Результат: build/app/outputs/bundle/release/app-release.aab
"""
import os
import subprocess
import sys

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    print('сборка AAB: модели в base (asset pack убран, task 108)')
    r = subprocess.run(
        [r'C:\flutter\bin\flutter.bat', 'build', 'appbundle', '--release'] + sys.argv[1:],
        cwd=A, shell=True,
    )
    print('сборка завершена, код:', r.returncode)
    return r.returncode


if __name__ == '__main__':
    sys.exit(main())
