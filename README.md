# QuizKit

択一クイズアプリ（2 択・3 択・4 択…）を量産するための Swift Package です。

問題・解答・結果・ランダム出題・難易度・制限時間・スコアとコンボ・ランキング・デイリーチャレンジといった「どのクイズアプリでも同じ部分」を持ちます。
各アプリが用意するのは、次のものだけです。

- 中身のデータ（国旗・都道府県など）
- 見た目
- 使う機能の選択

## Environment

- Swift 6（Swift 6 言語モード / Strict Concurrency）
- iOS 17.0 以上（ロジックのテスト用に macOS 14.0 以上でもビルドできます）
- Xcode 26.6

## Products

| Product | 内容 | 依存 |
|---|---|---|
| `QuizCore` | 問題の型・データセットからの出題・1 プレイの進行（`QuizSession`）・スコアとコンボ・端末内ランキング・デイリーの日付とストリーク・シード付き乱数 | なし（UI なし） |
| `QuizUI` | テーマ（`QuizTheme`）と標準の画面・部品（出題・結果・ランキング・選択肢ボタン・オプション選択） | `QuizCore` |
| `QuizGameCenter` | Game Center のリーダーボード（スコアの送信・一覧・標準画面） | GameKit |

広告と Analytics は Kit に入れていません。子ども向けのアプリでは、第三者の広告や Analytics の SDK がリンクされているだけで、審査（Kids カテゴリ）と PrivacyInfo の申告に響くためです。広告を出すアプリだけが、アプリ側で SDK を足します。

## 導入

Xcode の「File → Add Package Dependencies…」で `https://github.com/shilokuma-inc/quiz-kit` を追加し、使う product を選びます。

```swift
.package(url: "https://github.com/shilokuma-inc/quiz-kit", from: "0.1.0")
```

## 30 行で 4 択クイズ

データセット（1 行が 1 件のデータ）から、問題にする列と答えにする列を選んで出題を作ります。

```swift
import QuizCore
import QuizUI
import SwiftUI

struct Prefecture: Sendable {
    let name: String
    let capital: String
    let region: String
}

struct PrefectureQuizView: View {
    @State private var session: QuizSession<ChoiceQuestion<String, String>>

    init(prefectures: [Prefecture]) {
        var generator = ChoiceQuestionGenerator(
            items: prefectures,
            choiceCount: 4,                        // 2 にすれば 2 択
            prompt: { $0.name },                   // 問題: 都道府県名
            answer: { $0.capital },                // 答え: 県庁所在地
            distractorGroup: { AnyHashable($0.region) } // 誤答を同じ地方から選んで難しくする（任意）
        )
        var rng = SystemRandomNumberGenerator()
        let questions = generator.makeQuestions(count: 10, using: &rng)
        _session = State(initialValue: QuizSession(questions: questions, rules: .practice))
    }

    var body: some View {
        if session.isFinished {
            QuizResultView(session: session) { Button("もう一度") { /* 作り直す */ } }
        } else {
            QuizPlayView(session: session) { question in
                Text("\(question.prompt)の県庁所在地は？")
            }
        }
    }
}
```

## 考え方

### 問題（`QuizQuestion`）

`QuizQuestion` に必要なのは、次の 3 つだけです。

- `choices`：選択肢
- `isCorrect(_:)`：選んだものが正解か
- `scoreFactor`：難易度係数

`QuizSession` は問題の中身を知りません。そのため、データの形が違っても同じ進行の仕組みで動きます。たとえば次のどちらにも使えます。

- 国旗の画像を見せて国名を選ぶ
- 数字を見せて素数かどうかを選ぶ

| 作り方 | 使う型 |
|---|---|
| データセットから作る（国旗・都道府県・単語など） | `ChoiceQuestion` + `ChoiceQuestionGenerator` |
| 計算やルールで作る（素数・計算問題など） | 自分の型を `QuizQuestion` に適合させる（prime-pick の `QuizEntity`） |

### 進め方（`QuizRules`）

「練習」「タイムアタック」のようなモードは、名前も数もアプリごとに違います。そのため Kit はモードを持ちません。アプリはモードから `QuizRules` を作って `QuizSession` に渡します。

