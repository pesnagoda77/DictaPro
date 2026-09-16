#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Подготовка модели к APK-сборке DictaPro (task 019).

Для прямой раздачи (APK) модель кладётся в flutter-ассеты
(assets/models/gigaam_v3_punct/, см. pubspec.yaml). Для Play (AAB) она
идёт через install-time asset pack android/gigaam_pack и во flutter-ассетах
НЕ нужна — иначе base-часть AAB превысит лимит Play в 200 МБ.

Порядок:
  1. python3 tools/fetch_model.py                 (скачать модель, один раз)
  2. python3 tools/prepare_apk_build.py           (эта команда)
  3. flutter build apk --release --split-per-abi
  4. python3 tools/prepare_apk_build.py --clean   (убрать модель из ассетов
                                                   перед AAB-сборкой)

--clean обязателен перед `flutter build appbundle` — иначе модель попадёт
и в base AAB (отказ Play по размеру).
"""

import argparse
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PACK_DIR = os.path.join(
    ROOT, "android", "gigaam_pack", "src", "main", "assets",
    "models", "gigaam_v3_punct",
)
ASSETS_DIR = os.path.join(ROOT, "assets", "models", "gigaam_v3_punct")

FILES = [
    "encoder.int8.onnx",
    "decoder.onnx",
    "joiner.onnx",
    "tokens.txt",
    "silero_vad.onnx",
]


def log(msg: str) -> None:
    print(f"[prepare_apk_build] {msg}", flush=True)


def prepare() -> int:
    missing = [f for f in FILES if not os.path.isfile(os.path.join(PACK_DIR, f))]
    if missing:
        log("ОШИБКА: модель не скачана, нет файлов: " + ", ".join(missing))
        log("Сначала: python3 tools/fetch_model.py")
        return 1
    os.makedirs(ASSETS_DIR, exist_ok=True)
    for f in FILES:
        src = os.path.join(PACK_DIR, f)
        dst = os.path.join(ASSETS_DIR, f)
        if os.path.isfile(dst) and os.path.getsize(dst) == os.path.getsize(src):
            continue
        shutil.copy2(src, dst)
    total = sum(os.path.getsize(os.path.join(ASSETS_DIR, f)) for f in FILES)
    log(f"модель в ассетах ({total / 1048576:.1f} МБ) — можно собирать APK")
    return 0


def clean() -> int:
    removed = 0
    for f in FILES:
        p = os.path.join(ASSETS_DIR, f)
        if os.path.isfile(p):
            os.remove(p)
            removed += 1
    log(f"убрано {removed} файлов — можно собирать AAB (asset pack)")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--clean", action="store_true",
                    help="убрать модель из flutter-ассетов (перед AAB-сборкой)")
    args = ap.parse_args()
    sys.exit(clean() if args.clean else prepare())
