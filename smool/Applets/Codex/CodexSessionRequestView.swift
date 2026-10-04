import SwiftUI

struct CodexSessionRequestView: View {
    let request: CodexSessionRequest
    @Binding var answers: [String: String]
    var error: String?
    let respond: (CodexSessionDecision) -> Void
    let close: () -> Void

    private enum Focus: Hashable {
        case content, answer(String), option(String, String), allow, decline, submit, cancel
    }
    @FocusState private var focus: Focus?

    private var hasAnswers: Bool {
        !request.questions.isEmpty && request.questions.allSatisfy {
            !(answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var controls: [Focus] {
        switch request.kind {
        case .approval: return request.allowsApproval ? [.decline, .allow] : [.decline]
        case .unsupported: return [.cancel]
        case .questions:
            return request.questions.flatMap { question in
                question.options.map { .option(question.id, $0.label) } + [.answer(question.id)]
            } + [.cancel, .submit]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.title)
                .font(.system(size: 15, weight: .medium))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !request.message.isEmpty {
                        Text(request.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(request.questions) { question in
                        questionView(question)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                switch request.kind {
                case .approval:
                    Button("Decline") { respond(.decline) }
                        .focusable()
                        .focused($focus, equals: .decline)
                    Spacer()
                    if request.allowsApproval {
                        Button(request.method == "item/permissions/requestApproval" ? "Allow for this turn" : "Allow once") {
                            respond(.allowOnce)
                        }
                        .focusable()
                        .focused($focus, equals: .allow)
                    }
                case .questions:
                    Button("Cancel turn") { respond(.cancel) }
                        .focusable()
                        .focused($focus, equals: .cancel)
                    Spacer()
                    Button("Send answers", action: sendAnswers)
                        .focusable()
                        .focused($focus, equals: .submit)
                        .disabled(!hasAnswers)
                case .unsupported:
                    Button("Cancel turn") { respond(.cancel) }
                        .focusable()
                        .focused($focus, equals: .cancel)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(NotchControlStyle())
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .focusable(interactions: .edit)
        .focused($focus, equals: .content)
        .focusEffectDisabled()
        .onAppletFocusRestore { focus = .content }
        .task { await Task.yield(); focus = .content }
        .onKeyPress(.tab, phases: .down) { key in
            guard key.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
            let reverse = key.modifiers.contains(.shift)
            if let focus, let index = controls.firstIndex(of: focus) {
                self.focus = controls[(index + (reverse ? controls.count - 1 : 1)) % controls.count]
            } else {
                focus = reverse ? controls.last : controls.first
            }
            return .handled
        }
        .onKeyPress(.return, phases: .down) { key in
            guard key.modifiers.isEmpty else { return .ignored }
            switch focus {
            case .allow: respond(.allowOnce)
            case .decline: respond(.decline)
            case .cancel: respond(.cancel)
            case .submit: sendAnswers()
            case .option(let question, let option): answers[question] = option
            default: return .ignored
            }
            return .handled
        }
        .onKeyPress(.escape) { close(); return .handled }
    }

    private func questionView(_ question: CodexSessionQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.question)
                .font(.system(size: 12, weight: .medium))

            ForEach(question.options, id: \.label) { option in
                Button {
                    answers[question.id] = option.label
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: answers[question.id] == option.label ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.label)
                            if !option.description.isEmpty {
                                Text(option.description).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($focus, equals: .option(question.id, option.label))
                .accessibilityAddTraits(answers[question.id] == option.label ? .isSelected : [])
            }

            let answer = Binding<String>(
                get: {
                    let value = answers[question.id] ?? ""
                    return question.options.contains { $0.label == value } ? "" : value
                },
                set: { answers[question.id] = $0 }
            )
            Group {
                if question.isSecret {
                    SecureField("Your answer", text: answer)
                } else {
                    TextField(question.options.isEmpty ? "Your answer" : "Or write an answer…", text: answer)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.vertical, 6)
            .focused($focus, equals: .answer(question.id))
            .accessibilityLabel(question.question)
            .onSubmit {
                if let index = request.questions.firstIndex(where: { $0.id == question.id }),
                   request.questions.indices.contains(index + 1) {
                    focus = .answer(request.questions[index + 1].id)
                } else {
                    sendAnswers()
                }
            }
        }
    }

    private func sendAnswers() {
        guard hasAnswers else { return }
        respond(.answers(answers.mapValues { [$0] }))
    }
}
