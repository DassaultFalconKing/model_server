# Prompt: source-only investigation of the Gemma4 adversarial review failure

Работай как независимый senior reviewer/debugger. Нужно выяснить по исходному коду, почему Gemma4 adversarial reliability campaign получила `NOT_ACCEPTED`, и определить, какие причины исправимы в OVMS, какие принадлежат chat template/model behavior, а какие могут быть дефектами harness. Ничего не исправляй до завершения анализа.

## Жёсткие границы

- Рабочий репозиторий: `C:\git\model_server-gemma4-fast`.
- Текущая целевая ветка: `integration/ovms-2026.5-forward-port`.
- В начале зафиксируй `git rev-parse HEAD`, ветку и dirty state. Не считай SHA из этого промпта текущим.
- Исследование только по коду, Git-истории и приложенным логам. Не запускай OVMS, модель, GPU inference, сборку или длительные тесты. Не останавливай работающий сервер.
- Не изменяй файлы, не коммить и не пушь. Итогом должен быть evidence-backed root-cause report и минимальный план исправления.
- Исторический тест выполнен на OVMS 2026.4 exact HEAD `2cb5a9a0e8d22732de2d1c89f52795c2de612a57`, binary SHA256 `38067689f79ae6f6be2d951a7827c84768265f74ff35142a5f847bcc563668d4`. Не переноси выводы автоматически на текущую 2026.5 ветку: сравни код через `git diff`/`git log`.
- Единственный валидный reliability dataset: `reliability-v2-live`. Каталог `reliability-v2-attempt-wrong-base-url` и старый `reliability-v2` содержат ранние/ошибочные попытки с удвоенным `/v3/v3`; не смешивай их с итоговыми 316 trials.

## Наблюдаемый провал, который требуется объяснить

- Всего: 316 trials, verdict `NOT_ACCEPTED`.
- Named tool choice: `0/30`; во всех 30 случаях `finish_reason=length`, 1024 completion tokens, структурированный вызов отсутствует.
- Required tool choice: `50/50`.
- Auto: `4/100`.
- API-visible parser recognition: `279/279` среди попыток, где модель выдала вызов.
- Exact grounded-value fidelity: `262/279`.
- Ungrounded hallucination: `150/316`.
- Campaign A: `54/180`; 91 invented values, 35 truncated.
- Thinking cells: `42/100`; 56 invented values, 2 truncated.
- Adversarial B: `16/36`; 8 corrupted grounded values, 3 invented values, 9 wrong tools.
- В отдельной 50-request campaign четыре named second turns вернули HTTP 200, пустые `content` и `tool_calls`, `finish_reason=length` после 1024 токенов.
- В серверных логах нет inference `ERROR`, `FATAL`, `CL_OUT_OF_RESOURCES` или XGrammar errors.

Это доказывает критерий провала, но не окончательную первопричину. Не называй parser виновным только потому, что результат плохой: распознавание выполнено `279/279`.

## Что трассировать в коде

Проследи полный путь данных без пропусков:

1. JSON `tool_choice` и `tools` -> `OpenAIApiHandler::parseTools` -> `OpenAIRequest::toolChoice` и `toolNameSchemaMap`.
2. Передачу tools/tool_choice/tool results в JINJA template и rendered prompt, включая адаптер истории и различия первого/второго tool turn.
3. Выбор `Gemma4GenerationConfigBuilder`, различия `auto`, `required` и named, построение `StructuredOutputConfig`, обработку validation failure и возможность сброса constraints.
4. Взаимодействие reasoning grammar с mandatory tool grammar: может ли optional/unbounded thought поглотить весь `max_tokens`, не достигнув tool tag; чем named отличается от required в реально протестированном SHA.
5. Что именно гарантирует XGrammar: выбор инструмента, JSON shape/schema или также grounding значений. Проверь, может ли серверная grammar вообще запретить выдуманный SHA/digest, которого нет в tool result.
6. Путь tool-result content -> model prompt. Проверь потерю, преобразование, экранирование, нормализацию, truncation и неоднозначность authoritative values.
7. Вычисление verdict в `ab-evidence/reliability_grounded_harness_v2.py`: отдели реальные product failures от завышенного/ошибочного oracle. Особенно проверь `allow_no_tool`, forbidden distractors, wrong-tool classification и exact-value matching.
8. Сравни tested SHA `2cb5a9a0...` с текущим HEAD по всем относящимся файлам. Укажи, какие причины уже изменены в 2026.5, но не называй их исправленными без live rerun.

Минимальный набор исходников для чтения:

- `src/llm/apis/openai_api_handler.cpp`
- `src/llm/apis/openai_api_handler.hpp`
- `src/llm/apis/openai_request.hpp`
- `src/llm/io_processing/base_generation_config_builder.cpp`
- `src/llm/io_processing/generation_config_builder.hpp`
- `src/llm/io_processing/input_processors/chat_template_adapter.cpp`
- `src/llm/io_processing/input_processors/chat_template_processor.cpp`
- `src/llm/io_processing/chat_template/analyzer.cpp`
- `src/llm/io_processing/output_parser.cpp`
- `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp`
- `src/llm/io_processing/gemma4/gemma4_reasoning_parser.cpp`
- `src/test/llm/generation_config/gemma4_generation_contract_test.cpp`
- `src/test/llm/gemma4_fast/gemma4_parser_contract_test.cpp`
- `src/test/llm/gemma4_fast/gemma4_reasoning_semantic_refit_test.cpp`
- `ab-evidence/reliability_grounded_harness_v2.py`

Ищи дополнительные вызывающие места сам; этот список не является доказательством полноты.

## Приложенные evidence

Распакуй `gemma4-adversarial-test-logs-20260907-v4.zip`. Все файлы взяты без изменения из immutable remote branch `origin/Testrun_2026-09-07`, commit `393268a7a8acd1227a0203efbc297a2ea72ec64d`.

Сначала прочитай:

1. `FINAL-REPORT.md`.
2. `reliability-v2-live/summary.json`.
3. `reliability-v2-live/trials.jsonl`.
4. Representative raw trials для named truncation, auto invention, grounded corruption, fake-SHA distractor и wrong-tool.
5. Named second-turn request/response из `generated-campaign/r1-b3-c1-named`.
6. Серверные логи launch-attempt-4 и launch-attempt-5-restart.

## Требуемый результат

Верни отчёт в таком порядке:

1. Короткий verdict: почему acceptance gate не прошёл.
2. Таблица по классам `named truncation`, `auto hallucination`, `grounded corruption`, `wrong tool`, `harness issue`: observed evidence, точный code path, root cause или `UNKNOWN`, слой-владелец.
3. Для каждой root-cause гипотезы — подтверждающие и опровергающие факты с `file:line` на текущем HEAD и ссылкой на конкретный evidence-файл/trial.
4. Отдельный diff-разбор: что было в tested 2026.4 SHA и что изменено в текущей 2026.5 ветке.
5. Минимальный source-level fix plan, ранжированный по вероятности и риску. Не предлагай расширять parser language, если проблема находится до parser или в grounding.
6. Какие unit/contract tests надо сначала сделать красными. Live rerun перечисли отдельно как последующий acceptance gate, но не запускай.
7. Явно перечисли всё, что код и логи не позволяют доказать.

Главный вопрос: почему `required` был 50/50, а named 0/30 при одинаковом обязательном tool-call контракте, и почему parser распознавал 279/279 вызовов, но общий adversarial verdict всё равно оказался `NOT_ACCEPTED`?
