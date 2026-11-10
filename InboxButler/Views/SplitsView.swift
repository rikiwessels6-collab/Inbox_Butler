import SwiftUI
import InboxButlerCore

/// Make and edit your own inbox views ("splits"), like Patto or Calendar. A split shows mail that
/// carries chosen labels from your account, or comes from chosen senders. It only changes what Inbox
/// Butler shows; your real mailbox is never touched.
struct SplitsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: InboxSplit?

    private var usedLabels: Set<String> {
        Set(model.splits.flatMap { $0.labelNames.map { $0.lowercased() } })
    }
    private var suggestions: [LabelCount] {
        model.availableLabels.filter { !usedLabels.contains($0.name.lowercased()) }.prefix(8).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.splits.isEmpty {
                        Text("No splits yet. A split is your own view of the inbox, such as one label or one group of senders.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    ForEach(model.splits) { split in
                        Button { editing = split } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(split.name).foregroundStyle(Theme.ink)
                                    Text(summary(split)).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { model.deleteSplit(model.splits[i].id) }
                    }
                    Button { editing = InboxSplit(name: "") } label: { Label("New split", systemImage: "plus") }
                        .accessibilityIdentifier("new-split")
                } header: { Text("Your splits") }

                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions, id: \.name) { item in
                            Button {
                                model.saveSplit(InboxSplit(name: item.name, labelNames: [item.name]))
                            } label: {
                                HStack {
                                    Text(item.name).foregroundStyle(Theme.ink).lineLimit(1)
                                    Spacer()
                                    Text("\(item.count)").font(.footnote).foregroundStyle(Theme.muted)
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    } header: { Text("From your labels") } footer: {
                        Text("Tap a label to make it a split.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Splits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { split in SplitEditor(split: split) }
        }
        .presentationDetents([.large])
    }

    private func summary(_ split: InboxSplit) -> String {
        let parts = split.labelNames + split.senderPatterns
        return parts.isEmpty ? "Nothing chosen yet" : parts.joined(separator: ", ")
    }
}

private struct SplitEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var split: InboxSplit
    @State private var sendersText = ""

    private var isNew: Bool { !model.splits.contains { $0.id == split.id } }
    /// Labels you could pick: ones seen on your mail plus any already in this split.
    private var choices: [String] {
        var names = model.availableLabels.map(\.name)
        for n in split.labelNames where !names.contains(n) { names.append(n) }
        return names
    }
    private var senderList: [String] {
        sendersText.split(whereSeparator: { ", \n".contains($0) }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var canSave: Bool {
        !split.name.trimmingCharacters(in: .whitespaces).isEmpty && (!split.labelNames.isEmpty || !senderList.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("e.g. Patto", text: $split.name) }
                Section {
                    if choices.isEmpty {
                        Text("Your labels appear here after your mail has synced.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    ForEach(choices, id: \.self) { name in
                        Button {
                            if let i = split.labelNames.firstIndex(of: name) { split.labelNames.remove(at: i) }
                            else { split.labelNames.append(name) }
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(Theme.ink)
                                Spacer()
                                if split.labelNames.contains(name) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                } header: { Text("Your labels") } footer: { Text("Mail with any chosen label shows in this split.") }
                Section {
                    TextField("a@b.com, @company.com", text: $sendersText, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Senders") } footer: { Text("Full addresses, or @domain for everyone at a company. Separate with commas.") }
                if !isNew {
                    Section {
                        Button("Delete split", role: .destructive) { model.deleteSplit(split.id); dismiss() }
                    }
                }
            }
            .navigationTitle(isNew ? "New split" : "Edit split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        split.name = split.name.trimmingCharacters(in: .whitespaces)
                        split.senderPatterns = senderList
                        model.saveSplit(split)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { sendersText = split.senderPatterns.joined(separator: ", ") }
        }
    }
}
