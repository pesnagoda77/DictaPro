# -*- coding: utf-8 -*-
"""WER-стенд v2 (по шагу 1 глубокого исследования): единая нормализация,
разложение ошибок S/D/I, CER, доверительный интервал, сравнение нескольких гипотез.

Использование:
    python wer_bench2.py <эталон.txt> <гипотеза1.txt> [<гипотеза2.txt> ...]
Нормализация одна для всех сторон: нижний регистр, ё→е, пунктуация вырезается,
числа НЕ разворачиваются (сравниваем как есть), слова без букв/цифр отбрасываются.
"""
import io, re, sys, random


def norm(text):
    t = text.lower().replace('ё', 'е')
    t = re.sub(r'[^а-яa-z0-9\s.,%]', ' ', t)
    t = re.sub(r'[,.]', ' ', t)
    return [w for w in t.split() if w and (re.search(r'[а-яa-z0-9]', w))]


def align(ref, hyp):
    n, m = len(ref), len(hyp)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        d[i][0] = i
    for j in range(m + 1):
        d[0][j] = j
    for i in range(1, n + 1):
        ri = ref[i - 1]
        for j in range(1, m + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1,
                          d[i - 1][j - 1] + (ri != hyp[j - 1]))
    i, j = n, m
    s = dele = ins = 0
    while i > 0 or j > 0:
        if i > 0 and j > 0 and d[i][j] == d[i - 1][j - 1] + (ref[i - 1] != hyp[j - 1]):
            if ref[i - 1] != hyp[j - 1]:
                s += 1
            i -= 1; j -= 1
        elif i > 0 and d[i][j] == d[i - 1][j] + 1:
            dele += 1; i -= 1
        else:
            ins += 1; j -= 1
    return d[n][m], n, s, dele, ins


def cer(ref_words, hyp_words):
    """CER по строкам через difflib (быстро, без ДП по символам)."""
    import difflib
    a = ''.join(ref_words)
    b = ''.join(hyp_words)
    if not a:
        return 0.0
    sm = difflib.SequenceMatcher(a=a, b=b, autojunk=False)
    same = sum(bl.size for bl in sm.get_matching_blocks())
    return 100.0 * (max(len(a), len(b)) - same) / len(a)


def ci95(errors, total, iters=400):
    """Бутстреп по словам: приблизительный доверительный интервал WER."""
    if total == 0:
        return (0.0, 0.0)
    p = errors / total
    vals = []
    for _ in range(iters):
        k = sum(1 for _ in range(total) if random.random() < p)
        vals.append(100.0 * k / total)
    vals.sort()
    return vals[int(0.025 * iters)], vals[int(0.975 * iters)]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return
    ref = norm(io.open(sys.argv[1], encoding='utf-8').read())
    print('Эталон: %d слов (нормализовано)' % len(ref))
    print('%-34s | %7s | %5s | %5s | %5s | %5s | %4s | %4s' %
          ('гипотеза', 'WER', 'S', 'D', 'I', 'CER', 'сл', '95%CI'))
    for path in sys.argv[2:]:
        hyp = norm(io.open(path, encoding='utf-8').read())
        e, n, s, dele, ins = align(ref, hyp)
        lo, hi = ci95(e, n)
        name = path.split('\\')[-1][:34]
        print('%-34s | %6.1f%% | %5d | %5d | %5d | %4.1f%% | %4d | %2.0f-%2.0f' %
              (name, 100.0 * e / n, s, dele, ins, cer(ref, hyp), len(hyp), lo, hi))


if __name__ == '__main__':
    main()
