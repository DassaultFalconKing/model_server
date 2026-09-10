Да. После уточнения **«причастность, а не авторство»** картина получается гораздо правильнее. И, что приятно, Git ancestry здесь оказался не таким уж сатанинским, как количество веток намекало.

### Что считаем «нашим файлом»

Я предлагаю зафиксировать критерий так:

> **Gemmamonster-involved file** = файл, который на любой релевантной Gemma4 / Gemmamonster / OVMS-forward-port линии был нами содержательно изменён, перенесён, восстановлен, адаптирован при forward-port, разрешён при merge/conflict либо участвовал в принятом исправлении, даже если текущий `git blame` уже показывает upstream.

Это лучше чистого author/blame. Например, файл мог пройти `cherry-pick → rebase → merge → rewrite`, и современный blame невозмутимо сообщит, что всё сделал кто-то другой. Git, как обычно, помнит ровно то, что ему удобно.

У GitHub-коннектора в этой сессии отдельного blame API нет, поэтому я **не буду притворяться, что выполнил line-blame**. Вместо этого ancestry + per-commit changed-files дают более надёжную основу для причастности. Для окончательного машинного отчёта локальный `git blame --reverse` всё равно стоит добавить вторым свидетельством.

## 1. Зафиксированные known-good / контрольные точки

| Статус                                 | Ref                                             | SHA                                        | Значение                                                                       |
| -------------------------------------- | ----------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------ |
| **KNOWN GOOD 2026.4**                  | `freeze/gemmamonster-2026.4-known-good`         | `c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd` | Зафиксированный 2026.4 known-good                                              |
| **KNOWN WORKING E / MINJA**            | `freeze/gemmamonster-working-e-minja-20260909`  | `4907343476e5c57d7cff5a1209c8317358a847ea` | Явно замороженный рабочий Profile E / MINJA runtime                            |
| **2026.5 ACCEPTED FORWARD-PORT POINT** | ancestry `integration/ovms-2026.5-forward-port` | `2d17e36f39412f18df558c49c6bc4661b833f675` | `complete 2026.5 forward-port acceptance`                                      |
| current hardening                      | `integration/gemma4-protocol-hardening-2026.5`  | `5d995cfafdb2ec90578678aa15714dedebc843b8` | Более новая линия, уже после acceptance, поэтому **не смешиваем с known-good** |

2026.4 freeze действительно стоит на `c48366f...`.
Отдельная рабочая E/MINJA freeze стоит на `4907343...`, причём сам commit называется `freeze(gemma4): record working E MINJA runtime`.

Особенно важно: `2d17e36f...` не какая-то случайная промежуточная ветка. Его commit message прямо фиксирует завершение 2026.5 forward-port acceptance и перенос parser/reasoning/request-policy/build-environment fixes.

---

# 2. Ancestry относительно последнего upstream OVMS

Последний upstream `openvinotoolkit/model_server/main`, который разрешился при аудите:

```text
a3a2abf287d5cb52f454bb1a1a55c0346cd44a35
Fix fuzz build. (#4497)
```

Наша текущая:

```text
integration/gemma4-protocol-hardening-2026.5
5d995cfafdb2ec90578678aa15714dedebc843b8
```

И вот здесь отличная новость:

```text
upstream/main     a3a2abf
                   |
                   +--- our 49 commits ---> 5d995cf
                   
behind upstream: 0
ahead upstream:  49
merge-base:      a3a2abf
```

То есть **нынешняя hardening-ветка уже содержит ровно последний проверенный upstream main**. Это не сравнение древнего форка с современным OVMS.

В ancestry виден специальный merge:

```text
fe9d803961d4001a26ff64f6f0dadde469c14ae3
merge(upstream): sync OVMS main at a3a2abf287d5
```

Причём commit документирует:

```text
Upstream:    a3a2abf287d5...
Merge base:  b935fe8b96a0...
Local:       646b6f8423d0...
```

и отдельно отмечает, что upstream delta там был лишь fuzz-packaging fix, а Gemma4 parser/generator/runtime semantics этим merge не менялись.

Это почти идеальная база для нашего аудита.

---

# 3. Точный CURRENT DIFF: наша ветка против последнего upstream

На `5d995cf...` против `a3a2abf...` сейчас существует **53 отличающихся файла**.

Из них production/runtime/build surface следующий.

### Core OVMS / API

