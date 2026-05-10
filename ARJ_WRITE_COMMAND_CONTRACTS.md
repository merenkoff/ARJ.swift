# ARJ Write Command Contracts (Stage 4.2)

Цель: описать стабильный CLI-контракт для первых write-команд (`a`, `d`, `c-write`) поверх минимального `ARJWriter` API из `ARJ_WRITER_API_MINIMAL.md`.

## Scope

Контракт покрывает:

- синтаксис команд;
- обязательные/необязательные параметры;
- маппинг в `ARJWriterChange`;
- ожидаемые exit codes;
- минимальные UX-правила сообщений.

Вне scope:

- фактическая реализация writer;
- legacy-совместимость 1:1 по всем редким ключам;
- chapter/write advanced operations.

## Common rules (for all three commands)

1. `archive` (позиционный аргумент #1) обязателен.
2. Все команды в write-режиме используют pipeline: `inputArchive -> temp output -> atomic replace`.
3. При флаге `-y` подтверждения не запрашиваются.
4. `-g<password>` применяется при чтении encrypted input и при записи encrypted output (если поддержано опциями writer).
5. Ошибки должны маппиться в `ARJExitCode` без прямого `fatalError`.

## Command `a` (add)

ARJ-смысл: добавить файлы в архив.

### CLI contract

```bash
arj a <archive> [base_dir] [files/masks...]
```

Поддерживаемые ключи (v1):

- `-m0..4` — compression method;
- `-r` — рекурсивный обход для директорий в input;
- `-y` — без интерактивных prompt;
- `-g<password>` — пароль;
- `-x<mask>` — исключения среди входных файлов.

### Mapping to writer

- Из `base_dir + files/masks` собирается список `ARJAddInput`.
- Формируется change:

```swift
.add([ARJAddInput])
```

- Вызов:

```swift
ARJWriter.apply(
    inputArchive: archiveURL,
    outputArchive: tempURL,
    changes: [.add(inputs)],
    options: writerOptions
)
```

### Validation rules

- если нет ни одного входного файла после фильтрации -> exit `1` (warning);
- если archive отсутствует и режим "create-on-missing" не включён -> exit `6`;
- если указан неподдерживаемый метод `-m` -> exit `2`.

## Command `d` (delete)

ARJ-смысл: удалить файлы из архива по маскам.

### CLI contract

```bash
arj d <archive> [masks...]
```

Поддерживаемые ключи (v1):

- `-y` — без prompt;
- `!<file>` — список масок из файла;
- `-x<mask>` — исключить часть масок удаления (защитный фильтр);
- `-g<password>` — пароль для encrypted archive.

### Mapping to writer

- Нормализуется итоговый набор масок удаления (позиционные + listfile - excludes).
- Формируется change:

```swift
.delete(ARJDeleteSelector(masks: normalizedMasks))
```

- Вызов `ARJWriter.apply(...)` аналогично `a`.

### Validation rules

- пустой набор масок удаления -> exit `7` (user parameter error);
- не найдено ни одного совпадения по маскам -> exit `1` (warning);
- при ошибке чтения archive -> exit `6/7`.

## Command `c-write` (set archive comment)

ARJ-смысл: изменить комментарий архива (write-ветка команды `c`).

### CLI contract

```bash
arj c <archive> -z<file>
```

Поддерживаемые ключи (v1):

- `-z<file>` — обязательный источник нового комментария;
- `-y` — без prompt;
- `-g<password>` — пароль.

Поведение:

- `arj c <archive>` без `-z` остаётся read-mode (show comment);
- `arj c <archive> -z<file>` активирует write-mode (`c-write`).

### Mapping to writer

- comment читается из `-z<file>` (UTF-8 с fallback ISO-8859-1);
- формируется change:

```swift
.setArchiveComment(commentText)
```

- вызов через `ARJWriter.apply(...)`.

### Validation rules

- `-z` пустой/файл не существует -> exit `7` или `6`;
- комментарий > установленного лимита формата -> exit `2`;
- при успешном обновлении -> exit `0`.

## Output / UX contract

Минимальный stderr/stdout контракт:

- `a`: `Added: <n>, Skipped: <m>`;
- `d`: `Deleted: <n>, Not matched: <m>`;
- `c-write`: `Archive comment updated`.

Ошибки:

- единый префикс `arj: ...`;
- человекочитаемая причина + switch/arg, вызвавший ошибку.

## Exit code matrix

- `0` success: операция применена;
- `1` warning: частичный успех / нет совпадений по маске;
- `2` fatal/not supported: невалидная write-операция или ограничение формата;
- `3` password/crypto;
- `5` disk full/write failure;
- `6` cannot open input;
- `7` parameter/file I/O user-side;
- `9` invalid archive.

## Minimal acceptance tests (Stage 4.2)

1. `a`: добавление одного файла в новый temp-output и проверка entry.
2. `a`: `-x<mask>` исключает часть входа.
3. `d`: удаление по маске реально уменьшает набор entries.
4. `d`: удаление по несуществующей маске возвращает warning (`1`).
5. `c-write`: `-z` меняет `archiveComment`.
6. `c-write`: `-z` на отсутствующий файл возвращает `6/7`.

## Stage linkage

Этот документ закрывает Stage 4.2 и напрямую задаёт требования для Stage 4.3 (fixture-план и тестовые сценарии writer-команд).
