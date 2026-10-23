import SwiftUI
import GoogleSignIn

@MainActor @Observable final class GoogleAccount {
    var email: String?
    var error: String?
    static let driveScope = "https://www.googleapis.com/auth/drive.file"
    func restore() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        do { let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn(); email = user.profile?.email }
        catch { self.error = error.localizedDescription }
    }
    func connect() async {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String, !clientID.contains("YOUR_") else {
            error = "Add your iOS OAuth client ID in Config.xcconfig, then rebuild. See docs/GoogleOAuth.md."; return
        }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: email, additionalScopes: [Self.driveScope])
            email = result.user.profile?.email
        } catch { self.error = error.localizedDescription }
    }
    func disconnect() { GIDSignIn.sharedInstance.signOut(); email = nil }
    func token() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw DriveError.disconnected }
        let refreshed = try await user.refreshTokensIfNeeded()
        guard refreshed.grantedScopes?.contains(Self.driveScope) == true else { throw DriveError.disconnected }
        return refreshed.accessToken.tokenString
    }
}

enum DriveError: LocalizedError {
    case disconnected, response(Int), invalidResponse
    var errorDescription: String? {
        switch self {
        case .disconnected: "Connect Google Drive in Settings to sync."
        case .response(let code): "Google Drive returned HTTP \(code). Your local notebook is safe."
        case .invalidResponse: "Google Drive returned an unexpected response."
        }
    }
}
