---
reportType: documentation
targetSha: fde0762ba314dc5f6448726dfce7c533bad9a8a6
provenance: anon
reviewId: none
---

# Где рантайм OVMS на Windows + запомненный ovms.exe

- date: 2026-09-10T05:39:36Z
- target: fde0762ba314dc5f6448726dfce7c533bad9a8a6
- dirty: yes (M *.sh при `git status --ignore-submodules=all`; полный статус без флага падает на stale worktree-submodule, см. Limitations)
- scope: где рантайм для `bazel-bin/src/ovms.exe`; что лежит в `runtime/`; фиксация запомненного exe (size/hash/mtime)
- agent: opencode build (Muse Spark)
- provenance: anon (sidecar недоступен: `review_state_start` падает на окружении, личность не выдумывается)
- reviewId: none
- ehaCampaignId: none

## Summary

`runtime/` в корне репо — не рантайм, а логи запусков (`runtime/gemmamonster-*`). Настоящий Windows-рантайм — `C:\opt\openvino\runtime` (symlink на `C:\opt\openvino_genai_windows_2026.4.0.0rc1_x86_64`), DLL — в `runtime\bin\intel64\Release`. `WORKSPACE` пинит оба репозитория (`windows_openvino`, `windows_genai`) на этот путь, а `windows_setupvars.bat` кладёт рантайм в `PATH` через `C:\opt\openvino\setupvars.bat`. Запомненный `bazel-bin\src\ovms.exe`: 22671872 байт, `2026-09-10 07:30:30`, SHA256 `9926F8B5…68EEA` (полный ниже) — сверен повторным `Get-FileHash`. Рядом с exe лежит только подмножество DLL; ядра `openvino.dll` там нет, оно приходит из `C:\opt`.

## Findings

### info: `runtime/` в репо — логи, не рантайм
- location: `runtime:1-6` (каталог: 6 записей `gemmamonster-*`)
- evidence: `glob runtime/**/*` возвращает только `ovms.stdout.log`, `ovms.stderr.log`, плюс `ovms.command.json` / `graph.pbtxt` / `config.json` в `runtime/gemmamonster-ovms/`; бинарных DLL и `setupvars` там нет
- recommendation: не искать рантайм в `runtime/`; это артефакты запусков

### info: настоящий рантайм — `C:\opt\openvino\runtime`
- location: `C:\opt\openvino\runtime\bin\intel64\Release`
- evidence: `C:\opt\openvino` — SymbolicLink на `C:\opt\openvino_genai_windows_2026.4.0.0rc1_x86_64`; каталог `runtime/` содержит `bin include lib cmake 3rdparty setupvars.bat version.txt`; `bin\intel64\Release` содержит `openvino.dll`, `openvino_c.dll`, `openvino_genai.dll`, `openvino_tokenizers.dll`, `openvino_*_frontend.dll`, `openvino_intel_*_plugin.dll` и др. (проверено `Get-ChildItem`)
- recommendation: для запуска/диагностики смотреть этот каталог и `version.txt`

### info: `WORKSPACE` пинит рантайм на `C:\opt\openvino\runtime`
- location: `WORKSPACE:260-270`
- evidence: `windows_openvino` (`path = "C:\\opt\\openvino\\runtime"`, build `@//third_party/openvino:openvino_windows.BUILD`) и `windows_genai` (`path = "C:\\opt\\openvino\\runtime"`, build `@//third_party/genai:genai_windows.BUILD`); рядом `windows_opencv` → `C:\opt\opencv_4.14.0`
- recommendation: смену рантайма делать через этот пин + `setupvars`, а не копированием DLL вручную

### info: `PATH` на рантайм ставит `windows_setupvars.bat`
- location: `windows_setupvars.bat:52-56`
- evidence: `set "openvinoBatch=call C:\opt\openvino\setupvars.bat"` и вызов `%openvinoBatch%` с проверкой `errorlevel`; рядом аналогично `opencvBatch` из `C:\opt\opencv_<ver>\setup_vars_opencv4.cmd`. Сам bat не исполнялся, только прочитан
- recommendation: перед ручным запуском `ovms.exe` выполнять этот bat (или читать результирующий `PATH` из него)

### info: запомненный `ovms.exe` — identity зафиксирована
- location: `bazel-bin\src\ovms.exe`
- evidence: `FullName C:\git\model_server-gemma4-fast\bazel-bin\src\ovms.exe`, `Length 22671872`, `LastWriteTime 09/10/2026 7:30:30`, `SHA256 9926F8B520704CCF429DEB67F4DFF7A76466A749A1AD1700750BEC0DED968EEA` — повторный `Get-FileHash` сошёлся с ранее предъявленным значением
- recommendation: использовать этот hash как baseline; при пересборке фиксировать новый