```text
src/BUILD

src/llm/apis/openai_api_handler.hpp
src/llm/apis/openai_completions.hpp
src/llm/apis/openai_request.hpp
src/llm/apis/openai_responses.cpp
src/llm/apis/openai_responses.hpp

src/llm/io_processing/base_generation_config_builder.hpp

src/llm/io_processing/chat_template/analyzer.cpp
src/llm/io_processing/chat_template/caps.hpp

src/llm/io_processing/gemma4/gemma4_reasoning_parser.cpp
src/llm/io_processing/gemma4/gemma4_reasoning_parser.hpp
src/llm/io_processing/gemma4/gemma4_tool_parser.cpp
src/llm/io_processing/gemma4/gemma4_tool_parser.hpp

src/llm/io_processing/generation_config_builder.hpp

src/llm/io_processing/input_processors/chat_template_adapter.cpp
src/llm/io_processing/input_processors/chat_template_adapter.hpp
src/llm/io_processing/input_processors/chat_template_processor.cpp
src/llm/io_processing/input_processors/chat_template_processor.hpp

src/llm/io_processing/output_parser.cpp
src/llm/io_processing/output_parsing_config.hpp

src/llm/ovms_text_streamer.cpp

src/llm/servable.cpp
src/llm/servable.hpp
```

Это **23 runtime/source файла**.

### Build / package

```text
src/version.hpp
windows_build.bat
windows_create_package.bat
windows_install_build_dependencies.bat
```

Итого production + build surface: **27 файлов**.

---

# 4. Наши test-contract файлы

Это тоже важная часть причастности, потому что именно ими определяется, что считается сохранённой семантикой при следующем upstream-port:

```text
src/test/llm/gemma4_fast/BUILD
src/test/llm/gemma4_fast/gemma4_parser_contract_test.cpp
src/test/llm/gemma4_fast/gemma4_reasoning_semantic_refit_test.cpp
src/test/llm/gemma4_fast/gemma4_recovery_contract_test.cpp

src/test/llm/gemma4_overlay/BUILD
src/test/llm/gemma4_overlay/gemma4_chat_template_overlay_contract_test.cpp

src/test/llm/generation_config/BUILD
src/test/llm/generation_config/gemma4_generation_contract_test.cpp
src/test/llm/generation_config/gemma4_prompt_state_generation_contract_test.cpp
src/test/llm/generation_config/openai_parallel_tool_calls_contract_test.cpp

tests/windows/gemma4_standalone_package_test.ps1
```

То есть ещё **11 contract/test файлов**.

---

# 5. Наш runtime/operator tooling

Текущий diff содержит:

```text
scripts/gemma4/Start-Gemma4.ps1
scripts/gemma4/audit-forward-port.ps1
scripts/gemma4/benchmark-legacy-prompts.ps1
scripts/gemma4/build-local-candidate.ps1
scripts/gemma4/collect-runtime-provenance.ps1
scripts/gemma4/forward-port-manifest.json
scripts/gemma4/launch-gemma4-candidate.ps1
scripts/gemma4/new-upstream-forward-port.ps1
scripts/gemma4/package-standalone-runtime.ps1
scripts/gemma4/prepare-google-template-overlay.ps1
scripts/gemma4/run-candidate-acceptance.ps1
scripts/gemma4/semantic_ab.py
scripts/gemma4/test-protocol-hardening.ps1
scripts/gemma4/test_semantic_ab.py
```

Ещё **14 файлов**.

Плюс:

```text
docs/gemmamonster/COMPARATIVE-GEMMA4-PARSER-VERDICT.md
```

Получаем:

```text
23 runtime source
 4 build/package
11 tests/contracts
14 scripts
 1 document
----------------
53 current upstream-different files
```

---

# 6. Но CURRENT DIFF != полный provenance

И вот здесь твоё уточнение про «причастность» особенно важно.

Есть файлы, которые **мы точно трогали исторически**, хотя они уже не входят в нынешние 53 отличия от upstream.

Самый показательный:

```text
src/llm/apis/openai_api_handler.cpp
```

Он участвовал в нашем accepted parser/tool-contract исправлении. В частности, мы добавляли fail-closed поведение:

```text
tool_choice = required/named
+
tools отсутствуют
=
INVALID_ARGUMENT
```

вместо прежнего тихого превращения в `tool_choice=none`.

Это зафиксировано в историческом implementation/evidence commit `798e99e...`. Там же явно перечислена рабочая поверхность: `openai_api_handler.cpp`, Gemma4 reasoning/tool parsers, generation builder, output parser/config и build/test integration.

Ещё один подтверждённый исторический файл:

```text
windows_build_fast.ps1
```

Он присутствовал в acceptance-era working-tree provenance, хотя в современную hardening-ветку эта форма build helper уже не входит.

Следовательно, **минимальный подтверждённый кодовый provenance-union сейчас = текущие 27 production/build файлов + эти исторические-only поверхности**.

---

# 7. Семантический diff против upstream

Это гораздо полезнее количества плюсиков и минусиков.

