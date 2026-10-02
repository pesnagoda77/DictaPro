# Модель GigaAM v3 (ASR, русский, пунктуация из коробки)

Файлы модели **не хранятся в git** (≈222 МБ). Скачивание перед сборкой:

```bash
python3 tools/fetch_model.py        # Linux/macOS
# или
python tools\fetch_model.py         # Windows
```

Скрипт качает 5 файлов и кладёт их сюда (для APK-раздачи через
`tools/prepare_apk_build.py`) и в `android/gigaam_pack/src/main/assets/models/gigaam_v3_punct/`
(install-time asset pack для Play AAB):

| Файл | Размер | Источник |
|------|--------|----------|
| `encoder.int8.onnx` | ~214 МБ | HuggingFace `csukuangfj/sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16` |
| `decoder.onnx` | ~4,4 МБ | там же |
| `joiner.onnx` | ~2,6 МБ | там же |
| `tokens.txt` | <1 МБ | там же |
| `silero_vad.onnx` | ~0,6 МБ | github.com/k2-fsa/sherpa-onnx releases (asr-models) |

При первом запуске приложение копирует файлы из сборки во внутреннее
хранилище (локально, без сети) и показывает прогресс «Подготовка модели».
