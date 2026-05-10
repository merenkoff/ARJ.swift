# ARJ Write Implementation Progress

Живой план внедрения write-функционала итерациями.

## Iteration 1 (in progress)

- [x] Создать трекер итераций.
- [x] Реализовать минимальный `ARJWriter` (stored-only rewrite).
- [x] Подключить `c -z<file>` к writer (вместо stub).
- [x] Подключить `d` (delete by masks) к writer.
- [x] Подключить `a` (add files) к writer (базовый scope).
- [x] Обновить CLI-тесты под новые write-paths.

## Iteration 2 (next)

- [ ] Улучшить `a` для mask/listfile edge-cases.
- [ ] Уточнить overwrite/model поведения.
- [ ] Добавить больше fixture-driven write тестов.

## Iteration 3 (later)

- [ ] Подготовить расширение под `u/f` поверх тех же примитивов.
- [ ] Тонкая ARJ-совместимость по сообщениям и exit-level нюансам.
