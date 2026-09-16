# -*- coding: utf-8 -*-
"""iOS-подготовка Flutter-проекта: иконки, экран запуска, манифест приватности Apple.

Использование:
    python ios_prepare.py "<путь к проекту>" --name "Руна Судьбы" [--icon <png>] [--bg #12141a] [--accent #e0a03c]

Что делает:
 1. Иконки приложения для iOS из источника (--icon) или из android-иконки xxxhdpi (увеличение с резкостью).
 2. Прозрачный LaunchImage + тёмный фон экрана запуска (правка LaunchScreen.storyboard).
 3. PrivacyInfo.xcprivacy (требование Apple: UserDefaults и прочее) + регистрация в проекте Xcode.
 4. Резервная копия project.pbxproj до правки.
 5. Отчёт: что сделано и что осталось (аккаунт Apple, сертификаты, TestFlight, покупки).
"""
import argparse, io, os, re, shutil, sys
from PIL import Image, ImageFilter, ImageDraw

IOS_ICON_SIZES = [
    ('Icon-App-20x20@1x.png', 20), ('Icon-App-20x20@2x.png', 40), ('Icon-App-20x20@3x.png', 60),
    ('Icon-App-29x29@1x.png', 29), ('Icon-App-29x29@2x.png', 58), ('Icon-App-29x29@3x.png', 87),
    ('Icon-App-40x40@1x.png', 40), ('Icon-App-40x40@2x.png', 80), ('Icon-App-40x40@3x.png', 120),
    ('Icon-App-60x60@2x.png', 120), ('Icon-App-60x60@3x.png', 180),
    ('Icon-App-76x76@1x.png', 76), ('Icon-App-76x76@2x.png', 152),
    ('Icon-App-83.5x83.5@2x.png', 167), ('Icon-App-1024x1024@1x.png', 1024),
]


def hex_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def make_icon_from_source(src, out_path, size=1024, bg='#12141a'):
    im = Image.open(src).convert('RGBA')
    # вписываем в квадрат с полями, подложка — цвет базы
    side = max(im.size)
    canvas = Image.new('RGBA', (side, side), hex_rgb(bg) + (255,))
    canvas.paste(im, ((side - im.size[0]) // 2, (side - im.size[1]) // 2), im)
    if side != size:
        canvas = canvas.resize((size, size), Image.LANCZOS)
        canvas = canvas.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=3))
    canvas.convert('RGB').save(out_path, 'PNG')
    return out_path


