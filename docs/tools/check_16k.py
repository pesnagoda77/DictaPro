# -*- coding: utf-8 -*-
"""Проверка требования Google Play: 16 КБ страницы памяти (p_align >= 0x4000)
для всех нативных библиотек в APK."""
import struct, sys, zipfile

APK = sys.argv[1]
z = zipfile.ZipFile(APK)
libs = [n for n in z.namelist() if n.endswith('.so')]
if not libs:
    print('нативных библиотек нет')
    sys.exit(0)


def load_aligns(data):
    if data[:4] != b'\x7fELF':
        return None
    is64 = data[4] == 2
    if not is64:
        return None
    e_phoff = struct.unpack_from('<Q', data, 0x20)[0]
    e_phentsize = struct.unpack_from('<H', data, 0x36)[0]
    e_phnum = struct.unpack_from('<H', data, 0x38)[0]
    out = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from('<I', data, off)[0]
        if p_type != 1:  # PT_LOAD
            continue
        p_align = struct.unpack_from('<Q', data, off + 48)[0]
        out.append(p_align)
    return out


print('APK:', APK)
bad = []
for name in sorted(libs):
    data = z.read(name)
    al = load_aligns(data)
    if al is None:
        print('%-46s не ELF64 — пропуск' % name[-46:])
        continue
    worst = min(al)
    ok = worst >= 0x4000
    print('%-46s p_align min = 0x%X (%s)' % (name[-46:], worst, 'OK 16 КБ' if ok else 'НЕ ПРОХОДИТ'))
    if not ok:
        bad.append(name)
print()
print('ИТОГ:', 'все библиотеки совместимы с 16 КБ' if not bad else ('НЕ ПРОХОДЯТ: ' + ', '.join(bad)))
