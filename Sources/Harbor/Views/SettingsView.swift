import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage(SettingsKey.preferEnglishAudio) private var preferEnglishAudio = true
    @AppStorage(SettingsKey.subtitleLanguage) private var subtitleLanguage = "eng,en"
    @AppStorage(SettingsKey.torrentServer) private var torrentServer = ""
    @State private var confirmLogout = false

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Signed in as", value: app.email ?? "—")
                Button {
                    Task { await app.sync() }
                } label: {
                    HStack {
                        Text("Sync now")
                        Spacer()
                        if app.isSyncing {
                            ProgressView()
                        } else if let last = app.lastSync {
                            Text(last, style: .relative)
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }
                }
                Button("Sign out", role: .destructive) { confirmLogout = true }
            }

            Section {
                Toggle("Prefer English audio", isOn: $preferEnglishAudio)
                Picker("Subtitles", selection: $subtitleLanguage) {
                    Text("English").tag("eng,en")
                    Text("Arabic").tag("ara,ar")
                    Text("Arabic, then English").tag("ara,ar,eng,en")
                    Text("None by default").tag("none")
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("When a release has several audio tracks (e.g. English dub + Japanese), the player picks English first. You can switch tracks any time from the player.")
            }

            Section {
                TextField("http://192.168.1.10:11470", text: $torrentServer)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Torrent streaming server (optional)")
            } footer: {
                Text("Debrid / direct links (TorBox, Real-Debrid, AIOStreams…) play right away. Plain torrent streams need a Stremio streaming server, e.g. the one on your PC, reachable on the same Wi-Fi. Leave empty to hide them.")
            }

            Section("Addons (\(app.addons.count))") {
                ForEach(app.addons) { addon in
                    HStack(spacing: 12) {
                        RemoteImage(url: addon.manifest.logo, contentMode: .fit)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(addon.manifest.name).font(.subheadline.weight(.semibold))
                            Text(addonSummary(addon))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Text("Addons are managed from your Stremio account. Install or remove them in Harbor on your PC, then tap Sync now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: "1.0.0")
            } footer: {
                Text("Harbor for iPhone — an unofficial client for the Stremio addon ecosystem. Not affiliated with Stremio or the Harbor desktop project.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of Harbor?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { app.logout() }
        }
    }

    private func addonSummary(_ addon: Addon) -> String {
        let resources = Set(addon.manifest.resources.map(\.name)).sorted().joined(separator: ", ")
        return [addon.manifest.version.map { "v\($0)" }, resources.isEmpty ? nil : resources]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
