# ARJWriter Minimal API (Stage 4.1)

Цель: зафиксировать минимальный контракт `ARJWriter`, достаточный для первых write-команд (`a`, `d`, `c-write`) без преждевременного усложнения.

## Scope v1

`ARJWriter` в v1 должен уметь:

1. Читать существующий архив и его метаданные.
2. Формировать новый архив как результат операции (copy-on-write).
3. Добавлять/удалять entries на уровне payload + заголовков.
4. Обновлять archive comment.
5. Возвращать ARJ-совместимые ошибки для CLI mapping.

Вне scope v1:

- multi-volume;
- chapter operations (`ac/cc/dc`);
- solid blocks и продвинутые оптимизации;
- полная совместимость со всеми экзотическими флагами legacy ARJ.

## API Proposal

```swift
import Foundation

public struct ARJWriterOptions: Sendable, Equatable {
    public var compressionMethod: ARJCompressionMethod
    public var password: String?
    public var preserveTimestamps: Bool
    public var lowercaseNames: Bool
    public var overwriteBehavior: ARJOverwriteBehavior
}

public enum ARJOverwriteBehavior: Sendable, Equatable {
    case errorIfExists
    case replace
}

public struct ARJAddInput: Sendable, Equatable {
    public var sourceURL: URL
    public var archivePath: String
    public var comment: String?
}

public struct ARJDeleteSelector: Sendable, Equatable {
    public var masks: [String]
}

public enum ARJWriterChange: Sendable, Equatable {
    case add([ARJAddInput])
    case delete(ARJDeleteSelector)
    case setArchiveComment(String?)
}

public struct ARJWriterResult: Sendable, Equatable {
    public var outputURL: URL
    public var entriesAdded: Int
    public var entriesDeleted: Int
    public var commentChanged: Bool
}

public protocol ARJWriter {
    static func apply(
        inputArchive: URL,
        outputArchive: URL,
        changes: [ARJWriterChange],
        options: ARJWriterOptions
    ) throws -> ARJWriterResult
}
```

## Why this shape

- Один `apply(...)` покрывает первые сценарии и упрощает CLI-адаптер.
- `inputArchive` + `outputArchive` делают поведение безопасным и тестопригодным.
- `ARJWriterChange` позволяет естественно наращивать write-команды без ломки API.
- Отдельный `ARJWriterResult` удобен для CLI progress/summary и будущих integration тестов.

## Error Contract (for CLI)

Рекомендуемые ошибки (внутри `ARJError`/writer-specific wrapper):

- invalidInputFile / cannotReadInput -> exit 6/7;
- cannotWriteOutput / diskFull -> exit 5/7;
- unsupportedCompressionMethod -> exit 2;
- passwordRequired / wrongPassword -> exit 3;
- malformedArchive / invalidSignature -> exit 9.

Требование: writer-ошибки должны маппиться в уже существующий `ARJExitCode`.

## Minimal test plan for API

1. `add`: добавить 1 текстовый файл, проверить наличие entry и содержимое.
2. `delete`: удалить entry по маске, убедиться что остальные сохранены.
3. `setArchiveComment`: записать и затем прочитать comment.
4. `replace output`: при существующем output и `replace` операция успешна.
5. `errorIfExists`: при существующем output операция падает ожидаемой ошибкой.

## Stage 4 integration note

Этот документ закрывает Stage 4.1 (дизайн минимального API) и служит базой для:

- Stage 4.2: контрактов команд `a`, `d`, `c-write`;
- Stage 4.3: фикстур и end-to-end write тестов.
