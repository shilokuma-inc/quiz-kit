import Foundation
import GameKit
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

/// Game Center のリーダーボード
///
/// サーバーを持たずに「全員と競うランキング」を出す。使うには次の準備が要る（README の「Game Center」）。
/// - Xcode の Signing & Capabilities で Game Center を有効にする
/// - App Store Connect でリーダーボードを作り、その ID を `leaderboardID` に渡す
///
/// サインインしていない・Game Center が使えない端末では何もしない。端末の中だけのランキング（`LocalLeaderboard`）と併用すると、
/// サインインしていない人にも自己ベストを見せられる。
@MainActor
public final class GameCenterLeaderboard: ObservableObject {
    /// サインイン済みか
    @Published public private(set) var isAuthenticated = false

    public init() {}

    /// サインインを始める。サインインの画面が要るときは `presentAuthentication` に渡して出す
    ///
    /// 起動直後ではなく、最初の画面が出てから呼ぶ。
    #if canImport(UIKit)
    public func authenticate(
        presentAuthentication: @escaping @MainActor (UIViewController) -> Void = GameCenterLeaderboard.presentOnKeyWindow
    ) {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            MainActor.assumeIsolated {
                if let viewController {
                    presentAuthentication(viewController)
                }
                self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            }
        }
    }
    #else
    public func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            }
        }
    }
    #endif

    /// スコアを送る。サインインしていなければ何もしない。失敗してもプレイは止めない
    public func submit(score: Int, leaderboardID: String) async {
        guard GKLocalPlayer.local.isAuthenticated, score > 0 else { return }
        try? await GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        )
    }

    /// 自分のスコアの前後のプレイヤー（全期間）。サインインしていなければ空
    public func entries(leaderboardID: String, range: NSRange = NSRange(location: 1, length: 10)) async -> [Entry] {
        guard GKLocalPlayer.local.isAuthenticated,
              let leaderboard = try? await GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]).first,
              let (_, entries, _) = try? await leaderboard.loadEntries(for: .global, timeScope: .allTime, range: range)
        else { return [] }
        return entries.map { Entry(rank: $0.rank, displayName: $0.player.displayName, score: $0.score) }
    }

    /// リーダーボードの 1 行
    public struct Entry: Sendable, Equatable {
        public let rank: Int
        public let displayName: String
        public let score: Int
    }

    #if canImport(UIKit)
    /// いちばん手前のウィンドウに画面を出す
    public static func presentOnKeyWindow(_ viewController: UIViewController) {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        top?.present(viewController, animated: true)
    }
    #endif
}

#if canImport(UIKit)
/// Game Center の標準のリーダーボード画面。`.sheet` などで出す
public struct GameCenterLeaderboardView: UIViewControllerRepresentable {
    private let leaderboardID: String
    @Environment(\.dismiss) private var dismiss

    public init(leaderboardID: String) {
        self.leaderboardID = leaderboardID
    }

    public func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let viewController = GKGameCenterViewController(
            leaderboardID: leaderboardID,
            playerScope: .global,
            timeScope: .allTime
        )
        viewController.gameCenterDelegate = context.coordinator
        return viewController
    }

    public func updateUIViewController(_ uiViewController: GKGameCenterViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator { dismiss() }
    }

    public final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        public func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
            onFinish()
        }
    }
}
#endif