| 項目 | 内容 |
|---|---|
| `timeLimitSeconds` | 制限時間。nil なら時間無制限で、全問に答えたら終わり |
| `missTimePenaltySeconds` / `missInputLockDuration` | 誤答で減らす秒数 / 誤答後に入力を止める秒数 |
| `advanceDelay` | 解答してから次の問題に進むまでの待ち時間（解説を読ませる）。待っている間は次の問題の解答時間に数えない |
| `scoringRule` / `scoring` | スコアのルール（練習 / タイムアタック）と係数 |

制限時間内に問題が尽きないよう、タイムアタックでは `QuizSession(…, refill:)` で問題を補充します。

### 1 プレイの進行（`QuizSession`）

`QuizSession` は `@Observable` のクラスで、次のものを持ちます。

- 出題と、表示中の問題
- 解答の受付（次の問題を待っている間と、誤答後のロック中は受け付けない）
- スコア・コンボ・残り時間・問題の補充・終わりの判定

画面はこのクラスを観察して描き、`answer(_:)` を呼ぶだけで動きます。

効果音・触覚・計測などの画面の外の処理は、`onEvent` でつなぎます。届く出来事は `.answered` / `.timePenalty` / `.advanced` / `.tick` / `.finished` です。

撮影モードやプレビューで「何問か解いた画面」を作るときは、`restore(answeredChoices:remainingSeconds:isFinished:)` を使います。

## 見た目の差し替え

アプリに合わせて 3 段階で選べます。

| 段階 | やり方 | 向いているもの |
|---|---|---|
| 1. テーマ | `.quizTheme(QuizTheme(…))` で色・書体・角丸・間隔を変える | 標準のレイアウトで足りるアプリ |
| 2. 部品 | `QuizPlayView` の `prompt`（問題）・`choiceLabel`（選択肢の中身）・`status`（進捗・スコア・残り時間）を ViewBuilder で差し替え、`layout` で選択肢の並べ方（縦・横・格子）を選ぶ | 問題の見せ方（画像・地図）や選択肢の並べ方だけ変えたいアプリ |
| 3. 画面ごと | `QuizUI` を使わず、`QuizSession` を観察する独自の画面を作る | レイアウトや演出を作り込むアプリ（prime-pick はこの段階） |

どの段階でも、出題・進行・スコアのロジックは `QuizSession` のものをそのまま使います。

## ランキング

| 種類 | 使う型 | 準備 |
|---|---|---|
| 端末内（自分との競争） | `LocalLeaderboard`（枠ごとに上位 10 件を日付つきで保存）＋ `LocalLeaderboardView` | なし |
| 全員と競う | `GameCenterLeaderboard`（`authenticate()` → `submit(score:leaderboardID:)`）＋ `GameCenterLeaderboardView` | Signing & Capabilities で Game Center を有効にし、App Store Connect でリーダーボードを作る |

Game Center にサインインしていない人もいるので、両方を併用するのがおすすめです。

## デイリーチャレンジ

全員が同じ日に同じ問題を解く仕組みの部品です。

| 型 | 内容 |
|---|---|
| `QuizDay` | 端末のタイムゾーンの 0 時で切り替わる「今日」。グレゴリオ暦に固定し、`dayKey`（`2026-10-01`）を出題のシードと記録のキーに使う |
| `StableSeed.fnv1a` | `dayKey` から、起動や端末に依らないシードを作る |
| `SplitMix64` | OS が変わっても同じ列を返す乱数。`shuffled(_:)`・`nextIndex(below:)` も OS に依らない |
| `DayKeyedRecordStore` | 1 日 1 件の記録の保存 |
| `QuizStreak` | 連続日数と最長記録 |

標準ライブラリの `shuffled(using:)` などは、OS の更新で引き方が変わることがあります。デイリーの出題では `SplitMix64` のメソッドだけを使ってください。

## 使っているアプリ

- [prime-pick-ios](https://github.com/shilokuma-inc/prime-pick-ios)（素数クイズ。`QuizCore` だけを使い、画面は独自）

## バージョン

[Semantic Versioning](https://semver.org/lang/ja/) に従います。1.0.0 までは minor の更新で API が変わることがあるので、アプリでは `upToNextMinorVersion` で固定してください。

## License

[MIT License](LICENSE)
