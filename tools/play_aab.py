# -*- coding: utf-8 -*-
"""Сборка AAB для Google Play: модели уходят ТОЛЬКО в пакет ресурсов, база остаётся лёгкой (<200 МБ).

Порядок: временно убираем файлы моделей из flutter-ассетов -> собираем appbundle -> возвращаем обратно.
Файлы моделей при этом остаются в android/gigaam_pack (fast-follow asset pack).

Запуск:  python tools/play_aab.py        (из корня проекта)
Результат: build/app/outputs/bundle/release/app-release.aab
"""
import io, os, shutil, subprocess, sys

A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_DIRS = {
    'gigaam': os.path.join(A, 'assets', 'models', 'gigaam_v3_punct'),
    'whisper': os.path.join(A, 'assets', 'models', 'whisper-small'),
}
HOLD = os.path.join(A, '.openclaw_model_hold')
KEEP = {'README.md', 'readme.md'}


def move_out():
    os.makedirs(HOLD, exist_ok=True)
    moved = []
    for tag, adir in MODEL_DIRS.items():
        if not os.path.isdir(adir):
            continue
        for f in os.listdir(adir):
            if f in KEEP:
                continue
            src = os.path.join(adir, f)
            dst = os.path.join(HOLD, tag + '__' + f)
            shutil.move(src, dst)
            moved.append(tag + '__' + f)
    return moved


def move_back(moved):
    for name in moved:
        tag, f = name.split('__', 1)
        src = os.path.join(HOLD, name)
        if os.path.exists(src):
            shutil.move(src, os.path.join(MODEL_DIRS[tag], f))
    if os.path.isdir(HOLD) and not os.listdir(HOLD):
        os.rmdir(HOLD)


def main():
    moved = move_out()
    print('временно убрано из ассетов: %d файлов (модели остаются в пакете gigaam_pack)' % len(moved))
    try:
        r = subprocess.run([r'C:\flutter\bin\flutter.bat', 'build', 'appbundle', '--release'] + sys.argv[1:], cwd=A, shell=True)
        print('сборка завершена, код:', r.returncode)
        return r.returncode
    finally:
        move_back(moved)
        print('файлы моделей возвращены в ассеты (для сборки APK прямой раздачи)')


if __name__ == '__main__':
    sys.exit(main())
