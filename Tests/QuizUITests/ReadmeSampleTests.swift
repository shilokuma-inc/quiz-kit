import QuizCore
import QuizUI
import SwiftUI
import Testing

// README の「30 行で 4 択クイズ」がそのままコンパイルできること

private struct Prefecture: Sendable {
    let name: String
    let capital: String
    let region: String
}

private struct PrefectureQuizView: View {
    @State private var session: QuizSession<ChoiceQuestion<String, String>>

    init(prefectures: [Prefecture]) {
        var generator = ChoiceQuestionGenerator(
            items: prefectures,
            choiceCount: 4,
            prompt: { $0.name },
            answer: { $0.capital },
            distractorGroup: { AnyHashable($0.region) }
        )
        var rng = SystemRandomNumberGenerator()
        let questions = generator.makeQuestions(count: 10, using: &rng)
        _session = State(initialValue: QuizSession(questions: questions, rules: .practice))
    }

    var body: some View {
        if session.isFinished {
            QuizResultView(session: session) { Button("もう一度") {} }
        } else {
            QuizPlayView(session: session) { question in
                Text("\(question.prompt)の県庁所在地は？")
            }
        }
    }
}

@MainActor
struct ReadmeSampleTests {
    @Test func サンプルの画面を作れる() {
        let view = PrefectureQuizView(prefectures: [
            Prefecture(name: "青森県", capital: "青森市", region: "東北"),
            Prefecture(name: "岩手県", capital: "盛岡市", region: "東北")
        ])
        _ = view.body
    }
}
