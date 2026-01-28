import SwiftUI

/// A fake gallery view designed to look like a standard Photos app.
/// This is shown when the user enters the "Duress PIN" to make an aggressor believe
/// they have access to a harmless device, while the real evidence remains hidden.
struct FakeGalleryView: View {
    // Grid layout
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    // Fake data: Just colorful rectangles to look like generic photos
    private let fakeColors: [Color] = [
        .blue, .green, .pink, .orange, .purple, .yellow,
        .gray, .mint, .indigo, .teal, .brown, .cyan
    ]
    
    var body: some View {
        TabView {
            // Library Tab
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 1) {
                        // Generate a bunch of dummy "photos"
                        ForEach(0..<40, id: \.self) { index in
                            Rectangle()
                                .fill(fakeColors[index % fakeColors.count].gradient)
                                .aspectRatio(1, contentMode: .fill)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(.white.opacity(0.5))
                                )
                                .clipped()
                        }
                    }
                }
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Select") {}
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {}) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .tabItem {
                Label("Library", systemImage: "photo.fill.on.rectangle.fill")
            }
            
            // For You Tab
            NavigationStack {
                VStack {
                    Text("No Memories Yet")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .navigationTitle("For You")
            }
            .tabItem {
                Label("For You", systemImage: "heart.text.square.fill")
            }
            
            // Albums Tab
            NavigationStack {
                List {
                    Section {
                        NavigationLink(destination: Text("Recents")) {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.blue)
                                Text("Recents")
                                Spacer()
                                Text("40")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        NavigationLink(destination: Text("Favorites")) {
                            HStack {
                                Image(systemName: "heart")
                                    .foregroundStyle(.blue)
                                Text("Favorites")
                                Spacer()
                                Text("0")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Albums")
            }
            .tabItem {
                Label("Albums", systemImage: "rectangle.stack.fill")
            }
            
            // Search Tab
            NavigationStack {
                Text("Search")
                    .navigationTitle("Search")
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
        }
        .tint(.blue) // iOS Standard Blue
    }
}

#Preview {
    FakeGalleryView()
}
