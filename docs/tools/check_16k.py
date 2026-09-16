#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Проверка требования Google Play о 16-килобайтных страницах памяти (task 019).

Сканирует нативные библиотеки (.so) в APK/AAB (или отдельный файл/папку)
и проверяет выравнивание LOAD-сегментов: p_align должен быть ≥ 0x4000 (16 КБ).
Старый движок (libvosk.so) этому требованию НЕ соответствовал (p_align=0x1000)
— одна из причин его удаления.

Запуск:
    python3 docs/tools/check_16k.py build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
    python3 docs/tools/check_16k.py build/app/outputs/bundle/release/app-release.aab
    python3 docs/tools/check_16k.py path/to/lib.so
"""

import struct
import sys
import zipfile

PT_LOAD = 1
REQUIRED_ALIGN = 0x4000  # 16 КБ


def check_elf(data: bytes, name: str) -> bool:
    if data[:4] != b"\x7fELF":
        print(f"  SKIP {name}: не ELF-файл")
        return True
    ei_class = data[4]  # 1 = 32-бит, 2 = 64-бит
    if ei_class == 2:
        # 64-бит ELF: program headers после e_phoff (u64), p_align = offset 48
        e_phoff = struct.unpack_from("<Q", data, 32)[0]
        e_phentsize = struct.unpack_from("<H", data, 54)[0]
        e_phnum = struct.unpack_from("<H", data, 56)[0]
        min_align = None
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type = struct.unpack_from("<I", data, off)[0]
            if p_type != PT_LOAD:
                continue
            p_align = struct.unpack_from("<Q", data, off + 48)[0]
            min_align = p_align if min_align is None else min(min_align, p_align)
    else:
        # 32-бит ELF: p_align = offset 28
        e_phoff = struct.unpack_from("<I", data, 28)[0]
        e_phentsize = struct.unpack_from("<H", data, 42)[0]
        e_phnum = struct.unpack_from("<H", data, 44)[0]
        min_align = None
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type = struct.unpack_from("<I", data, off)[0]
            if p_type != PT_LOAD:
                continue
            p_align = struct.unpack_from("<I", data, off + 28)[0]
            min_align = p_align if min_align is None else min(min_align, p_align)

    if min_align is None:
        print(f"  ??   {name}: LOAD-сегменты не найдены")
        return True
    ok = min_align >= REQUIRED_ALIGN
    status = "OK " if ok else "FAIL"
    print(f"  {status} {name}: min p_align = {min_align:#x}")
    return ok


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    target = sys.argv[1]

    names = []
    if target.endswith((".apk", ".aab")):
        with zipfile.ZipFile(target) as z:
            names = [n for n in z.namelist() if n.endswith(".so")]
        print(f"{len(names)} .so в {target}")
        all_ok = True
        with zipfile.ZipFile(target) as z:
            for n in sorted(names):
                all_ok &= check_elf(z.read(n), n)
    elif target.endswith(".so"):
        with open(target, "rb") as f:
            all_ok = check_elf(f.read(), target)
    else:
        print("Укажите .apk, .aab или .so")
        return 2

    if all_ok:
        print("Все библиотеки совместимы с 16 КБ.")
        return 0
    print("ЕСТЬ БИБЛИОТЕКИ, НЕ СОВМЕСТИМЫЕ С 16 КБ.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
