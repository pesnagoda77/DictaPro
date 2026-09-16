# -*- coding: utf-8 -*-
"""Сборка AAB для Google Play: модель уходит ТОЛЬКО в пакет ресурсов, база остаётся лёгкой (<200 МБ).

Порядок: временно убираем файлы модели из flutter-ассетов -> собираем appbundle -> возвращаем обратно.
Файлы модели при этом остаются в android/gigaam_pack (install-time asset pack).

Запуск:  python tools/play_aab.py        (из корня проекта)
Результат: build/app/outputs/bundle/release/app-release.aab
"""
import io, os, shutil, subprocess, sys

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(A, 'assets', 'models', 'gigaam_v3_punct')
HOLD = os.path.join(A, '.openclaw_model_hold')
KEEP = {'README.md', 'readme.md'}


def move_out():
    os.makedirs(HOLD, exist_ok=True)
    moved = []
    if not os.path.isdir(ASSETS):
        return moved
    for f in os.listdir(ASSETS):
        if f in KEEP:
            continue
        src = os.path.join(ASSETS, f)
        dst = os.path.join(HOLD, f)
        shutil.move(src, dst)
        moved.append(f)
    return moved


def move_back(moved):
    for f in moved:
        src = os.path.join(HOLD, f)
        if os.path.exists(src):
            shutil.move(src, os.path.join(ASSETS, f))
    if os.path.isdir(HOLD) and not os.listdir(HOLD):
        os.rmdir(HOLD)


def main():
    moved = move_out()
    print('временно убрано из ассетов: %d файлов (модель остаётся в пакете gigaam_pack)' % len(moved))
    try:
        r = subprocess.run([r'C:\flutter\bin\flutter.bat', 'build', 'appbundle', '--release'], cwd=A, shell=True)
        print('сборка завершена, код:', r.returncode)
        return r.returncode
    finally:
        move_back(moved)
        print('файлы модели возвращены в ассеты (для сборки APK прямой раздачи)')


if __name__ == '__main__':
    sys.exit(main())
