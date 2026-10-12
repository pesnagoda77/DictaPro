// Task 099: record 5.x на iOS при прерывании записи (звонок, Siri,
// смена аудио-роута — а иногда и при штатной остановке) оставляет WAV
// с нефинализированным заголовком: data size=0. Для читателей, ожидающих
// корректный RIFF, файл выглядит пустым. Переписываем заголовок
// фактическими размерами — файл валиден, PCM-данные на месте.
import 'dart:io';
import 'dart:typed_data';

class WavHeaderFixer {
  static Future<void> fix(String path) async {
    final f = File(path);
    if (!await f.exists()) return;
    final raf = await f.open(mode: FileMode.readWrite);
    try {
      final len = await raf.length();
      if (len < 44) return;
      final head = await raf.read(12);
      if (!_tag(head, 0, 'RIFF') || !_tag(head, 8, 'WAVE')) return; // не WAV

      // Идём по чанкам: ищем data.
      var off = 12;
      int? dataSizePos;
      while (off + 8 <= len) {
        await raf.setPosition(off);
        final ch = await raf.read(8);
        final id = String.fromCharCodes(ch.sublist(0, 4));
        final sz = _le32(ch, 4);
        if (id == 'data') {
          dataSizePos = off + 4;
          break;
        }
        off += 8 + sz + (sz & 1); // чанки выровнены по чётному размеру
      }
      if (dataSizePos == null) return;

      final dataStart = (dataSizePos - 4) + 8;
      final actualData = len - dataStart;
      final actualRiff = len - 8;

      await raf.setPosition(4);
      final riffSz = _le32(await raf.read(4), 0);
      await raf.setPosition(dataSizePos);
      final dataSz = _le32(await raf.read(4), 0);

      if (riffSz == actualRiff && dataSz == actualData) return; // заголовок ок

      final buf = Uint8List(4);
      await raf.setPosition(4);
      _putLe32(buf, actualRiff);
      await raf.writeFrom(buf);
      await raf.setPosition(dataSizePos);
      _putLe32(buf, actualData);
      await raf.writeFrom(buf);
    } catch (_) {
      // Не критично: конвертер (task 099) сам терпит нефинализированный
      // заголовок, читая data до конца файла.
    } finally {
      await raf.close();
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
