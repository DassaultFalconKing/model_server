# GEMMAMONSTER-OVMS — отчёт ревизору

Дата: 2026-09-08  
Ветка: `docs/gemma4-local-acceptance-execution`  
Проверенная ревизия: `8d14f31b65257fbc3148dbf8f64b7280b189f7f2`  
Known-good ancestry: `fea1a5f1c2640aa60fe6a840d3f62b38fb7b7767`

## Среда

- MSI Claw 8 AI+ A2VM
- Intel Arc 140V GPU (16 GB shared GPU memory)
- 32 GB system RAM
- Windows 11 Home 10.0.26200
- OVMS backend `2026.4.0-22930-61afcb26271-releases/2026/4`
- OpenVINO GenAI backend `2026.4.0.0-3401-5f7f1278107`
- Gemma 4 26B A4B INT4 OpenVINO model

## Рабочая конфигурация

Штатный сервер поднят на GPU с `VLM_CB`, `max_num_seqs=1`, `cache_size=0`,
`enable_prefix_caching=false`, `DYNAMIC_QUANTIZATION_GROUP_SIZE=0`,
`PERFORMANCE_HINT=LATENCY`, `chat_template_mode=MINJA`, очередь графа `0`.
REST: `8888`; gRPC: `9000`.

## Результаты acceptance

| Профиль | Результат | Покрытие |
|---|---:|---|
| A (`VLM`) | 14/14 PASS | unary + streaming, 2k/4k/8k/12k/16k |
| C (`VLM_CB` + prefix cache) | 14/14 PASS | unary + streaming, 2k/4k/8k/12k/16k |
| B2 (`VLM_CB`, fresh process) | 6/6 PASS | до 8k |
| B3 (`VLM_CB`, fresh process) | 14/14 PASS | unary + streaming, 2k/4k/8k/12k/16k |

Тест проверял не только наличие tool call: точное имя и аргумент `probe-N`,
свободную генерацию 300–500 токенов, unary/streaming и persistent context с
tool result.

Артефакты находятся в `runtime/gemmamonster-acceptance/`.

## Наблюдение о падении

В первом полном прогоне B (`B-full`, 18:54) streaming-запрос на 8k завершился
принудительным закрытием соединения и процесс OVMS завершился. Повторные свежие
запуски B2 и B3 прошли; поэтому это воспроизводимый acceptance FAIL первого
прогона, но не подтверждённый постоянный дефект текущего процесса.

## Автоматический speed selection

Добавлен `Optimize-GemmaMonsterOvms.ps1`, сравнивающий B и D
(`PERFORMANCE_HINT=THROUGHPUT`). Его первый запуск получил FAIL от probe для
обоих кандидатов; это ограничение текущего smoke-probe, а не доказательство
неработоспособности VLM_CB. Поэтому production/default оставлен на проверенном B.

## Вердикт

`PASS` для текущего B-профиля по проведённому acceptance matrix и tool-calling
контракту, с оговоркой об историческом единичном streaming disconnect в первом
прогоне. `PERFORMANCE_HINT=THROUGHPUT` пока `UNVERIFIED`; менять рабочий профиль
на D без исправленного benchmark-probe нельзя. Полный внешний OpenCode agent loop
и независимое измерение tokens/sec этим отчётом не утверждаются.
