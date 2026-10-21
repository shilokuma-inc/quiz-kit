import SwiftUI

/// アプリの見た目のうち、色・書体・形をまとめたもの
///
/// 標準画面（`QuizPlayView` など）と部品（`QuizChoiceButton` など）はすべてここから色と書体を読む。
/// アプリは `.quizTheme(_:)` で差し替える。レイアウトまで変えたいときは、画面の部品を ViewBuilder で差し替えるか、
/// `QuizSession` を直接観察する独自の画面を作る（README の「見た目の差し替え」）。
public struct QuizTheme: Sendable {
    /// 画面の背景
    public var background: Color
    /// 問題や選択肢を載せる面
    public var surface: Color
    /// 主な文字の色
    public var primaryText: Color
    /// 補足の文字の色
    public var secondaryText: Color
    /// 強調色（選択中・進捗など）
    public var accent: Color
    /// 正解の色
    public var correct: Color
    /// 不正解の色
    public var incorrect: Color
    /// 見出しの書体
    public var titleFont: Font
    /// 問題文の書体
    public var questionFont: Font
    /// 選択肢の書体
    public var choiceFont: Font
    /// 数字（スコア・残り時間）の書体
    public var numberFont: Font
    /// 本文の書体
    public var bodyFont: Font
    /// ボタンやカードの角丸
    public var cornerRadius: CGFloat
    /// 部品の間隔
    public var spacing: CGFloat

    public init(
        background: Color = Color(white: 0.96),
        surface: Color = .white,
        primaryText: Color = .primary,
        secondaryText: Color = .secondary,
        accent: Color = .blue,
        correct: Color = .green,
        incorrect: Color = .red,
        titleFont: Font = .system(.largeTitle, design: .rounded, weight: .heavy),
        questionFont: Font = .system(.title, design: .rounded, weight: .bold),
        choiceFont: Font = .system(.title3, design: .rounded, weight: .bold),
        numberFont: Font = .system(.title2, design: .rounded, weight: .heavy).monospacedDigit(),
        bodyFont: Font = .system(.body, design: .rounded),
        cornerRadius: CGFloat = 16,
        spacing: CGFloat = 16
    ) {
        self.background = background
        self.surface = surface
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.accent = accent
        self.correct = correct
        self.incorrect = incorrect
        self.titleFont = titleFont
        self.questionFont = questionFont
        self.choiceFont = choiceFont
        self.numberFont = numberFont
        self.bodyFont = bodyFont
        self.cornerRadius = cornerRadius
        self.spacing = spacing
    }

    /// 標準のテーマ
    public static let standard = QuizTheme()

    /// 子ども向けの例。大きな文字・丸い形・はっきりした色
    public static let playful = QuizTheme(
        background: Color(red: 1.0, green: 0.97, blue: 0.88),
        accent: Color(red: 1.0, green: 0.55, blue: 0.1),
        correct: Color(red: 0.2, green: 0.75, blue: 0.35),
        incorrect: Color(red: 0.95, green: 0.3, blue: 0.3),
        questionFont: .system(size: 34, weight: .heavy, design: .rounded),
        choiceFont: .system(size: 26, weight: .heavy, design: .rounded),
        cornerRadius: 28,
        spacing: 20
    )
}

extension EnvironmentValues {
    /// 画面と部品が使うテーマ
    @Entry public var quizTheme: QuizTheme = .standard
}

extension View {
    /// 配下の画面と部品のテーマを差し替える
    public func quizTheme(_ theme: QuizTheme) -> some View {
        environment(\.quizTheme, theme)
    }
}
