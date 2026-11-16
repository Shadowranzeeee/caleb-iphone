import SwiftUI

@main
struct CalebApp: App {
    var body: some Scene {
        WindowGroup {
            ChatScreen()
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
final class ChatState: ObservableObject {
    @Published private(set) var messages: [Message] = []
    @Published private(set) var ready = FileManager.default.fileExists(atPath: ModelFiles.weights.path)
    @Published private(set) var downloading = false
    @Published private(set) var answering = false
    @Published var error: String?
    @Published var input = ""

    private let model = LocalModel()
    private var task: Task<Void, Never>?

    init() {
        if let data = try? Data(contentsOf: ModelFiles.history),
           let saved = try? JSONDecoder().decode([Message].self, from: data) {
            messages = saved
        }
    }

    func download() {
        guard task == nil, !ready else { return }
        downloading = true
        error = nil
        task = Task { [weak self, model] in
            defer {
                self?.downloading = false
                self?.task = nil
            }
            do {
                let (file, response) = try await URLSession.shared.download(from: ModelFiles.remoteURL)
                defer { try? FileManager.default.removeItem(at: file) }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw LocalModelError.download
                }
                try Task.checkCancellation()
                try await model.install(file: file)
                self?.ready = true
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self?.error = error.localizedDescription }
            }
        }
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard task == nil, ready, !text.isEmpty else { return }
        input = ""
        error = nil
        messages.append(Message(role: .user, text: text))
        persist()
        let history = messages
        let reply = Message(role: .assistant, text: "")
        messages.append(reply)
        answering = true
        task = Task { [weak self, model] in
            defer { self?.finish(reply: reply.id) }
            do {
                try await model.generate(history) { [weak self] text in
                    guard let self else { return }
                    await self.append(text, to: reply.id)
                }
                if self?.messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    self?.error = LocalModelError.generation.localizedDescription
                }
            } catch is CancellationError {
            } catch {
                self?.error = error.localizedDescription
            }
        }
    }

    func stop() { task?.cancel() }

    func clear() {
        guard task == nil else { return }
        messages = []
        error = nil
        persist()
    }

    private func append(_ text: String, to id: UUID) {
        guard messages.last?.id == id else { return }
        messages[messages.count - 1].text += text
    }

    private func finish(reply: UUID) {
        if messages.last?.id == reply,
           messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            messages.removeLast()
        }
        answering = false
        task = nil
        persist()
    }

    private func persist() {
        do {
            try ModelFiles.prepareDirectory()
            try JSONEncoder().encode(messages).write(to: ModelFiles.history, options: .atomic)
        } catch {
            self.error = "Не удалось сохранить историю на iPhone."
        }
    }
}

@MainActor
private struct ChatScreen: View {
    @StateObject private var state = ChatState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmClear = false

    private let surface = Color(red: 0.09, green: 0.085, blue: 0.12)
    private let accent = Color(red: 0.77, green: 0.67, blue: 1)

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.ready {
                conversation
                composer
            } else {
                onboarding
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.045, green: 0.042, blue: 0.065).ignoresSafeArea())
        .tint(accent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.23), value: state.ready)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, state.answering { state.stop() }
        }
        .alert("Очистить историю?", isPresented: $confirmClear) {
            Button("Очистить", role: .destructive) { state.clear() }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Caleb", isPresented: Binding(
            get: { state.error != nil },
            set: { if !$0 { state.error = nil } }
        )) {
            Button("OK") { state.error = nil }
        } message: {
            Text(state.error ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            mark(size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("Caleb").font(.headline.weight(.semibold))
                if state.ready {
                    Label("На iPhone", systemImage: "circle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(accent)
                        .labelStyle(.titleAndIcon)
                }
            }
            Spacer()
            if !state.messages.isEmpty {
                Button { confirmClear = true } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .disabled(state.answering)
                .accessibilityLabel("Очистить историю")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
    }

    private var onboarding: some View {
        ScrollView {
            VStack(spacing: 15) {
                mark(size: 76)
                    .padding(.bottom, 8)
                Text("Локальный чат")
                    .font(.largeTitle.bold())
                Text("Скачай \(ModelFiles.availablePhrase) один раз. После этого Caleb отвечает без интернета.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
                if state.downloading {
                    ProgressView("Загружаю и проверяю модель…").padding(.top, 10)
                    Button("Отменить", action: state.stop)
                } else {
                    Button(action: state.download) {
                        Label("Скачать модель · ≈1 ГБ", systemImage: "arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .foregroundStyle(.black)
                    .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 36)
        }
        .transition(.opacity)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if state.messages.isEmpty {
                        VStack(spacing: 13) {
                            mark(size: 62)
                            Text("О чём поговорим?").font(.title2.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 58)
                    }
                    ForEach(state.messages) { message in
                        bubble(message)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Color.clear.frame(height: 1).id("chat-end")
                }
                .padding(18)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: state.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: state.messages.last?.text.count) {
                if let last = state.messages.last, last.role == .user || state.answering {
                    proxy.scrollTo("chat-end", anchor: .bottom)
                }
            }
        }
    }

    private func bubble(_ message: Message) -> some View {
        let fromUser = message.role == .user
        return HStack(alignment: .top, spacing: 8) {
            if fromUser { Spacer(minLength: 36) }
            if !fromUser { mark(size: 29) }
            if message.text.isEmpty {
                ProgressView().padding(10).accessibilityLabel("Caleb готовит ответ")
            } else {
                Text(message.text)
                    .textSelection(.enabled)
                    .font(.body)
                    .foregroundStyle(fromUser ? Color.black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(fromUser ? accent : surface, in: RoundedRectangle(cornerRadius: 19))
                    .accessibilityLabel("\(fromUser ? "Ты" : "Caleb"): \(message.text)")
            }
            if !fromUser { Spacer(minLength: 24) }
        }
    }

    private var composer: some View {
        let canSend = !state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 9) {
            TextField("Сообщение Caleb", text: $state.input, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Button(action: state.answering ? state.stop : state.send) {
                Image(systemName: state.answering ? "stop.fill" : "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color.black)
                    .background(accent, in: Circle())
            }
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(state.answering ? "Остановить ответ" : "Отправить")
            .disabled(!state.answering && !canSend)
            .opacity(!state.answering && !canSend ? 0.48 : 1)
        }
        .padding(6)
        .background(surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.09)))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func mark(size: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.49, weight: .semibold))
            .foregroundStyle(Color.black)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [accent, Color(red: 0.55, green: 0.52, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.31)
            )
            .accessibilityHidden(true)
    }
}
