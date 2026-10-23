# Google Cloud OAuth setup

1. Create a Google Cloud project and enable **Google Drive API**.
2. Configure Google Auth Platform branding, audience and support email. For an external app in testing, add the Google accounts used on your iPads as test users.
3. Configure access for `https://www.googleapis.com/auth/drive.file`. This recommended, per-file scope permits the Paperly folder and notebooks created by the app; it does not request access to every Drive file. Sign-In additionally requests the standard identity scopes.
4. Create an **iOS OAuth client** with the bundle ID you will sign (`app.paperly.ipad` by default). Enter your Apple Team ID if requested. A web/server client and client secret are not needed.
5. Create `Config.local.xcconfig` at the repository root. Set `GOOGLE_CLIENT_ID` to the iOS client ID and `GOOGLE_REVERSED_CLIENT_ID` to its reversed URL scheme, e.g. `com.googleusercontent.apps.123456-abcdef`. The local file is ignored by Git and overrides the safe placeholders in `Config.xcconfig`; never commit it. These public client identifiers are expanded into Info.plist by Xcode.
6. If you change the app bundle ID for signing, update the Google iOS client to match. Build and run on your iPad, open Settings, and select **Sign in with Google**.
7. Confirm that a visible **Paperly** folder appears in Drive. Close a notebook to make it eligible for sync; writing remains local during an editing session.

Tokens are managed by Google Sign-In and its Keychain integration. Paperly stores no OAuth secrets or tokens in its SQLite database. Disconnect signs out on this iPad; it retains local notebooks and remote backups. Google's SDK also exposes full authorization revocation if you later add an account-deletion flow.

## Transfer and conflict behavior

Each synced generation is a new immutable `.paperly` file with `notebookID`, `generation`, and `parent` app properties. Remote file IDs and Drive versions are stored in SQLite. This intentionally retains history and avoids a check-then-overwrite race: no sync operation PATCHes an existing notebook. Two children of the same generation produce two heads and a visible conflict. Download a conflicting head as a separate notebook from Settings; original branches remain in Drive. Choose **Keep local notebook as current** to publish a new checkpoint acknowledging every current head through `ancestor_<generation>` properties. This ends the conflict while retaining all prior files. Download remote versions first if you want to compare them. There is no automatic stroke merge or destructive conflict resolution.

Uploads use resumable sessions with 1 MiB chunks (multiples of Drive's 256 KiB requirement), session persistence, status queries and exponential retry with jitter (capped at 5 minutes). Unfinished sessions resume on the next foreground sync/relaunch. An expired session is discarded and a new transfer starts on retry. The library ignores open notebooks during sync. Network failures never remove local data. Sync runs while the app is foregrounded; iPadOS suspension pauses it. There is no promise of continuous background transfers.

Snapshot history consumes Drive quota. The current app does not prune backups or delete remote notebooks. If you manually delete ancestors or move files to Trash, the service conservatively treats divergent or missing history as a conflict. Under `drive.file`, arbitrary existing Drive documents are not browsable: import them through the Files picker first.

Official references:
- [Google Sign-In iOS integration](https://developers.google.com/identity/sign-in/ios/sign-in)
- [Access Google APIs and refresh tokens](https://developers.google.com/identity/sign-in/ios/api-access)
- [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Resumable uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads)


## Universal clients and workspace folders

The iPhone and iPad client is one universal app and keeps the existing `app.paperly.ipad` bundle identifier, so the configured iOS OAuth client can be used by both device classes. Connect the same Google account in Paperly on each device; sharing an Apple ID alone does not sync Paperly. Both devices need the updated app for v3 text documents and empty-folder catalog sync. A future Mac client will need its own appropriate platform/OAuth configuration in the same Google Cloud project.

Workspace folder names (including empty folders) are represented by app-created Drive folders tagged `paperlyWorkspaceFolder=1`, under the visible Paperly folder. Clients merge names additively; duplicate concurrent creations are displayed once. Document membership remains in each `.paperly` manifest. Folder color and recoverable deletion use timestamp/revision app properties; older values cannot replace newer tombstones. Documents move to Paperly’s Trash via manifest v5 snapshots, while Drive files remain available for restore. Folder renaming is not exposed. Update all participating clients before using deletion sync. The scope remains `drive.file`.
