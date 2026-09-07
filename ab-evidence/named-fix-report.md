# Gemma4: разбор 2cb5a9a0 и проверка исправления

Дата: 2026-09-07. Итог: **NOT_ACCEPTED**, устранён конкретный дефект генерации named.

## Происхождение

- Исходный HEAD: `2cb5a9a0e8d22732de2d1c89f52795c2de612a57`; изменения не закоммичены.
- Исходные доказательства: `runs/2cb5a9a0/20260907-125739`, не изменялись.
- Новый Dev binary: `bazel-bin/src/ovms.exe`.
- Новый SHA256: `86F85D44FAE544B771C0631CA087C47B21ECAD68D41E413075FF0837FD642570`.
- Это сборка HEAD + patch, не исторический accepted binary и не чистый stamped candidate.
- Live модель: `gemma4-26-heretic`, GPU, прежние config/model/template, порт 18000.
- Новые доказательства: `named-fix/`; patch и SHA записаны в `*/provenance.json`.

## Причины и изменения

1. **Named truncation — дефект grammar builder.** В `Gemma4GenerationConfigBuilder`
   optional thought перед обязательными tool tags был разрешён только для `required`.
   После tool response Google template при thinking off оставляет продолжение модельного
   хода без нового empty-thought prefix. Named принудительно переводил это продолжение
   сразу в JSON аргументы. Теперь named допускает тот же thought prefix, сохраняя
   единственное разрешённое имя и обязательную JSON schema. TRACE нового запуска
   подтверждает empty thought, затем завершённый вызов. Это согласуется с
   [документацией Google о формате Gemma4](https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4).
   Старый raw API не содержит незавершённую генерацию: точное содержимое старых 1024
   токенов из этого freeze восстановить нельзя. Причинная проверка — изменение одной
   ветки builder и повтор неизменённых запросов при том же лимите.

2. **B malformed/array/scalar — семантическое нарушение инструкции моделью.** Запросы
   используют `tool_choice=auto`; `allow_no_tool` — поле harness, не запрет OVMS API.
   Модель создаёт новый валидный вызов, извлекая значение даже из неполного JSON,
   массива или scalar. Это не доказательство ремонта malformed arguments парсером.
   Generic server не может запрещать вызовы после любого текстового/array результата:
   такие tool results допустимы. Для гарантии здесь нужен явно заданный контракт
   приложения с проверкой результата до следующей генерации; JSON grammar не доказывает
   соблюдение условия из естественного языка. Этот фейл остаётся открытым.

3. **Auto invented SHA — семантическая генерация.** Во входе нет artifact sha256,
   но схема предлагает optional поле; модель заполняет его выдуманными хешами.
   Auto идёт native/unconstrained путём; парсер корректно распознаёт вызов и не знает
   источника истины для значения. Удалять такие значения в generic parser нельзя:
   это замаскировало бы нарушение. Проверка grounding остаётся ответственностью
   явно заданного прикладного контракта. Фейл воспроизведён после исправления named.

4. **Ложный PASS оценщика.** Campaign A проверял commit SHA и invented hashes, но
   пропускал повреждение repository. Первый новый named содержал `:/git/g4-final-review`
   вместо исходного пути. Исправлен v2 classifier: сверяет repository с tool result,
   допускает только различие slash spelling. Старые результаты не переписаны;
   отдельная переоценка новых ответов — `named-fix/reclassified.json`.
   Проверка всех artifact paths и доказательности gate claims всё ещё не полная.

## Проверки

| Проверка | Результат |
|---|---|
| Новый C++ regression до фикса | FAIL на named, остальные 9 PASS |
| Generation contracts после фикса | 10/10 PASS |
| Parser contracts | 16/16 PASS (повторно использован успешный неизменённый Bazel test result) |
| Dev build `//src:ovms` | PASS, без SkipFastTests |
| Harness regression до исправления classifier | FAIL на повреждённом/отсутствующем repository |
| Harness contracts после исправления | 5/5 PASS |
| Frozen named, 3 повтора, max_tokens=1024 | 3/3 завершены, 239/176/176 tokens вместо 3 truncations |
| Named с новым repository check | 2/3 PASS, 1/3 F_GROUNDED_VALUE_CORRUPTED |
| Frozen required, 1 повтор | PASS, 292 tokens |
| B malformed/array/scalar | 3/3 D_WRONG_TOOL, остаются открытыми |
| Auto A1 | G_UNGROUNDED_VALUE_INVENTED, остаётся открытым |
| Полная повторная host acceptance / streaming / session-resume | NOT RUN |

Повторы выполнялись `replay_reliability_failures.py`, без правок frozen requests.
Первый batch остановился после трёх named из-за отсутствия raw directory для успешного
required. Runner исправлен: читает такие строки из `trials.jsonl`; required и controls
выполнены отдельными batch. Успешность небольшого повтора не доказывает общую reliability.

Логи сборки: `named-fix-red-build.log`, `named-fix-green-build.log`.
Диагностический TRACE сохранён в `named-fix/server.log`; затем сервис перезапущен
с обычным INFO logging, PID записан в `named-fix/service-pid.txt`.

**Не исправлены веса модели, общее grounding и условный отказ от tools. Не объявлять
ветку принятой на основании устранения truncation или совпадения одного SHA.**
