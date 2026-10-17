#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Проверка наличия моделей перед сборкой DictaPro (task 108).

Task 108: asset pack gigaam_pack убран — модели (GigaAM v3 + Whisper)
всегда лежат в flutter-ассетах (assets/models/...). APK и AAB собираются
из одного и того же состояния, без перекладывания файлов.

Этот скрипт — просто верификатор: проверяет, что все файлы моделей
скачаны (см. tools/fetch_model.py), и сообщает, можно ли собирать.

Запуск из корня репозитория:
    python3 tools/prepare_apk_build.py
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ASSETS_DIR = os.path.join(ROOT, "assets", "models", "gigaam_v3_punct")
WHISPER_DIR = os.path.join(ROOT, "assets", "models", "whisper-small")

# (каталог, имя файла, минимальный валидный размер в байтах)
FILES = [
    (ASSETS_DIR, "encoder.int8.onnx", 190 * 1024 * 1024),
    (ASSETS_DIR, "decoder.onnx", 3 * 1024 * 1024),
    (ASSETS_DIR, "joiner.onnx", 1 * 1024 * 1024),
    (ASSETS_DIR, "tokens.txt", 10 * 1024),
    (ASSETS_DIR, "silero_vad.onnx", 500 * 1024),
    (WHISPER_DIR, "small-encoder.int8.onnx", 100 * 1024 * 1024),
    (WHISPER_DIR, "small-decoder.int8.onnx", 200 * 1024 * 1024),
    (WHISPER_DIR, "small-tokens.txt", 10 * 1024),
]


def log(msg: str) -> None:
    print(f"[prepare_apk_build] {msg}", flush=True)


def main() -> int:
    missing = []
    for d, name, min_size in FILES:
        p = os.path.join(d, name)
        if not os.path.isfile(p) or os.path.getsize(p) < min_size:
            missing.append(os.path.relpath(p, ROOT))
    if missing:
        log("ОШИБКА: модели не скачаны или биты:")
        for m in missing:
            log("  - " + m)
        log("Сначала: python3 tools/fetch_model.py")
        return 1
    total = sum(os.path.getsize(os.path.join(d, n)) for d, n, _ in FILES)
    log(f"модели на месте ({total / 1048576:.1f} МБ) — можно собирать APK и AAB")
    log("APK  → flutter build apk --release --split-per-abi")
    log("AAB  → flutter build appbundle --release")
    return 0


if __name__ == "__main__":
    sys.exit(main())
