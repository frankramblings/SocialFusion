import SwiftUI

struct MutedKeywordsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var keywords: [String] = []
    @State private var newKeyword: String = ""
    
    var body: some View {
        List {
            Section(header: Text("Add New Keyword")) {
                HStack {
                    TextField("Enter keyword or phrase", text: $newKeyword)
                        .onSubmit(addKeyword)
                    
                    Button(action: addKeyword) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            Section(header: Text("Muted Keywords"), footer: Text("Posts containing these keywords will be hidden from your timeline.")) {
                if keywords.isEmpty {
                    Text("No muted keywords")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(keywords, id: \.self) { keyword in
                        Text(keyword)
                    }
                    .onDelete(perform: removeKeywords)
                }
            }
        }
        .navigationTitle("Muted Keywords")
        .onAppear {
            keywords = serviceManager.currentBlockedKeywords
        }
    }
    
    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if !keywords.contains(trimmed) {
            keywords.append(trimmed)
            serviceManager.updateBlockedKeywords(keywords)
        }
        newKeyword = ""
    }
    
    private func removeKeywords(at offsets: IndexSet) {
        keywords.remove(atOffsets: offsets)
        serviceManager.updateBlockedKeywords(keywords)
    }
}

