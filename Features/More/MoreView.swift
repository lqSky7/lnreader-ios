// MoreView.swift
// Settings hub with quick stats and navigation using a monochrome Bento Grid and systemGray6 cards.

import PhotosUI
import SwiftData
import SwiftUI

struct MoreView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Novel> { $0.inLibrary }) private var libraryNovels: [Novel]
    @Query private var chapters: [Chapter]
    @Query private var profiles: [UserProfile]

    @State private var showingEditProfile = false

    // Haptic feedback generators
    private let lightFeedback = UIImpactFeedbackGenerator(style: .light)
    private let mediumFeedback = UIImpactFeedbackGenerator(style: .medium)

    private var userProfile: UserProfile {
        profiles.first ?? UserProfile(name: "Reader")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile/Journey Card (Name and PFP on bottom-left, no stats, edit button top-right)
                    profileHeaderCard
                    
                    // Bento grid layout for settings (systemGray6 background, monochrome icons)
                    bentoSettingsGrid
                }
                .padding(.vertical)
            }
            .navigationTitle("More")
            .sheet(isPresented: $showingEditProfile) {
                ProfileEditSheet(profile: userProfile)
            }
            .onAppear {
                ensureProfileExists()
                lightFeedback.prepare()
                mediumFeedback.prepare()
            }
        }
    }

    private func ensureProfileExists() {
        if profiles.isEmpty {
            let defaultProfile = UserProfile(name: "Reader")
            modelContext.insert(defaultProfile)
            try? modelContext.save()
        }
    }

    // MARK: - Profile Header Card

    private var profileHeaderCard: some View {
        ZStack {
            // Profile image or default backdrop
            GeometryReader { geometry in
                if let data = userProfile.avatarData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: 180)
                        .clipped()
                } else {
                    ZStack {
                        Color(UIColor.systemGray5)
                        Image(systemName: "person.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.gray.opacity(0.4))
                    }
                    .frame(width: geometry.size.width, height: 180)
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            
            // Dark overlay for legibility
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.4))
            
            // Username on bottom-left (No stats or data details)
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(userProfile.name)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
            }
            .padding(20)
            
            // Pencil edit button in top-right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        lightFeedback.impactOccurred()
                        showingEditProfile = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(12)
                    }
                }
                Spacer()
            }
        }
        .frame(height: 180)
        .padding(.horizontal)
    }

    // MARK: - Bento Settings Grid

    private var bentoSettingsGrid: some View {
        VStack(spacing: 0) {
            // Row 1: General | Appearance
            HStack(spacing: 0) {
                NavigationLink {
                    GeneralSettingsView()
                } label: {
                    BentoCell(alignment: .bottomLeading) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("General")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("Library & defaults")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(BentoCellButtonStyle())
                .simultaneousGesture(TapGesture().onEnded {
                    lightFeedback.impactOccurred()
                })
                
                Rectangle()
                    .fill(Color(UIColor.separator))
                    .frame(width: 0.5)
                
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    BentoCell(alignment: .bottomLeading) {
                        Image(systemName: "paintbrush.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Appearance")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("Theme & cover style")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(BentoCellButtonStyle())
                .simultaneousGesture(TapGesture().onEnded {
                    lightFeedback.impactOccurred()
                })
            }
            .frame(height: 140)
            
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(height: 0.5)
            
            // Row 2: Reader | Advanced
            HStack(spacing: 0) {
                NavigationLink {
                    ReaderSettingsView()
                } label: {
                    BentoCell(alignment: .bottomLeading) {
                        Image(systemName: "textformat.size")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reader")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("Typography & layout")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(BentoCellButtonStyle())
                .simultaneousGesture(TapGesture().onEnded {
                    lightFeedback.impactOccurred()
                })
                
                Rectangle()
                    .fill(Color(UIColor.separator))
                    .frame(width: 0.5)
                
                NavigationLink {
                    AdvancedSettingsView()
                } label: {
                    BentoCell(alignment: .bottomLeading) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Advanced")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("Diagnostics & cache")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(BentoCellButtonStyle())
                .simultaneousGesture(TapGesture().onEnded {
                    lightFeedback.impactOccurred()
                })
            }
            .frame(height: 140)
            
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(height: 0.5)
            
            // Row 3: Statistics (Full width)
            NavigationLink {
                StatisticsView()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color(UIColor.systemGray5), in: .circle)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Statistics")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("Library and reading insights")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .buttonStyle(BentoCellButtonStyle())
            .simultaneousGesture(TapGesture().onEnded {
                mediumFeedback.impactOccurred()
            })
            
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(height: 0.5)
            
            // Row 4: About (Full width)
            NavigationLink {
                AboutView()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color(UIColor.systemGray5), in: .circle)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("About")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("App version and source code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .buttonStyle(BentoCellButtonStyle())
            .simultaneousGesture(TapGesture().onEnded {
                mediumFeedback.impactOccurred()
            })
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(UIColor.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
    }
}

// MARK: - Bento Cell Component
private struct BentoCell<IconContent: View, LabelContent: View>: View {
    let alignment: Alignment
    @ViewBuilder let icon: () -> IconContent
    @ViewBuilder let label: () -> LabelContent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            icon()
            Spacer()
            label()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .contentShape(Rectangle())
    }
}

// MARK: - Bento Cell Button Style
private struct BentoCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.white.opacity(0.04) : Color.clear
            )
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Profile Edit Sheet

struct ProfileEditSheet: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var nameInput: String = ""
    @State private var currentAvatarData: Data? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Avatar") {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            if let data = currentAvatarData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 100, height: 100)
                            }
                            
                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                Text("Choose Photo")
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                            .onChange(of: selectedItem) { _, newItem in
                                Task {
                                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                        currentAvatarData = data
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Name") {
                    TextField("Enter name", text: $nameInput)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.name = nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Reader" : nameInput
                        profile.avatarData = currentAvatarData
                        dismiss()
                    }
                }
            }
            .onAppear {
                nameInput = profile.name
                currentAvatarData = profile.avatarData
            }
        }
    }
}
