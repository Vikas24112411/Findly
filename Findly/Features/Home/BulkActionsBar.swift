import SwiftUI

struct BulkActionsBar: View {

    let selectedCount: Int
    var onTag: () -> Void
    var onFavorite: () -> Void
    var onDelete: () -> Void
    var onCancel: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Text("\(selectedCount) selected")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, AppTheme.Spacing.base)

                HStack(spacing: AppTheme.Spacing.xLarge) {
                    Button { onTag() } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "tag")
                                .font(.system(size: 20))
                            Text("Tag")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(selectedCount > 0 ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel)
                    }
                    .disabled(selectedCount == 0)

                    Button { onFavorite() } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "heart")
                                .font(.system(size: 20))
                            Text("Favorite")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(selectedCount > 0 ? AppTheme.Colors.accent : AppTheme.Colors.tertiaryLabel)
                    }
                    .disabled(selectedCount == 0)

                    Button { showDeleteConfirm = true } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 20))
                            Text("Delete")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(selectedCount > 0 ? .red : AppTheme.Colors.tertiaryLabel)
                    }
                    .disabled(selectedCount == 0)
                }
                .padding(.trailing, AppTheme.Spacing.base)
            }
            .frame(height: 60)
            .background(AppTheme.Colors.secondaryBG)
        }
        .alert("Delete \(selectedCount) item\(selectedCount == 1 ? "" : "s")?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the selected files.")
        }
    }
}
