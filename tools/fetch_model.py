#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Скачивание модели GigaAM v3 для DictaPro (task 019).

Качает 5 файлов модели (~222 МБ) и кладёт их в два места:
  1. assets/models/gigaam_v3_punct/          — flutter-ассеты (APK, прямая раздача)
  2. android/gigaam_pack/src/main/assets/models/gigaam_v3_punct/
     — install-time asset pack (AAB, Play)

Модель в git не коммитится (см. .gitignore); скрипт идемпотентен:
уже скачанные файлы с валидным размером пропускает.

Запуск из корня репозитория:
    python3 tools/fetch_model.py
    python tools\\fetch_model.py   (Windows)
"""

import os
import shutil
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HF_BASE = (
    "https://huggingface.co/csukuangfj/"
    "sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16"
    "/resolve/main"
)
VAD_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
    "asr-models/silero_vad.onnx"
)

# (имя файла, url, минимальный валидный размер в байтах)
# Пороги чуть ниже фактических (~214 МБ / 4,4 МБ / 2,6 МБ / <1 МБ / 0,6 МБ),
# чтобы ловить оборванные закачки, а не отличия редакций модели.
FILES = [
    ("encoder.int8.onnx", f"{HF_BASE}/encoder.int8.onnx", 190 * 1024 * 1024),
    ("decoder.onnx", f"{HF_BASE}/decoder.onnx", 3 * 1024 * 1024),
    ("joiner.onnx", f"{HF_BASE}/joiner.onnx", 1 * 1024 * 1024),
    ("tokens.txt", f"{HF_BASE}/tokens.txt", 10 * 1024),
    ("silero_vad.onnx", VAD_URL, 500 * 1024),
]

DEST_DIRS = [
    os.path.join(ROOT, "assets", "models", "gigaam_v3_punct"),
    os.path.join(
        ROOT, "android", "gigaam_pack", "src", "main", "assets",
        "models", "gigaam_v3_punct",
    ),
]

CHUNK = 1024 * 1024


def log(msg: str) -> None:
    print(f"[fetch_model] {msg}", flush=True)


def valid(path: str, min_size: int) -> bool:
    return os.path.isfile(path) and os.path.getsize(path) >= min_size


def download(name: str, url: str, dest: str, min_size: int) -> str:
    """Скачивает url → dest с докачкой и проверкой размера."""
    if valid(dest, min_size):
        log(f"{name}: уже есть ({os.path.getsize(dest):,} байт), пропуск")
        return dest
    tmp = dest + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": "dictapro-fetch"})
    with urllib.request.urlopen(req, timeout=60) as r, open(tmp, "wb") as f:
        done = 0
        while True:
            chunk = r.read(CHUNK)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            print(f"\r[fetch_model] {name}: {done / 1048576:6.1f} МБ", end="", flush=True)
    print()
    if not valid(tmp, min_size):
        size = os.path.getsize(tmp) if os.path.exists(tmp) else 0
        os.remove(tmp)
        raise RuntimeError(
            f"{name}: скачано {size:,} байт — меньше ожидаемых {min_size:,}. "
            "Проверь сеть и запусти скрипт снова."
        )
    os.replace(tmp, dest)
    log(f"{name}: готово, {os.path.getsize(dest):,} байт")
    return dest


def main() -> int:
    primary = DEST_DIRS[0]
    os.makedirs(primary, exist_ok=True)

    for name, url, min_size in FILES:
        download(name, url, os.path.join(primary, name), min_size)

    # Копия в asset pack для Play AAB.
    for other in DEST_DIRS[1:]:
        os.makedirs(other, exist_ok=True)
        for name, _url, _min in FILES:
            src = os.path.join(primary, name)
            dst = os.path.join(other, name)
            if not (os.path.isfile(dst) and os.path.getsize(dst) == os.path.getsize(src)):
                shutil.copy2(src, dst)
        log(f"копия обновлена: {os.path.relpath(other, ROOT)}")

    total = sum(
        os.path.getsize(os.path.join(primary, n)) for n, _, _ in FILES
    )
    log(f"ВСЁ ГОТОВО: 5 файлов, суммарно {total / 1048576:.1f} МБ")
    log("Теперь: APK  → python3 tools/prepare_apk_build.py && flutter build apk --release --split-per-abi")
    log("        AAB  → flutter build appbundle --release")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        log("прервано пользователем")
        sys.exit(130)
    except Exception as e:  # noqa: BLE001 — понятная ошибка сборщику
        log(f"ОШИБКА: {e}")
        sys.exit(1)
