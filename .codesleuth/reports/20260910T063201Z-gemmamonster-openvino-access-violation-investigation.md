---
reportType: documentation
targetSha: fde0762ba314dc5f6448726dfce7c533bad9a8a6
provenance: anon
reviewId: none
---

# GEMMAMONSTER OpenVINO access-violation forensics (01ea946a crashes)

- date: 2026-09-10T06:32:01Z
- target: fde0762ba314dc5f6448726dfce7c533bad9a8a6 (forensic session runs FROM this checkout; crashes belong to OLD candidate `01ea946a`)
- dirty: yes (M *.sh при `git status --ignore-submodules=all`)
- scope: два падения `0xc0000005` в `openvino.dll+0x84b50` (05:14:03 PID 21232, 05:23:49 PID 28840), provenance, G5 vs opt, DLL resolution, trigger, A/B
- agent: opencode build (Muse Spark)
- provenance: anon (durable review недоступен, личность не выдумывается)
- reviewId: none
- ehaCampaignId: none

## Executive Verdict

Оба падения — `ACCESS_VIOLATION 0xc0000005` в `openvino.dll+0x84b50`, в когерентном g5-окружении старого candidate `01ea946a` (exe `b2612039`, OV 2026.5.0-23005). Смешивания DLL нет (доказано списком модулей из WER). За 35–55 с до каждого падения — штатная работа и тихий конец лога без ошибок. Точный trigger-request на машине НЕ сохранился (UNKNOWN). Единственный GPU-сигнал: `onednn CL_OUT_OF_RESOURCES` + `could not execute a primitive` в соседнем прогоне того же бинаря (05:16:37). Контрольная проба: СТАРЫЙ бинарь на mixed repeated+distinct workload (4 calls) отвечает HTTP 200 без падения. СВЕЖИЙ `fde0762`+`C:\opt` зелёный по всем acceptance-нагрузкам. Итог: `OLD CANDIDATE / OLD RUNTIME PROVENANCE PROBLEM` с ведущей гипотезой GPU-ресурс/состояние (I/H), parser-след `fde0762` к крашу НЕ привязан.

## Crash Evidence

Windows Event Log, ID 1000, оба:

- `Faulting application: ovms.exe 0.0.0.0 (6aa1bdba)`
- `Faulting module: openvino.dll 0.0.0.0 (6a994899)`
- `Exception code: 0xc0000005`, `Fault offset: 0x84b50`
- #1: `2026-09-10 05:14:03`, PID `0x52F0` (21232), Report `f8c4a8fe-...`
- #2: `2026-09-10 05:23:49`, PID `0x70A8` (28840), Report `0e28741a-...`
- Faulting path обоих: `C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\ovms.exe`
- Faulting DLL обоих: `C:\g5\openvino\runtime\bin\intel64\Release\openvino.dll`
- Классификация: `ACCESS_VIOLATION`. НЕ OOM (нет evidence allocation failure).

## Old Candidate Provenance

