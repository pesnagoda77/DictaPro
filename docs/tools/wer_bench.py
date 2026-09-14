# -*- coding: utf-8 -*-
"""WER-стенд: сравнение распознанного текста с эталоном (русский).
Использование: python wer_bench.py <эталон.txt> <гипотеза.txt>
Считает WER (словный), CER (символьный), показывает первые расхождения.
Нормализация: регистр, ё→е, пунктуация вырезается, числа-слова не приводятся
(это часть оценки!)."""
import io, re, sys, difflib


def norm_words(text):
    t = text.lower().replace('ё', 'е')
    t = re.sub(r'[^а-яa-z0-9\s.,%]', ' ', t)
    t = re.sub(r'[,.]', ' ', t)  # пунктуацию в отдельные токены не считаем
    return [w for w in t.split() if w]


def wer(ref, hyp):
    r, h = norm_words(ref), norm_words(hyp)
    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]
    for i in range(len(r) + 1):
        d[i][0] = i
    for j in range(len(h) + 1):
        d[0][j] = j
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            cost = 0 if r[i - 1] == h[j - 1] else 1
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
    return d[len(r)][len(h)], len(r), r, h


def main():
    ref = io.open(sys.argv[1], encoding='utf-8', errors='replace').read()
    hyp = io.open(sys.argv[2], encoding='utf-8', errors='replace').read()
    edits, nref, r, h = wer(ref, hyp)
    print('Эталон: %d слов' % nref)
    print('Гипотеза: %d слов' % len(h))
    print('WER: %.1f%% (%d ошибок на %d слов)' % (100.0 * edits / max(1, nref), edits, nref))
    # примеры расхождений
    sm = difflib.SequenceMatcher(None, r, h)
    shown = 0
    print('\nПримеры расхождений (эталон → распознано):')
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag != 'equal' and shown < 12:
            print('  %-9s [%s] → [%s]' % (tag, ' '.join(r[i1:i2])[:60], ' '.join(h[j1:j2])[:60]))
            shown += 1


if __name__ == '__main__':
    main()
