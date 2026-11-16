import CryptoKit
import Foundation

struct Message: Codable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
}

enum LocalModelError: LocalizedError {
    case download, checksum, load, prompt, generation

    var errorDescription: String? {
        switch self {
        case .download: return "Сервер не отдал файл модели. Попробуй ещё раз."
        case .checksum: return "Файл модели загрузился с ошибкой. Скачай его снова."
        case .load: return "Не удалось загрузить модель. Освободи память и попробуй снова."
        case .prompt: return "Сообщение слишком длинное. Разбей его на части."
        case .generation: return "Модель прервала ответ. Попробуй ещё раз."
        }
    }
}

enum ModelFiles {
    static let remoteURL = URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!
    static let checksum = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
    static let directory = URL.applicationSupportDirectory.appending(path: "Caleb", directoryHint: .isDirectory)
    static let weights = directory.appending(path: "qwen2.5-1.5b-instruct-q4_k_m.gguf")
    static let history = directory.appending(path: "chat.json")
    static let availablePhrase = "Qwen2.5 1.5B"

    static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

actor LocalModel {
    private var engine: OpaquePointer?

    deinit {
        if let engine { caleb_close(engine) }
    }

    func install(file: URL) throws {
        try ModelFiles.prepareDirectory()
        let staged = ModelFiles.directory.appending(path: UUID().uuidString)
        try FileManager.default.moveItem(at: file, to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }
        let handle = try FileHandle(forReadingFrom: staged)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == ModelFiles.checksum else { throw LocalModelError.checksum }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staged, to: ModelFiles.weights)
        var fileURL = ModelFiles.weights
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? fileURL.setResourceValues(values)
    }

    func generate(_ history: [Message], onText: @Sendable (String) async -> Void) async throws {
        try Task.checkCancellation()
        if engine == nil {
            engine = ModelFiles.weights.path.withCString { caleb_open($0) }
        }
        guard let engine else { throw LocalModelError.load }
        try Task.checkCancellation()
        var recent = Array(history.suffix(13))
        if recent.first?.role == .assistant { recent.removeFirst() }
        while true {
            let result = Self.prompt(recent).withCString { caleb_begin(engine, $0, 384) }
            if result == 0 { break }
            if result < 0 { throw LocalModelError.generation }
            guard recent.count > 2 else { throw LocalModelError.prompt }
            recent.removeFirst(2)
        }
        while true {
            try Task.checkCancellation()
            let result = caleb_prefill(engine)
            if result > 0 { break }
            if result < 0 { throw LocalModelError.generation }
        }

        var buffer = [CChar](repeating: 0, count: 512)
        var pending = [UInt8]()
        var output = ""
        var lastUpdate = ContinuousClock.now
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBufferPointer {
                caleb_next(engine, $0.baseAddress!, $0.count)
            }
            if count == 0 { break }
            if count < 0 { throw LocalModelError.generation }
            pending.append(contentsOf: buffer.prefix(Int(count)).map(UInt8.init(bitPattern:)))
            if let text = String(bytes: pending, encoding: .utf8) {
                output += text
                pending.removeAll(keepingCapacity: true)
            } else if pending.count > 32 {
                output += String(decoding: pending, as: UTF8.self)
                pending.removeAll(keepingCapacity: true)
            }
            if !output.isEmpty, ContinuousClock.now - lastUpdate >= .milliseconds(45) {
                await onText(output)
                output = ""
                lastUpdate = .now
            }
        }
        output += String(decoding: pending, as: UTF8.self)
        if !output.isEmpty { await onText(output) }
    }

    private static func prompt(_ messages: [Message]) -> String {
        var prompt = "<|im_start|>system\nТы Caleb, дружелюбный собеседник. Отвечай ясно, кратко и на языке пользователя.<|im_end|>\n"
        for message in messages {
            let text = message.text
                .replacingOccurrences(of: "<|", with: "<｜")
                .replacingOccurrences(of: "\0", with: "")
            prompt += "<|im_start|>\(message.role.rawValue)\n\(text)<|im_end|>\n"
        }
        return prompt + "<|im_start|>assistant\n"
    }
}