def make_icon_plain(out_path, size=1024, bg='#12141a', accent='#e0a03c'):
    """Простая иконка в стиле дизайн-системы: тёмная база и янтарная руна."""
    im = Image.new('RGB', (size, size), hex_rgb(bg))
    d = ImageDraw.Draw(im)
    a = hex_rgb(accent)
    w = int(size * 0.055)
    cx, cy = size // 2, size // 2
    h = int(size * 0.30)
    d.line([(cx, cy - h), (cx, cy + h)], fill=a, width=w)                      # ствол
    d.line([(cx, cy - h), (cx - h * 0.62, cy - h * 1.55)], fill=a, width=w)    # левая ветвь
    d.line([(cx, cy - h), (cx + h * 0.62, cy - h * 1.55)], fill=a, width=w)    # правая ветвь
    glow = im.filter(ImageFilter.GaussianBlur(size // 40))
    im = Image.blend(im, glow, 0.25)
    im.save(out_path, 'PNG')
    return out_path


def write_launch_transparent(imageset_dir):
    for name, size in (('LaunchImage.png', 90), ('LaunchImage@2x.png', 180), ('LaunchImage@3x.png', 270)):
        Image.new('RGBA', (size, size), (0, 0, 0, 0)).save(os.path.join(imageset_dir, name), 'PNG')


def patch_launch_bg(storyboard, bg='#12141a'):
    r, g, b = [c / 255.0 for c in hex_rgb(bg)]
    t = io.open(storyboard, encoding='utf-8').read()
    color = '<color key="backgroundColor" red="%.3f" green="%.3f" blue="%.3f" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>' % (r, g, b)
    if 'backgroundColor' in t:
        t = re.sub(r'<color key="backgroundColor"[^/]*/>', color, t, count=1)
    else:
        t = t.replace('<view key="view"', '<view key="view"')
    io.open(storyboard, 'w', encoding='utf-8').write(t)
    return 'фон экрана запуска: %s' % bg


PRIVACY = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>E174.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
'''


def register_in_xcode(proj_path, filename='PrivacyInfo.xcprivacy'):
    t = io.open(proj_path, encoding='utf-8').read()
    if filename in t:
        return 'уже зарегистрирован в проекте'
    id_file = 'AA11BB22CC33DD44EE55FF66'
    id_build = 'AA11BB22CC33DD44EE55FF67'
    t = t.replace('/* Begin PBXBuildFile section */',
                  '/* Begin PBXBuildFile section */\n\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
                  % (id_build, filename, id_file, filename), 1)
    t = t.replace('/* Begin PBXFileReference section */',
                  '/* Begin PBXFileReference section */\n\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = text.xml; path = %s; sourceTree = "<group>"; };'
                  % (id_file, filename, filename), 1)
    # в группу Runner
    m = re.search(r'(name = Runner;\s*\n\s*path = Runner;\s*\n\s*sourceTree = [^;]+;\s*\n\s*children = \(\n)', t)
    if m:
        t = t[:m.end()] + '\t\t\t\t%s /* %s */,\n' % (id_file, filename) + t[m.end():]
    # в фазу ресурсов
    m2 = re.search(r'(isa = PBXResourcesBuildPhase;[\s\S]*?files = \(\n)', t)
    if m2:
        t = t[:m2.end()] + '\t\t\t\t%s /* %s in Resources */,\n' % (id_build, filename) + t[m2.end():]
    io.open(proj_path, 'w', encoding='utf-8').write(t)
    return 'добавлен в проект Xcode (файл+фаза ресурсов)'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('project')
    ap.add_argument('--name', required=True, help='отображаемое имя приложения')
    ap.add_argument('--icon', help='исходная картинка иконки (png, >=1024 желательно)')
    ap.add_argument('--bg', default='#12141a')
    ap.add_argument('--accent', default='#e0a03c')
    a = ap.parse_args()

    proj = os.path.abspath(a.project)
    ios = os.path.join(proj, 'ios')
    if not os.path.isdir(ios):
        print('НЕТ папки ios/ — создайте её командой: flutter create --platforms=ios .')
        sys.exit(1)
    report = []

    # 1. иконки
    iconset = os.path.join(ios, 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    os.makedirs(iconset, exist_ok=True)
    src = a.icon
    if not src:
        cand = os.path.join(proj, 'android', 'app', 'src', 'main', 'res', 'mipmap-xxxhdpi', 'ic_launcher.png')
        src = cand if os.path.exists(cand) else None
    base = os.path.join(iconset, 'Icon-App-1024x1024@1x.png')
    if src:
        make_icon_from_source(src, base, 1024, a.bg)
        report.append('иконки: источник %s' % os.path.basename(src))
    else:
        make_icon_plain(base, 1024, a.bg, a.accent)
        report.append('иконки: сгенерирована базовая (без источника)')
    for name, size in IOS_ICON_SIZES:
        if size == 1024:
            continue
        im = Image.open(base)
        im.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, name), 'PNG')
    report.append('иконок записано: %d' % len(IOS_ICON_SIZES))

    # 2. экран запуска
    li = os.path.join(ios, 'Runner', 'Assets.xcassets', 'LaunchImage.imageset')
    if os.path.isdir(li):
        write_launch_transparent(li)
        report.append('LaunchImage: прозрачный')
    sb = os.path.join(ios, 'Runner', 'Base.lproj', 'LaunchScreen.storyboard')
    if os.path.exists(sb):
        report.append(patch_launch_bg(sb, a.bg))

    # 3. Info.plist: отображаемое имя
    plist = os.path.join(ios, 'Runner', 'Info.plist')
    if os.path.exists(plist):
        t = io.open(plist, encoding='utf-8').read()
        t = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)', r'\g<1>%s\g<2>' % a.name, t)
        io.open(plist, 'w', encoding='utf-8').write(t)
        report.append('Info.plist: имя «%s»' % a.name)

    # 4. манифест приватности
    pv = os.path.join(ios, 'Runner', 'PrivacyInfo.xcprivacy')
    io.open(pv, 'w', encoding='utf-8').write(PRIVACY)
    pbx = os.path.join(ios, 'Runner.xcodeproj', 'project.pbxproj')
    if os.path.exists(pbx):
        bak = pbx + '.bak'
        if not os.path.exists(bak):
            shutil.copy2(pbx, bak)
        report.append('PrivacyInfo: ' + register_in_xcode(pbx))

    print('=== iOS-подготовка: %s ===' % os.path.basename(proj))
    for line in report:
        print(' •', line)
    print('\nОсталось (нужен Mac и аккаунт Apple): сборка на macOS, сертификаты и профили, внутренние покупки в App Store Connect, TestFlight, скриншоты 6.7"/6.5"/5.5"')


if __name__ == '__main__':
    main()
