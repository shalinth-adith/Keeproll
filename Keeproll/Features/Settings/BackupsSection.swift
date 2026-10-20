import SwiftUI

/// The contacts and calendar backups, with Share and Delete (QA M2). Lets the user undo
/// a change long after the Summary screen has closed.
struct BackupsSection: View {
    @State private var files: [BackupFile] = []
    @State private var pendingDelete: BackupFile?

    var body: some View {
        VStack(spacing: 0) {
            if files.isEmpty {
                HStack {
                    Text("No backups yet").font(Font.keeproll.body).foregroundStyle(Color.keeproll.inkSecondary)
                    Spacer()
                }
                .padding(.vertical, Spacing.s)
            } else {
                ForEach(files) { file in
                    row(file)
                    if file != files.last { Divider().overlay(Color.keeproll.hairline).padding(.leading, 36 + Spacing.s) }
                }
            }
        }
        .onAppear { files = BackupStore.files() }
        .confirmationDialog("Delete this backup?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { file in
            Button("Delete backup", role: .destructive) {
                BackupStore.delete(file)
                files = BackupStore.files()
            }
        } message: { _ in
            Text("You won't be able to restore these contacts or events from it.")
        }
    }

    private func row(_ file: BackupFile) -> some View {
        HStack(spacing: Spacing.s) {
            let tint = file.kind == .contacts ? Color.keeproll.catContacts : Color.keeproll.catCalendar
            Image(systemName: file.kind == .contacts ? "person.2" : "calendar")
                .font(.headline.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.kind == .contacts ? "Contacts backup" : "Calendar backup")
                    .font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkPrimary)
                Text("\(file.date.formatted(date: .abbreviated, time: .shortened)) · \(contents(file))")
                    .font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
            }
            Spacer(minLength: Spacing.s)
            ShareLink(item: file.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(Font.keeproll.headline).foregroundStyle(Color.keeproll.accent)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .accessibilityLabel(Text("Share backup"))
            // Not red: red is for the final Review button. The confirmation is red (UX review P2-5).
            Button { pendingDelete = file } label: {
                Image(systemName: "trash")
                    .font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkSecondary)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete backup"))
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func contents(_ file: BackupFile) -> Text {
        switch (file.kind, file.itemCount) {
        case (.contacts, 0): Text("No contacts")
        case (.calendar, 0): Text("No events")
        case (.contacts, let count): Text("^[\(count) contact](inflect: true)")
        case (.calendar, let count): Text("^[\(count) event](inflect: true)")
        }
    }
}
