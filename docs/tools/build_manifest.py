# -*- coding: utf-8 -*-
"""Подготовка данных для дообучения GigaAM (шаг 7 исследования).
Собирает TSV-манифесты (path\tduration\ttranscription) из пар
<аудио.wav + эталон.txt> в корпусах стенда.

Использование:
    python build_manifest.py <корень корпуса> [<корень 2> ...]
Ожидаемая раскладка:
    <корпус>/caseX.../audio.wav   (+ эталон.txt в той же папке)
    <корпус>/caseX.../эталон.txt  → transcription
Пишет: docs/bench/manifest_all.tsv и docs/bench/manifest_train.tsv (90/10 сплит).
"""
import io, os, sys, wave, random

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'bench')
OUT_DIR = os.path.abspath(OUT_DIR)


def find_pairs(root):
    pairs = []
    for dirpath, _dirs, files in os.walk(root):
        wavs = [f for f in files if f.lower().endswith(('.wav', '.flac'))]
        refs = [f for f in files if f.lower() in ('эталон.txt', 'reference.txt', 'ref.txt')]
        if wavs and refs:
            wav = os.path.join(dirpath, sorted(wavs)[0])
            ref = os.path.join(dirpath, refs[0])
            pairs.append((wav, ref))
    return pairs


def duration(path):
    try:
        with wave.open(path, 'rb') as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return 0.0


def clean_text(t):
    t = ' '.join(t.split())
    return t.replace('\t', ' ').replace('\n', ' ').strip()


def main():
    roots = sys.argv[1:] or [os.path.join(os.path.dirname(OUT_DIR), 'bench')]
    pairs = []
    for r in roots:
        pairs += find_pairs(r)
    if not pairs:
        print('Пар <аудио + эталон> не найдено. Уложите wav и эталон.txt рядом.')
        return
    rows = []
    total = 0.0
    for wav, ref in pairs:
        dur = duration(wav)
        txt = clean_text(io.open(ref, encoding='utf-8').read())
        if dur <= 0 or not txt:
            continue
        rows.append((os.path.abspath(wav), dur, txt))
        total += dur
    os.makedirs(OUT_DIR, exist_ok=True)
    all_path = os.path.join(OUT_DIR, 'manifest_all.tsv')
    with io.open(all_path, 'w', encoding='utf-8') as f:
        for p, d, t in rows:
            f.write('%s\t%.2f\t%s\n' % (p, d, t))
    random.seed(42)
    idx = list(range(len(rows)))
    random.shuffle(idx)
    cut = max(1, int(len(rows) * 0.9)) if len(rows) > 1 else 1
    train = [rows[i] for i in idx[:cut]]
    val = [rows[i] for i in idx[cut:]] or train[:1]
    for name, data in (('manifest_train.tsv', train), ('manifest_val.tsv', val)):
        with io.open(os.path.join(OUT_DIR, name), 'w', encoding='utf-8') as f:
            for p, d, t in data:
                f.write('%s\t%.2f\t%s\n' % (p, d, t))
    print('Записей: %d | суммарно %.1f мин (%.2f ч)' % (len(rows), total / 60.0, total / 3600.0))
    print('Куда: %s' % OUT_DIR)
    print('Цель исследования: 5–20 ч целевых записей для доменной адаптации.')


if __name__ == '__main__':
    main()
