// Task 099: record 5.x на iOS при прерывании записи (звонок, Siri,
// смена аудио-роута — а иногда и при штатной остановке) оставляет WAV
// с нефинализированным заголовком: data size=0. Для читателей, ожидающих
// корректный RIFF, файл выглядит пустым. Переписываем заголовок
// фактическими размерами — файл валиден, PCM-данные на месте.
//
// Правка середины файла без режима r+ (в целевом Dart SDK нет
// FileMode.readWrite): шапка исправляется и файл перекопируется потоком
// во временный файл, затем атомарная замена. Копирование выполняется
// только когда заголовок действительно битый.
import 'dart:io';
import 'dart:typed_data';

class WavHeaderFixer {
  static Future<void> fix(String path) async {
    final f = File(path);
    if (!await f.exists()) return;
    RandomAccessFile? src;
    RandomAccessFile? dst;
    File? tmp;
    try {
      src = await f.open(mode: FileMode.read);
      final len = await src.length();
      if (len < 44) return;
      final head = await src.read(12);
      if (head.length < 12) return;
      if (!_tag(head, 0, 'RIFF') || !_tag(head, 8, 'WAVE')) return; // не WAV

      // Идём по чанкам: ищем data.
      var off = 12;
      int? dataSizePos;
      var dataStart = 0;
      while (off + 8 <= len) {
        await src.setPosition(off);
        final ch = await src.read(8);
        if (ch.length < 8) break;
        final id = String.fromCharCodes(ch.sublist(0, 4));
        final sz = _le32(ch, 4);
        if (id == 'data') {
          dataSizePos = off + 4;
          dataStart = off + 8;
          break;
        }
        off += 8 + sz + (sz & 1); // чанки выровнены по чётному размеру
      }
      if (dataSizePos == null || dataStart <= 0) return;

      final actualData = len - dataStart;
      final actualRiff = len - 8;

      await src.setPosition(4);
      final riffSz = _le32(await src.read(4), 0);
      await src.setPosition(dataSizePos);
      final dataSz = _le32(await src.read(4), 0);
      if (riffSz == actualRiff && dataSz == actualData) return; // заголовок ок

      // Читаем исправляемую шапку (до начала данных), правим размеры
      // и перекопируем файл потоком.
      await src.setPosition(0);
      final prefix = await src.read(dataStart);
      if (prefix.length < dataStart) return;
      final buf = Uint8List(4);
      _putLe32(buf, actualRiff);
      prefix.setRange(4, 8, buf);
      _putLe32(buf, actualData);
      prefix.setRange(dataSizePos, dataSizePos + 4, buf);

      tmp = File('$path.tmpfix');
      if (await tmp.exists()) await tmp.delete();
      dst = await tmp.open(mode: FileMode.write);
      await dst.writeFrom(prefix);
      var remaining = len - dataStart;
      while (remaining > 0) {
        final chunk =
            await src.read(remaining > (1 << 20) ? (1 << 20) : remaining);
        if (chunk.isEmpty) break;
        await dst.writeFrom(chunk);
        remaining -= chunk.length;
      }
      await dst.close();
      dst = null;
      await src.close();
      src = null;
      await tmp.rename(path);
      tmp = null;
    } catch (_) {
      // Не критично: конвертер (task 099) сам терпит нефинализированный
      // заголовок, читая data до конца файла.
    } finally {
      try {
        await dst?.close();
      } catch (_) {}
      try {
        await src?.close();
      } catch (_) {}
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  static bool _tag(Uint8List d, int i, String s) {
    final b = s.codeUnits;
    return d[i] == b[0] && d[i + 1] == b[1] && d[i + 2] == b[2] && d[i + 3] == b[3];
  }

  static int _le32(Uint8List d, int i) =>
      d[i] | (d[i + 1] << 8) | (d[i + 2] << 16) | (d[i + 3] << 24);

  static void _putLe32(Uint8List d, int v) {
    d[0] = v & 0xff;
    d[1] = (v >> 8) & 0xff;
    d[2] = (v >> 16) & 0xff;
    d[3] = (v >> 24) & 0xff;
  }
}
