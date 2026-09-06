Тема: снимок незакрытой Gemma4 reliability-кампании (test-only, без merge)

Коллеги,

фиксирую текущее состояние тестовой сессии в отдельной ветке
`test/gemma4-reliability-snapshot`, чтобы живое дерево
`C:\git\model_server-gemma4-clean` (`test/gemma4-reliability-grounded-facts`)
можно было не трогать: там ещё пишет harness, а дальше пойдёт новая задача.

Это не production-фикс и не финальный supervisor-отчёт. Production SHA
`908bc8b7e3bdd24ddd5eb9b27bbe15bcffb00703` не менялся. В коммите только
контрактные тесты, harness, partial evidence и runbook.

Что уже видно на Intel GPU / OVMS `2026.4.0.908bc8b7` / порт `:18000` /
модель `gemma4-26-heretic` (245 trials на момент заморозки):

- named и required, t=0 seed=42: 80/80 PASS, exact `commit_sha` живёт;
- auto почти везде ломается не выбором тула, а G: модель дописывает
  выдуманный `sha256` (часто hash пустой строки `e3b0c44…`);
- auto A4 (t=0.9 + seed=42) наоборот 15/15 PASS;
- thinking off при t=0 повторяет A1 (30/30 G); thinking on при t=0 почти
  не спасает (1/30 PASS);
- thinking 0.9 и Campaign B не доехали.

Практический runbook (рабочий PYTHONHOME, запрет `setupvars.ps1`, запрет
Bazel параллельно с 26B, resume-команда) лежит в
`docs/gemma4/reliability-campaign-runbook.md`.

Code-contract тесты в этом коммите есть, но не гонялись: Bazel на этой
машине конкурирует с live OVMS за память. Прогон — отдельным шагом,
когда сервер можно остановить.

Просьба: не мержить, не путать с review-веткой
`fix/gemma4-final-toolcalling-review`. Live-кампанию продолжать только из
грязного worktree `model_server-gemma4-clean`, resume-safe jsonl уже там.

С уважением,
агент сессии reliability / grounded-facts