| Область                         | Наше состояние относительно upstream | Семантический эффект                                                                                       |                                                       |
| ------------------------------- | ------------------------------------ | ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `gemma4_tool_parser.*`          | существенно расширен                 | Native Gemma4 framing, arguments, recovery, multi-call и malformed handling                                |                                                       |
| `output_parser.*`               | изменена маршрутизация               | Gemma4 parser может **владеть своими boundaries**, generic parser не режет JSON по сырому marker           |                                                       |
| `output_parsing_config.hpp`     | добавлена parser-policy metadata     | Разделение model-specific framing и generic routing                                                        |                                                       |
| `gemma4_reasoning_parser.*`     | model-native semantics               | Thought-channel рассматривается как Gemma protocol, а не случайный Qwen surrogate                          |                                                       |
| `ovms_text_streamer.cpp`        | исправлен phase handoff              | Special token `<                                                                                           | tool_call>` не теряется при переходе reasoning → tool |
| `generation_config_builder.hpp` | hard grammar значительно расширена   | `required`/named/auto получают Gemma-aware constrained generation                                          |                                                       |
| `chat_template_processor.*`     | введена post-render reconciliation   | Grammar адаптируется **после фактического Jinja render**, то есть учитывает, открыт ли уже thought-channel |                                                       |
| `chat_template_adapter.*`       | Gemma-specific rendered state        | Template и generation grammar больше не живут в параллельных вселенных                                     |                                                       |
| `analyzer.cpp`, `caps.hpp`      | расширены capabilities               | Gemma template capabilities распознаются и передаются дальше                                               |                                                       |
| OpenAI API headers/responses    | сохранена tool policy                | `parallel_tool_calls`, tool state и Responses/Chat semantics доходят до generation path                    |                                                       |
| `servable.*`                    | существенный local delta             | Persistent session continuity / runtime state                                                              |                                                       |
| Windows package files           | local deployment semantics           | Воспроизводимая Windows/Arc сборка и standalone Gemmamonster package                                       |                                                       |

## 7.1 Самая важная parser-разница

Исторически у generic `OutputParser` был соблазн увидеть:

```text
<tool_call|>
```

и решить:

> конец tool-call, режем поток здесь.

Но Gemma может иметь этот текст **внутри JSON string**.

Наш контракт ввёл концепцию:

```cpp
ownsToolCallBoundaries = true
```

То есть Gemma parser сам определяет, находится marker:

```text
outside JSON
```

или:

```json
{"text": "literal <tool_call|> inside argument"}
```

Это не косметический diff. Это разница между валидным аргументом и поломанным tool call. Исторический acceptance как раз ловил этот regression.

---

## 7.2 Reasoning → tool handoff

Текущая линия отдельно чинит случай:

```text
<|channel|>thought
...
<|channel|>
<|tool_call>
```

Проблема была не только в parser.

Streamer мог:

1. закончить reasoning;
2. переключить `skip_special_tokens`;
3. съесть непосредственно следующий `<|tool_call>`;
4. parser уже никогда его не увидит.

`45ea4a8...` меняет порядок:

```text
sync previous phase decode mode
→ flush
→ re-read parser phase
→ detect token-id phase start
```

То есть parser и tokenizer/streamer теперь согласуют фазу, а не соревнуются, кто первым уничтожит доказательство преступления. Этот commit и его rationale присутствуют прямо в ancestry.

---

## 7.3 Bare-call recovery

Мы не просто принимаем:

```text
call:anything
```

Иначе обычная фраза вроде:

```text
call:question prose
```

может внезапно стать tool call. Очень творческое API, но не особенно полезное.

Современная hardening-линия ограничивает recovery registry-aware prefixes:

```text
call:<allowed-tool>{
call:<allowed-tool>(
```

При этом partial streaming prefix:

```text
call:quest
```

может быть удержан, если разрешённый инструмент:

```text
question
```

То есть tolerance остаётся, false-positive область резко сужается. Это `7f90275...`.

---

## 7.4 Rendered prompt grammar

Здесь у нас ещё одно фундаментальное отличие от обычной generation-config логики.

Нельзя построить hard grammar только из:

```text
request + tools + tool_choice
```

потому что официальный Gemma template может уже закончить prompt внутри:

```text
<|channel|>thought
```

Следовательно правильное продолжение grammar зависит от **реально отрендеренного prompt**.

Текущая архитектура поэтому разделяет:

```text
GenerationConfigBuilder
    request → initial grammar
```

и:

```text
ChatTemplateProcessor
    rendered prompt → grammar reconciliation
```

Commit `64fd113...` специально централизует эту ответственность именно на render boundary.

