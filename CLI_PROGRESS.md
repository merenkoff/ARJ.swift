# ARJ CLI Progress Log

Цей файл — жива дорожня карта, щоб можна було легко продовжити роботу з будь-якого місця.

## Stage 1: Stabilize Current v1 Behavior
- [x] Базовий `arj` executable доданий у SwiftPM.
- [x] Read-команди (`l,v,t,e,x,p,s,w,c-read`) працюють.
- [x] Write-команди заведені як stubs (exit 2).
- [x] Вирівняти парсинг switch-ів (`-z`, `-w`, `-!`, тощо) і додати regression-тести.
- [x] Добити покриття ключових ARJ-compatible exit-codes у CLI тестах (`2`, `3`, `9`, базові success paths).

## Stage 2: CLI Correctness & DX
- [x] Додати snapshot/золотий тест для `v` (verbose формат).
- [x] Додати тести на `-g` (відсутній/невірний пароль -> exit 3).
- [ ] Додати тести на `!listfile` та `-x<mask>` фільтрацію.
- [ ] Підчистити help/usage (консистентні підказки для команд).

## Stage 3: Read-mode Feature Parity (safe scope)
- [ ] Уточнити поведінку `e/x` для `-p/-p1/-e` в edge-cases.
- [ ] Покращити `w` (search) для текстових патернів/кодувань.
- [ ] Узгодити `c` (show comment) з очікуваним ARJ-стилем виводу.

## Stage 4: Write Roadmap Preparation (без реалізації writer)
- [ ] Специфікувати мінімальний `ARJWriter` API (дизайн-док).
- [ ] Виписати контракт для перших write-команд (`a`, `d`, `c-write`).
- [ ] Підготувати fixture-план для write-тестів.

---

## Session Notes

### 2026-05-08
- Розпочато ітерацію після первинного впровадження плану.
- Закрито баг у `ARJArgvPreprocessor`: `-w/-z` тепер коректно парсяться (було помилкове `,` замість `||`).
- Додано regression CLI тести:
  - `c ... -z<file>` -> write-stub, exit `2`.
  - `l ... -w<dir>` приймається як no-op switch.
  - encrypted fixture без пароля / з невірним паролем -> exit `3`.
- Stage 2.1: додано snapshot test для `arj v` (`verbose_multi_file.txt`) + інтегровано snapshots у `Package.swift` ресурси `arjTests`.
