# ARJ Write Fixtures Plan (Stage 4.3)

Цель: определить минимальный, но достаточный набор фикстур и сценариев для тестирования write-команд (`a`, `d`, `c-write`) до реализации полноценного writer.

## Principles

1. Фикстуры должны быть маленькими и детерминированными.
2. Каждый сценарий проверяет одну ключевую семантику.
3. Все write-тесты должны работать через temp-copy архива, не модифицируя исходные файлы в `Tests/.../Fixtures`.
4. Проверки делать через публичный `ARJArchive` API (entries/extract/comment), без внутренних хаков.

## Directory layout (proposed)

```text
Tests/arjTests/FixturesWrite/
  base_empty.arj
  base_single.arj
  base_multi.arj
  base_encrypted.arj
  inputs/
    alpha.txt
    beta.bin
    nested/docs/readme.md
    nested/bin/tool.dat
    cp1251.txt
  comments/
    short_comment.txt
    multiline_comment.txt
    long_comment.txt
  masks/
    delete_docs.txt
    delete_all_txt.txt
```

## Fixture catalog

### 1) `base_empty.arj`

- архив без entries, без comment;
- нужен для add в «чистый» контейнер.

### 2) `base_single.arj`

- 1 entry: `alpha.txt`;
- нужен для минимальных delete/comment smoke-тестов.

### 3) `base_multi.arj`

- entries: `alpha.txt`, `beta.bin`, `nested/docs/readme.md`, `nested/bin/tool.dat`;
- нужен для mask-based delete и конфликтных сценариев.

### 4) `base_encrypted.arj`

- простой encrypted fixture с валидным паролем (`secret`);
- нужен для exit-code веток `3` и позитивного сценария с `-g`.

### 5) `inputs/*`

- набор файлов-источников для `a`;
- включает nested-path и не-ASCII контент (`cp1251.txt`).

### 6) `comments/*`

- `short_comment.txt` — 1 строка;
- `multiline_comment.txt` — несколько строк;
- `long_comment.txt` — заведомо длинный (для error-path по лимиту).

### 7) `masks/*`

- listfile-маски для delete, чтобы покрыть `!<file>` контракт.

## Test matrix by command

## `a` (add)

1. add single file -> entry появляется и извлекается корректно.
2. add nested files с `-r` -> пути сохраняются по контракту.
3. add с `-x*.bin` -> `beta.bin` не попадает в архив.
4. add в encrypted archive без `-g` -> exit `3`.
5. add с неподдерживаемым `-m` -> exit `2`.

## `d` (delete)

1. delete по `*.txt` -> txt entries удалены, остальные живы.
2. delete по listfile (`!delete_docs.txt`) -> удаляются только целевые пути.
3. delete по несуществующей маске -> warning exit `1`.
4. delete в encrypted archive без пароля -> exit `3`.

## `c-write`

1. set short comment (`-zshort_comment.txt`) -> comment обновлён.
2. set multiline comment -> формат чтения/вывода корректен.
3. set long comment -> ожидаемая ошибка (exit `2`, если лимит превышен).
4. missing `-z` file -> exit `6/7`.

## Reusable helpers (tests)

Предлагаемые helper-функции в `ARJCLITests`/новом test target:

- `copyFixtureToTemp(_ name: String) -> URL`
- `runARJ(_ args: [String]) -> (out: String, err: String, status: Int32)`
- `entries(in archive: URL) -> [String]`
- `extractText(_ archive: URL, _ path: String, password: String?) -> String`
- `readArchiveComment(_ archive: URL) -> String?`

## Determinism and CI stability

1. Всегда работать в уникальной temp-директории (`UUID()`).
2. Не зависеть от локали/таймзоны в assertions.
3. Для текстов с кодировками сравнивать байты либо явно заданную decoding strategy.
4. Не использовать внешние бинарники в write-тестах.

## Stage 4.3 acceptance criteria

- Есть документированный набор fixture-файлов и назначение каждого.
- Для `a/d/c-write` есть покрытие позитивных и error/warning веток.
- Определены reusable test helpers.
- План готов к прямой реализации в тестах после появления `ARJWriter`.