Это я бы считал одним из ключевых наших семантических вкладов, а не просто Gemma workaround.

---

# 8. Важный результат сравнения 2026.5 acceptance с его предком

Для accepted commit:

```text
2d17e36f39412f18df558c49c6bc4661b833f675
```

его 2026.5 upstream ancestor:

```text
b935fe8b96a0445f3746297f872b55ed202fa6e5
```

GitHub даёт:

```text
ahead:  8
behind: 0
merge-base = b935fe8b
```

Это значит, что acceptance port был не «свалкой нескольких несвязанных веток», а **восемью локальными commits поверх конкретного upstream baseline**.

И уже после этого наша линия была синхронизирована с `a3a2abf`.

Граф принципиально такой:

```text
upstream b935fe8
      |
      +-- 2d8df712   migration contracts
      +-- 2eda5165   hardened parser + guided generation
      +-- 2e52a839   tool policy + parallel semantics
      +-- d6aa8c5b   template workaround composition
      +-- 6bd6ba35   persistent session continuity
      +-- ...
      +-- 2d17e36f   ACCEPTED FORWARD PORT
                        |
                        +-- later reasoning/parser work
                        |
                        +-- 646b6f84
                               \
upstream a3a2abf ------------- fe9d8039 merge
                                      |
                                      +-- current hardening
                                      |
                                   5d995cfa
```

Вот это уже нормальный provenance chain, который можно показывать maintainer'у, а не археологический рисунок углём.

---

# 9. Что делать с `ab-evidence/**` и `runtime/**`

Они **тоже являются нашей причастностью**, но я не смешивал их с source provenance.

Причина объективная: исторический 2026.4 known-good содержит сотни:

```text
ab-evidence/**
runtime/gemmamonster-acceptance/**
runtime/gemmamonster-optimization/**
```

В одном только compare GitHub начинает выдавать огромные серии `request.json`, `response.raw`, `trial.json`, SSE и snapshots раньше, чем добирается до интересующего `src/`.

Поэтому предлагаю в нашем итоговом ledger иметь классы:

```text
PRODUCTION
TEST_CONTRACT
BUILD_PACKAGE
OPERATOR_TOOLING
DOCUMENTATION
EVIDENCE
GENERATED_RUNTIME
```

а не делать вид, что `stream-context-8000.sse.txt` и `gemma4_tool_parser.cpp` имеют одинаковую инженерную ценность.

---

# 10. Итоговая область, которую теперь надо сравнивать при каждом upstream update

Для **семантического forward-port audit** главным whitelist становится именно эта поверхность:

```text
src/BUILD
src/llm/apis/*
src/llm/io_processing/base_generation_config_builder.hpp
src/llm/io_processing/chat_template/analyzer.cpp
src/llm/io_processing/chat_template/caps.hpp
src/llm/io_processing/gemma4/*
src/llm/io_processing/generation_config_builder.hpp
src/llm/io_processing/input_processors/chat_template_adapter.*
src/llm/io_processing/input_processors/chat_template_processor.*
src/llm/io_processing/output_parser.cpp
src/llm/io_processing/output_parsing_config.hpp
src/llm/ovms_text_streamer.cpp
src/llm/servable.cpp
src/llm/servable.hpp
src/version.hpp
windows_build.bat
windows_create_package.bat
windows_install_build_dependencies.bat
```

Плюс исторически подтверждённые involvement-only файлы вроде:

```text
src/llm/apis/openai_api_handler.cpp
windows_build_fast.ps1
```

И отдельно contracts/tests.

### Главный вывод

У нас теперь есть не просто «fork отличается от OVMS».

Есть намного более сильное утверждение:

> **Текущий Gemmamonster hardening является 49-commit descendant актуального проверенного `openvinotoolkit/model_server@a3a2abf`, без missing upstream commits. Его runtime delta локализуется в небольшой известной поверхности файлов, для которой можно восстановить provenance до accepted 2026.5 forward-port и 2026.4 known-good.**

Причём основные отличия семантические и хорошо раскладываются на **tool framing, reasoning boundaries, special-token streaming, rendered-prompt grammar, OpenAI tool policy и session continuity**. Это уже достаточно узкая поверхность, чтобы следующий upstream-port делать не «перетаскиванием форка», а **file-by-file semantic reconciliation**.

Следующим логическим артефактом здесь должен быть машинный `GEMMAMONSTER-PROVENANCE-LEDGER.json`: `file → involvement commits → earliest ancestor → known-good presence → current upstream diff → semantic responsibility → disposition {UPSTREAMED|STILL_LOCAL|SUPERSEDED|TEST_ONLY}`. Именно он превратит последующие 2026.6/2027.x обновления из археологии в проверяемую процедуру.
