---
reportType: documentation
targetSha: 950aa12cffed027fdcb43d715ac136d855e1d178
provenance: anon-d4243c8a62b1
reviewId: 20260909231916-950aa12cffed-eJ7ZWPEh-e6ae864c
---

# Рабочий протокол проверки активности билда

- date: 2026-09-09T23:19:23Z
- target: 950aa12cffed027fdcb43d715ac136d855e1d178
- dirty: yes (untracked: .codesleuth/, .opencode/, AGENTS.md, ovms.exe, runtime/, tools/codesleuth/ и др.)
- scope: поиск процессов компиляторов + живость/активность + логи; проверено на живой сборке `model_server-gate12-repair-20260909`
- agent: opencode build (Muse Spark)
- provenance: anon-d4243c8a62b1
- reviewId: 20260909231916-950aa12cffed-eJ7ZWPEh-e6ae864c
- ehaCampaignId: none

## Summary

Зафиксирован как рабочий протокол из трёх шагов: 1) поиск компиляторов по `Get-Process` + `Win32_Process.CommandLine`, 2) доказательство живости через `Responding`, дельту CPU, ротацию короткоживущих `cl.exe` и рост лога, 3) проверка живого `win_build.log` + `command.log` и отсутствия `ERROR/FAILED`. На момент проверки сборка Bazel (`--output_user_root=C:\g5`, `--jobs=8`, `//src:ovms //src:ovms_test`) была активна: ~4,2xx/6,4xx действий, 8 running, лог +564 байт за 5с.

## Findings

### info: Цепочка сборки идентифицирована по CommandLine
- location: `C:\git\model_server-gate12-repair-20260909\windows_build.bat:1-1`
- evidence: `cmd 1736` запускает `windows_build.bat g5 --with_python --with_tests` → `bazel 34084` (`--output_user_root=C:\g5 build --config=win_mp_on_py_on --jobs=8 --verbose_failures //src:ovms //src:ovms_test //third_party:espeak_ng //third_party:espeak_ng_data`) → `java 27380` (Bazel server, `--workspace_directory=c:\git\model_server-gate12-repair-20260909`, `--output_base=c:\g5\os2nayqe`) → `cl.exe x8` (`C:\BuildTools\VC\Tools\MSVC\14.44.35207\bin\HostX64\x64\cl.exe @bazel-out/.../*.obj.params`) + `tee 34536` (`tee win_build.log`)
- recommendation: всегда начинать с `Win32_Process.CommandLine`, а не только с имени процесса — имя `cl.exe`/`java.exe` без родителя и командной строки не отличает живую сборку от висячих серверов (`java 11724`, `java 26956`)

### info: Живость = Responding + дельта CPU + ротация cl.exe + рост лога
- location: `win_build.log:1-5` (рост 64369 → 64933 байт за 5с)
- evidence: все `Responding=True`; `java 27380` CPU 467.32 → 468.12с за 5с, WS ~984MB, 158 потоков; состав `cl.exe` полностью сменился за 5с (старые PID мертвы, новые стартовали) — норма для `--jobs=8`; хвост лога `[4,212 / 6,453] Compiling tensorflow/lite/kernels/conv.cc; 51s local ... (8 actions running)`
- recommendation: считать билд зависшим только если одновременно: лог не растёт >60с, CPU сервера не растёт, состав `cl.exe` статичен

### info: Логи: живой лог — единственный источник прогресса
- location: `C:\git\model_server-gate12-repair-20260909\win_build.log:1-10`
- evidence: `Select-String -Pattern "ERROR|FAILED|error C"` — совпадений нет; `Get-Content -Tail 40` показывает прогресс `concatenation.cc → conv.cc`; `C:\g5\os2nayqe\command.log` (66KB) свежий; `win_build.log` в `model_server-gemma4-fast` (42798 байт, `Build completed successfully, 925 actions`) — старый, к текущей сборке не относится
- recommendation: смотреть живой лог в репозитории из `workspace_directory` Bazel-сервера, а не в соседнем клоне

## Paths inspected

- `C:\git\model_server-gemma4-fast` — рабочая директория запроса (старый `win_build.log` распознан как нерелевантный)
- `C:\git\model_server-gate12-repair-20260909\win_build.log` — живой лог, рост и хвост проверены
- `C:\g5\os2nayqe\command.log` — серверный лог Bazel, свежесть проверена

## Checks run

- `Get-Process | Select Name,Id,CPU,WorkingSet64,StartTime,Path` — найдены `cl x8`, `bazel`, `java`, `tee`
- `Get-CimInstance Win32_Process | Select Name,ProcessId,ParentProcessId,CommandLine` — построена цепочка `cmd→bazel→java→cl`, отсечены висячие `java 11724/26956`
- Повторный опрос `Get-Process -Id` с интервалом 5с + замер размера `win_build.log` — доказана активность
- `Select-String -Pattern "ERROR|FAILED|error C" win_build.log` — ошибок нет
- `Get-Process -Id 1736,34084,27380,34536 | Select Responding,CPU` — все отвечают

## Recommendations

- Повторно использовать этот порядок: CommandLine → дельта CPU/ротация → хвост живого лога
- Живой лог читать через `Get-Content <живой win_build.log> -Tail 40 -Wait`
- Висячие `java` от старых `output_base` (`_bazel_*`, `g12repair`) гасить только после проверки их `CommandLine`

## Limitations

- CWD `cmd 1736` выведена из `CommandLine`/`workspace_directory`, прямого поля CWD в `Win32_Process` нет
- `wmic` отсутствует в окружении — не использовался
- Проверены только MSVC/Bazel-процессы; `link.exe`/`ml64.exe` в момент опроса не наблюдались
- Отчёт — производная навигация, не EHA/acceptance; PASS никуда не переносится