- `OLD_SOURCE_SHA: 01ea946a5dc8a179a91e8c42e77f0f7a443bc343` (manifest.json, legacy-candidate.json), branch `test/gemmamonster-gate12-20260909-e398363c`, repo dirty=true, tree `3b97ce63...`
- `OVMS_EXE: ...\01ea946a-...\ovms.exe`, size `22929920`, sha256 `b26120393ceeba469858fb0380409cd715c04dcee58a186420448750cc7164d8` (перепроверен на диске — совпадает)
- Build: `short_root=g5`, `openvino_dir=C:\g5\openvino`, `--with_python --with_tests`, `built_at 2026-09-09T20:12:48Z`
- Version string: `Model Server 2026.5.0.ca84db6b`, `OV backend 2026.5.0-23005-9b1d5c9494e`, `GenAI 2026.5.0.0-3421-2e3b291a30e`
- Crashing launches: `runtime/20260910T031017Z` (PID 21232 = crash #1), `runtime/20260910T031925Z` (PID 28840 = crash #2); команда `ovms.exe --config_path ...\tmp\gemmamonster-ovms\gate12-opencode-fast\config.json --rest_port 8888 --port 9000`; модель `gemma-4-26B-...-int4-ov`, имя `gemma4-26-heretic`, DEVICE GPU (fast config: THROUGHPUT, u8 KV, prefix cache)
- Protocol на build: `gemma4_parser_contract_test` FAIL (exit 1), остальные 5 PASS (protocol-summary.json) — unit-уровень, не live crash
- `dll-staging.json`: genai/tokenizers — exact-build копии (`7d4ea32e`/`bf6423ac`), exe untouched

## Fresh Candidate Provenance

- `NEW_SOURCE_SHA: fde0762ba314dc5f6448726dfce7c533bad9a8a6` (`fix(gemma4): allow repeated same-tool calls with parallel_tool_calls=true`)
- `NEW_OVMS: C:\git\model_server-gemma4-fast\bazel-bin\src\ovms.exe`, size `22671872`, sha256 `9926F8B5...68EEA`
- Build: `//src:ovms`, `Build completed successfully, 4040 actions`, `--output_user_root=C:\opt`, `OpenVINO_DIR=C:\opt\openvino\runtime\cmake`; `--version`: Model Server 2026.5.0.ca84db6b, OV backend 2026.4.0-22930, GenAI 2026.4.0.0-3401 (наблюдено; NB: строка флагов `win_mp_on_py_on`)
- OLD vs NEW: разные файлы (22929920 vs 22671872, sha различаются). Старый бинарь НЕ равен свежему — подмены не было.

## Loaded DLL Provenance (crash #2, из WER Report.wer, AppSessionGuid PID 28840)

- `ovms.exe` — vault-копия `01ea946a`
- `openvino.dll` + auto/auto_batch/cpu/gpu/hetero/npu/ir-frontend + `tbb12/bbmalloc/bbbind` — ВСЕ из `C:\g5\openvino\runtime\...` (Release + 3rdparty\tbb)
- `openvino_genai.dll`, `openvino_tokenizers.dll` — colocated staged копии candidate dir (sha совпадают с g5 Release)
- НЕТ модулей из `C:\opt`, НЕТ Debug (`openvinod`) модулей. Смешивание DLL (класс B) — DISPROVEN. DLL из PATH launcher'а (LAUNCH-GUIDE: tbb+Release+Debug из `C:\g5`) — отвечено, почему именно `C:\g5`.

## C:\g5 vs C:\opt Comparison

- G5 `openvino.dll`: `16483080` bytes, sha `25C7B09A...`, `2026.5.0.23005` (source build 9b1d5c9) — sha на диске == sha crashing DLL из runtime-provenance. Файл не менялся.
- Opt `openvino.dll`: `16465168` bytes, sha `829C4642...`, `2026.4.0` (prebuilt).
- `SAME_BINARY: NO`, `SAME_VERSION: NO`, `SAME_BUILD: NO` (source-built 2026.5 vs prebuilt 2026.4).
- Падение произошло НЕ из-за подмены: crashing процесс грузил ровно то дерево, против которого был собран (legacy-candidate `openvino_dir=C:\g5\openvino`). Класс A (build/runtime mismatch) для загруженного сета — DISPROVEN.

## PATH / DLL Resolution

- Краш-процесс: env launcher'а (`C:\g5\...\tbb`, `...\Release`, `...\Debug` + `PYTHONHOME=C:\opt\Python312`) — когерентен g5-сборке.
- Свежий процесс (PID 31584, модули сняты вживую): `openvino.dll`/плагины/`tbb` — все из `C:\opt`, genai/tokenizers — colocated `bazel-bin\src`. Когерентен opt-сборке. G5 в его модулях нет.

## Exact Crash Trigger

- Статус: UNKNOWN. На машине нет client-side request/response артефактов за 05:00–05:30 (искались `*request*/*response*/*prompt*/*chat*` в `C:\gemmamonster-artifacts` и файлы `tmp\` за окно — только launch.json'ы). В gate12-доках краш не описан.
- Timeline #1: старт 05:10:17 → штатные запросы → последняя активность 05:13:31 (`All requests: 0`) → тишина 32 с → AV 05:14:03.
- Timeline #2: старт 05:19:25 → штатные запросы → последняя активность 05:22:55 → тишина 54 с → AV 05:23:49.
- CRASH_STAGE: UNKNOWN (между «ранняя стадия необработанного в логе запроса» и «фоновый поток в idle»). Лог обрывается БЕЗ ошибок в обоих случаях.
- Единственный GPU-сигнал рядом: прогон 031458Z того же бинаря, 05:16:37 — `onednn ... errcode -5, CL_OUT_OF_RESOURCES` → `llm_executor: could not execute a primitive` (процесс позже заменён harness'ом, без WER-события).
- Контекст машины: sporadic LiveKernelEvent P1:141/193 (LAUNCH-GUIDE/WORKING-STATE), свежие `Kernel_141` в WER-очереди 06:19 — iGPU/driver flaky независимо подтверждены.

## A/B Reproduction

- B (NEW fde0762 + C:\opt, coherent): зелёный эталон — single/parallel/repeated/stream/mixed-4-call, HTTP 200, без падений, процессы жили часами. `FRESH_CANDIDATE_CRASH: NO`.
- A-rerun (OLD, coherent g5 env, ONE controlled probe, own fast config, ports 8888/9000): первая попытка с неполным env — тихий exit на старте (без AV, без WER; зафиксировано как env-fidelity artifact, не evidence). Вторая попытка с полным env (PATH+PYTHONHOME+PYTHONPATH+QUEUE=0) — старт, модель AVAILABLE, затем ОДИН mixed workload (weather×3+timezone×1, parallel, required): HTTP 200, корректные 4 calls (`MYN15OiUS/FbiUxcnrs/GHcsRSzZn/tgxyLIoqY`), процесс жив. Старый бинарь repeated same-tool workload НЕ роняет.
- Матрица §14: ближе к Scenario 1 (`OLD CANDIDATE / OLD RUNTIME PROVENANCE PROBLEM`), но триггер неизвестен — Scenario 4 (request-specific) не исключён для НЕпротестированного исторического запроса.

## Crash Dump Analysis / Symbolized Stack

- Полных `.dmp` нет: `LocalDumps` не настроен, `C:\gemmamonster-crashdumps` отсутствует, WER-архив содержит только `Report.wer` (78KB, metadata + module list, без call stack).
- PDB для `openvino.dll+0x84b50` отсутствуют (`*.pdb` в обоих Release-каталогах не найдены).
- Стек: `UNSYMBOLIZED` (явно). Без стека классы E/F/G по коду неразличимы — вердикт строится на provenance + trigger evidence, а не на адресе.

## Root Cause Tree

```text
OVMS CRASH (0xc0000005 @ openvino.dll+0x84b50, 01ea946a/g5-2026.5, GPU)
+-- wrong runtime DLL (B) .................... DISPROVEN (WER module list: coherent g5)
+-- incompatible candidate package (C) ....... DISPROVEN (staged sha == g5 tree; exe untouched)
+-- build/runtime mismatch (A) ............... DISPROVEN для загруженного сета (собран против C:\g5, грузит C:\g5)
+-- ABI mismatch old-exe/new-DLL ............. DISPROVEN (смешивания не было)
+-- old candidate/code defect (parser) ....... UNLIKELY: старый бинарь корректно отработал repeated+parallel probe (HTTP 200); parser-FAIL был unit-level, не live AV
+-- genuine OpenVINO defect (E) .............. UNRESOLVED (без стека/дампа нельзя; детерминированный offset ×2 — подозрительно, но недостаточно)
+-- invalid OVMS state into OpenVINO (F) ..... UNRESOLVED (кандидат: error-path после GPU failure; см. Contributing)
+-- concurrency/lifetime (G) ................. UNRESOLVED (тишина 35–55с + AV намекает на async/background, но это inference, не evidence)
+-- corrupted request/session state (H) ...... UNRESOLVED (trigger-запросы не сохранились)
+-- environment: flaky iGPU/driver (I) ....... LIKELY CONTRIBUTOR: CL_OUT_OF_RESOURCES в соседнем прогоне + LiveKernelEvent 141 + известный flaky driver
```

## Proven Root Cause

Строго доказанного root cause НЕТ (нет стека/дампа/trigger-запроса). Сильнейшее доказанное утверждение: **падения принадлежат старому candidate `01ea946a` в его когерентном g5-окружении и НЕ воспроизводятся ни свежим `fde0762`+`C:\opt`, ни самим старым бинарём на repeated/parallel tool workload; faulting DLL совпадает с build-деревом; общий знаменатель обоих падений — GPU device + молчаливый разрыв 35–55 с + flaky iGPU контекст (CL_OUT_OF_RESOURCES рядом, Kernel_141 на машине)**. Связь с `fde0762` parser path — ОТСУТСТВУЕТ (сессия §18 соблюдена).

## Contributing Factors

- iGPU Intel Arc 140V + driver с LiveKernelEvents; все краш-прогоны — DEVICE GPU.
- `enable_tool_guided_generation`/VLM_CB + u8 KV на Arc — тяжёлый GPU-путь; при `CL_OUT_OF_RESOURCES` error-path GenAI/OVMS может уходить в необработанное исключение → AV (гипотеза, требует стек).
- Debug-каталог в PATH launcher'а (не загрузился, но хрупкость конфигурации).
- Отсутствие сохранения exact request JSON в harness'е — trigger невосстановим post-factum.

## Disproven Hypotheses

- OOM (нет allocation-failure evidence; cache usage в логах <75% от десятков MB; процессный Private в норме).
- Подмена/смешивание DLL (WER-модули + sha).
- «Упал свежий fde0762 бинарь» (faulting path — vault `01ea946a`; свежий бинарь в другом месте с другим sha).
- «Починилось/должно чиниться парсером fde0762» — старый бинарь сам проходит repeated-workload; краш не в parser-слое по имеющимся данным.

## Remaining Unknowns

- Exact trigger requests 05:14/05:23 (клиентские логи не велись).
- Стек `openvino.dll+0x84b50` (нет PDB/дампа).
- Почему AV наступает через 35–55 с тишины (idle-crash vs незалогированный запрос).
- Первый startup-probe exit без env (minor; объяснён неполным env, не расследован глубже — и не нужно).

## Recommended Next Action

1. Включить WER LocalDumps (или procdump `-ma -e 1`) для vault-бинаря и прогнать исторические tool-workloads до повторного AV — нужен стек.
2. Вести exact request/response JSON в harness'е (как в acceptance-сессии сегодня) — иначе trigger снова невосстановим.
3. Повторить длительную GPU-нагрузку с мониторингом LiveKernelEvents: если 141 совпадают с AV — сначала driver/платформа, потом код.
4. Не трогать parser-код по мотивам этого краша (нет связи).

## Handoff

```text
OLD_OVMS_SHA256: b26120393ceeba469858fb0380409cd715c04dcee58a186420448750cc7164d8
OLD_SOURCE_SHA: 01ea946a5dc8a179a91e8c42e77f0f7a443bc343

NEW_OVMS_SHA256: 9926F8B520704CCF429DEB67F4DFF7A76466A749A1AD1700750BEC0DED968EEA
NEW_SOURCE_SHA: fde0762ba314dc5f6448726dfce7c533bad9a8a6

CRASHING_OPENVINO_DLL: C:\g5\openvino\runtime\bin\intel64\Release\openvino.dll
CRASHING_OPENVINO_SHA256: 25c7b09a3cedfefbdf2868a1befb547c83324d9867f7bb480851409d606d3369
BUILD_OPENVINO_DLL: C:\opt\openvino\runtime\bin\intel64\Release\openvino.dll
BUILD_OPENVINO_SHA256: 829c4642e287522f8a8e748a726d4ad3117a701e22ab46adc82771f98e5d2f7e

DLL_MATCH: NO (different builds) / loaded set coherent in both cases
PATH_MATCH: launcher-controlled per candidate, no mixing observed

EXCEPTION: 0xc0000005
FAULT_MODULE: openvino.dll
FAULT_OFFSET: 0x84b50

CRASH_STAGE: UNKNOWN (silent 35-55s gap after normal activity)
REPRODUCIBLE: signature yes (same code/module/offset x2); trigger UNKNOWN

FRESH_CANDIDATE_CRASH: NO
FRESH_CANDIDATE_EXCEPTION: N/A
FRESH_CANDIDATE_OFFSET: N/A

ROOT_CAUSE: not strictly proven; strongest: old-candidate/old-runtime GPU-path failure, likely contributor flaky iGPU (CL_OUT_OF_RESOURCES nearby + Kernel_141); no link to fde0762 parser path
CONFIDENCE: medium (provenance solid, stack/trigger missing)

REPORT: .codesleuth/reports/20260910T063201Z-gemmamonster-openvino-access-violation-investigation.md
DUMP: none (no LocalDumps; WER Report.wer only)
```

## Limitations

- Ни один запрет сессии не нарушен: исходники, rebuild/clean, runtime, модель, профили, DLL не менялись; старый candidate запускался дважды (один startup-exit без AV + один controlled probe), свежий сервер останавливался/перезапускался только как процесс.
- Все серверы на конец сессии остановлены (проверено: `ovms.exe` отсутствует) — пользовательский curl до нового подъёма ходить не будет.
- Отчёт — derived navigation, не acceptance; PASS/FAIL никуда не переносятся.
