// TrackingSettingsView.swift
// AniList account and auto-update preference.

import SwiftUI

struct TrackingSettingsView: View {
    @Environment(TrackingManager.self) private var tracking
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        @Bindable var tracking = tracking
        List {
            Section("AniList") {
                if tracking.isLoggedIn {
                    LabeledContent("Signed in as", value: tracking.userName ?? "AniList user")
                    Button("Log out", role: .destructive) { tracking.logout() }
                } else {
                    Button {
                        Task {
                            isBusy = true
                            defer { isBusy = false }
                            do { try await tracking.login() }
                            catch AniListError.cancelled {} catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        HStack { Text("Log in to AniList"); Spacer(); if isBusy { ProgressView() } }
                    }
                    .disabled(isBusy)
                }
            }
            Section {
                Toggle("Update progress automatically", isOn: $tracking.autoUpdate)
            } footer: {
                Text("When you finish a chapter of a tracked title, AniList is updated with your highest chapter read. Updates made offline are sent when you are back online.")
            }
        }
        .navigationTitle("Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't log in", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}