### info: рядом с exe — только подмножество DLL
- location: `bazel-bin\src\*.dll`
- evidence: `Get-ChildItem` показывает `openvino_genai.dll`, `openvino_tokenizers.dll`, `opencv_world4140.dll`, `libcurl-x64.dll`, `git2.dll`, `python312.dll`; `openvino.dll` / `openvino_c.dll` / плагинов там нет. `ovms.exe.runfiles_manifest:1-18` перечисляет те же копии из `C:/opt/bvmxypto/...` (genai, tokenizers, opencv, curl, git2, zlib) — полного OpenVINO-ядра в манифесте нет
- recommendation: отсутствие `openvino.dll` рядом с exe — норма, а не битая сборка; ядро резолвится из `C:\opt` через `setupvars`

## Paths inspected

- `runtime/` — состав каталога и `glob runtime/**/*`
- `bazel-bin\src\ovms.exe` + `bazel-bin\src\*.dll` + `bazel-bin\src\ovms.exe.runfiles_manifest:1-18`
- `WORKSPACE:250-294` — пины `windows_openvino` / `windows_genai` / `windows_opencv`
- `windows_setupvars.bat:1-82` — простановка `PATH` на рантайм
- `C:\opt`, `C:\opt\openvino`, `C:\opt\openvino\runtime`, `C:\opt\openvino\runtime\bin\intel64\Release`
- `.codesleuth/reports/INDEX.md` + `20260909T231923Z-build-activity-check-protocol.md` — проверка на дубликат (scope другой)

## Checks run

- `Get-Item bazel-bin\src\ovms.exe` + `(Get-FileHash ...).Hash` — сошлось с предъявленным hash
- `Get-ChildItem bazel-bin\src` и `bazel-bin\src\*.dll` — состав DLL рядом с exe
- `read runtime/` + `glob runtime/**/*` — доказано: только логи/конфиги
- `read bazel-bin\src\ovms.exe.runfiles_manifest` — 18 строк, подмножество DLL
- `Get-Item C:\opt\openvino` (Target/LinkType) + `Get-ChildItem C:\opt\openvino\runtime` + `...\bin\intel64\Release` — ядро рантайма
- `Select-String WORKSPACE -Pattern openvino|windows_genai|windows_opencv` + `read WORKSPACE:250-294`
- `read windows_setupvars.bat` — строки 52-56
- `git rev-parse HEAD` → `fde0762b...`; `git branch --show-current`; `git log --oneline -3`; `git status --ignore-submodules=all` — dirty yes (M *.sh)
- `.opencode\bin\codesleuth-reports.ps1 --repo . sync` — `status: synced`, `imported: 0`
- `review_state_start` (documentation) — FAILED окружением, не данными (см. Limitations); `review_state_load` — только старый review на `950aa12c...` (stale, чужой SHA, не переиспользован)
- `python tools/codesleuth/scripts/contributor_antipatterns.py prewrite` — без ERROR (только WARN + semantic checklist SC-01..SC-03 разобран)

## Recommendations

- Ручной запуск exe делать после `windows_setupvars.bat` и сверять `PATH` на `C:\opt\openvino\runtime\bin\intel64\Release`
- Hash `9926F8B5…68EEA` держать как baseline запомненного exe; при новой сборке — новая фиксация, не правка этой
- Починить worktree-окружение (stale `tools/codesleuth` gitdir + `bazel-*` submodule-записи), чтобы `review_state_*` снова работал; до этого новые отчёты честно идут с `provenance: anon`

## Limitations

- Durable review не создан: `review_state_start` падает с `fatal: not a git repository: tools/codesleuth/.../modules/codesleuth` + `'git status --porcelain=2' failed in submodule bazel-model_server-gemma4-fast` (корень: `.git` — worktree-файл на `C:/git/model_server-gemma4-clean/...`, `.gitmodules` отсутствует, в локальном конфиге есть `submodule.codesleuth.*` и `ignore=all`). Поэтому `provenance: anon` без watermark; личность не выдумывалась, старый watermark `anon-d4243c8a62b1` (чужой HEAD `950aa12c`) не переиспользован
- Dirty-статус приближённый: точный `git status` без `--ignore-submodules=all` в этом worktree невозможен (см. выше)
- `setupvars.bat` из `C:\opt\openvino` прочитан частично (первые 40 строк через `Get-Content`); результирующий `PATH` исполнением не снимался
- `ovms.exe` не запускался; зависимости через dumpbin/Dependencies не разбирались; `version.txt` рантайма не читался
- Отчёт — производная навигация, не EHA/acceptance; PASS никуда не переносится
