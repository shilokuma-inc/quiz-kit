import SwiftUI

/// 難易度・問題数・モードなど、いくつかの中から 1 つを選ぶ部品
///
/// 選択肢の型はアプリが決める（`enum Difficulty: CaseIterable` など）。
public struct QuizOptionPicker<Option: Hashable, Label: View>: View {
    @Environment(\.quizTheme) private var theme
    private let options: [Option]
    @Binding private var selection: Option
    private let label: (Option) -> Label

    public init(_ options: [Option], selection: Binding<Option>, @ViewBuilder label: @escaping (Option) -> Label) {
        self.options = options
        _selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: theme.spacing / 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    label(option)
                        .font(theme.choiceFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(isSelected ? Color.white : theme.primaryText)
                        .background(
                            Capsule().fill(isSelected ? theme.accent : theme.surface)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(.snappy, value: selection)
    }
}
