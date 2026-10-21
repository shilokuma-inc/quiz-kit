@testable import QuizCore
import Testing

struct Prefecture: Sendable {
    let name: String
    let capital: String
    let region: String
}

struct ChoiceQuestionGeneratorTests {
    private let prefectures = [
        Prefecture(name: "北海道", capital: "札幌市", region: "北海道"),
        Prefecture(name: "青森県", capital: "青森市", region: "東北"),
        Prefecture(name: "岩手県", capital: "盛岡市", region: "東北"),
        Prefecture(name: "宮城県", capital: "仙台市", region: "東北"),
        Prefecture(name: "茨城県", capital: "水戸市", region: "関東"),
        Prefecture(name: "栃木県", capital: "宇都宮市", region: "関東"),
        Prefecture(name: "群馬県", capital: "前橋市", region: "関東"),
        Prefecture(name: "神奈川県", capital: "横浜市", region: "関東")
    ]

    @Test("選択肢の数と正解を含むこと", arguments: [2, 3, 4]) func containsChoiceCountAndCorrect(choiceCount: Int) {
        var generator = ChoiceQuestionGenerator(items: prefectures, choiceCount: choiceCount, prompt: \.name, answer: \.capital)
        var rng = SeededRandomNumberGenerator(seed: 1)
        let questions = generator.makeQuestions(count: 20, using: &rng)
        #expect(questions.count == 20)
        for question in questions {
            #expect(question.choices.count == choiceCount)
            #expect(Set(question.choices).count == choiceCount)
            #expect(question.choices.contains(question.correctChoice))
            let prefecture = prefectures.first { $0.name == question.prompt }
            #expect(prefecture?.capital == question.correctChoice)
        }
    }

    @Test("一巡するまで同じ問題を出さない") func noRepeatUntilCycle() {
        var generator = ChoiceQuestionGenerator(items: prefectures, choiceCount: 4, prompt: \.name, answer: \.capital)
        var rng = SeededRandomNumberGenerator(seed: 2)
        let prompts = generator.makeQuestions(count: prefectures.count, using: &rng).map(\.prompt)
        #expect(Set(prompts).count == prefectures.count)
    }

    @Test("同じシードなら同じ出題") func sameSeedSameQuestions() {
        var first = ChoiceQuestionGenerator(items: prefectures, choiceCount: 4, prompt: \.name, answer: \.capital)
        var second = first
        var rng1 = SeededRandomNumberGenerator(seed: 42)
        var rng2 = SeededRandomNumberGenerator(seed: 42)
        #expect(first.makeQuestions(count: 10, using: &rng1) == second.makeQuestions(count: 10, using: &rng2))
    }

    @Test("誤答は同じグループから優先して選ぶ") func prefersSameGroupDistractors() {
        let generator = ChoiceQuestionGenerator(
            items: prefectures,
            choiceCount: 4,
            prompt: { $0.name },
            answer: { $0.name },
            distractorGroup: { AnyHashable($0.region) }
        )
        var rng = SeededRandomNumberGenerator(seed: 3)
        let kanagawa = prefectures[7]
        let question = generator.makeQuestion(for: kanagawa, using: &rng)
        let kanto = Set(prefectures.filter { $0.region == "関東" }.map(\.name))
        #expect(Set(question.choices) == kanto)
    }

    @Test("答えの種類が足りなければある分だけ並べる") func fewerChoicesWhenAnswersRunOut() {
        let items = [Prefecture(name: "A", capital: "X", region: ""), Prefecture(name: "B", capital: "X", region: "")]
        let generator = ChoiceQuestionGenerator(items: items, choiceCount: 4, prompt: \.name, answer: \.capital)
        var rng = SeededRandomNumberGenerator(seed: 4)
        #expect(generator.makeQuestion(for: items[0], using: &rng).choices == ["X"])
    }
}
