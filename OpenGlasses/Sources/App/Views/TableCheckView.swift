import PDFKit
import SwiftUI
import UIKit

/// The tables of one manual that were read from a picture, each saying where it stands (Plan JN
/// P3): under the manual's row in Custom Vaults. Tapping one opens its check view.
struct PicturedTablesList: View {
    let vaultId: String
    let documentId: String
    let documentHash: String
    /// The PDF the tables were read from, for the picture in the check view.
    let pdfURL: URL?
    let documentStore: DocumentStore
    /// Whoever may manage the vault on this phone may check its tables.
    let canCheck: Bool
    /// A photographed manual's tables (Plan JN P4): their checks are the phone's own, kept in its
    /// store rather than in a vault's file.
    var photographed = false

    @State private var tables: [ManualTable] = []
    @State private var checks: [TableCheck] = []
    @State private var opened: OpenedTable?

    private struct OpenedTable: Identifiable {
        let table: ManualTable
        let index: Int
        var id: Int { index }
    }

    var body: some View {
        // By position, not caption: one manual can print the same caption twice ("Table 2" in two
        // chapters, or a continuation that was not joined), and rows sharing an id can crash the list.
        ForEach(Array(tables.enumerated()), id: \.offset) { index, table in
            Button {
                opened = OpenedTable(table: table, index: index)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tablecells")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: table.label)
                        .font(.caption2)
                    Spacer()
                    TableCheckStatusLabel(status: model(for: table).status)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityHint(Text("Opens the table beside its picture, to check it against the page."))
        }
        .onAppear(perform: load)
        .sheet(item: $opened, onDismiss: load) { opened in
            TableCheckView(vaultId: vaultId, pdfURL: pdfURL, canCheck: canCheck, photographed: photographed,
                           model: model(for: opened.table))
        }
    }

    private func model(for table: ManualTable) -> TableCheckModel {
        TableCheckModel(table: table, documentHash: documentHash, checks: checks)
    }

    private func load() {
        tables = documentStore.tables(documentId: documentId).filter { $0.source.isRecognised && $0.isExtracted }
        checks = tables.isEmpty ? [] : VaultTableChecks.checks(vaultId: vaultId, photographed: photographed)
    }
}

/// "Read from a picture: not checked" / "checked" / "checks disagree".
struct TableCheckStatusLabel: View {
    let status: TableChecks.Status?

    var body: some View {
        switch status {
        case .checked?:
            OGStatusLabel("Read from a picture: checked", kind: .ok)
        case .disagree?:
            OGStatusLabel("Read from a picture: checks disagree", kind: .error)
        case .notChecked?, nil:
            OGStatusLabel("Read from a picture: not checked", kind: .warn)
        }
    }
}

/// One table read from a picture, beside the picture it was read from (Plan JN P3): the region of
/// the page above, the grid below with every unclear and disagreeing cell marked. Tap a cell to
/// confirm it or type what the page prints; "Mark table checked" confirms every cell read clearly.
struct TableCheckView: View {
    let vaultId: String
    let pdfURL: URL?
    let canCheck: Bool
    /// A photographed manual's table (Plan JN P4): checks kept in the phone's own store.
    var photographed = false
    @State var model: TableCheckModel

    @Environment(\.dismiss) private var dismiss
    @State private var pictures: [UIImage] = []
    @State private var editing: Editing?
    @State private var draft = ""
    @State private var share: ShareItem?
    @State private var problem: String?

    /// What a tap opened: a cell, a row's name or a column's heading.
    private enum Editing: Identifiable, Equatable {
        case cell(row: Int, column: Int)
        case rowKey(Int)
        case heading(Int)

        var id: String {
            switch self {
            case .cell(let row, let column): return "c\(row)-\(column)"
            case .rowKey(let row): return "r\(row)"
            case .heading(let column): return "h\(column)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: model.table.displayName).font(.headline)
                        TableCheckStatusLabel(status: model.status)
                        Text("These values were read from a picture of the page on this phone. Check each against the page: tap a cell to confirm it or type what the page prints.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    pictureSection
                    grid

                    if model.needsLooking > 0 {
                        Text("Cells marked with a triangle could not be read clearly, or were checked to different values. Each needs a look of its own.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !model.unmatched.isEmpty {
                        Text("Some checks of this table match no row or column in it now. They are kept and not applied.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if canCheck {
                        Button("Mark table checked") { markChecked() }
                            .buttonStyle(.ogProminent)
                            .disabled(model.confirmRemaining(by: "", at: Date()).isEmpty)
                    } else {
                        Text("Checking a table is for whoever manages this vault on the phone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if TableCheckModel.offersSharing(photographed: photographed) {
                        Button("Share checks") { shareChecks() }
                            .buttonStyle(.ogQuiet)
                            .disabled(model.checks.isEmpty)
                        Text("Shares this table's manual's checks as table-checks.json. Put the file in the vault's folder on another phone and import the folder again, and its tables are checked there too.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(Text(verbatim: model.table.label))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { renderPictures() }
            .sheet(item: $editing) { editing in
                editor(editing)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $share) { item in
                ShareSheet(items: item.items)
            }
            .alert("Can't save that check",
                   isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) { problem = nil }
            } message: {
                Text(verbatim: problem ?? "")
            }
        }
    }

    // MARK: - The picture

    @ViewBuilder
    private var pictureSection: some View {
        if pictures.isEmpty {
            Text("The picture of this table can't be shown: its manual is not on this phone as a PDF.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(pictures.indices, id: \.self) { index in
                Image(uiImage: pictures[index])
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
                    .accessibilityLabel(Text("The picture of the table on the page"))
            }
        }
    }

    /// Each region the table was read from, drawn from the page itself and nothing around it.
    private func renderPictures() {
        guard pictures.isEmpty, let pdfURL, let document = PDFDocument(url: pdfURL) else { return }
        pictures = model.table.pictureAreas.compactMap { area in
            guard area.physical >= 1, let page = document.page(at: area.physical - 1) else { return nil }
            let render = PictureRegion.Render(region: area.rect, scale: 2)
            return PictureTableReading.image(of: page, render: render).map { UIImage(cgImage: $0) }
        }
    }

    // MARK: - The grid

    private var grid: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text(verbatim: model.table.rowHeaders.joined(separator: " / "))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(model.table.columns.indices, id: \.self) { column in
                        Button { open(.heading(column)) } label: {
                            marked(model.table.columns[column].name, uncertain: model.headingIsUncertain(column))
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCheck || !model.headingIsUncertain(column))
                    }
                }
                Divider()
                ForEach(model.table.rows.indices, id: \.self) { row in
                    GridRow {
                        Button { open(.rowKey(row)) } label: {
                            marked(TableLookup.rowName(model.table.rows[row]), uncertain: model.rowKeyIsUncertain(row))
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCheck || !model.rowKeyIsUncertain(row))
                        ForEach(model.table.columns.indices, id: \.self) { column in
                            Button { open(.cell(row: row, column: column)) } label: {
                                cellLabel(row: row, column: column)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canCheck)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func marked(_ text: String, uncertain: Bool) -> some View {
        HStack(spacing: 2) {
            if uncertain {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(OGTheme.warnLabel)
            }
            Text(verbatim: text)
        }
    }

    @ViewBuilder
    private func cellLabel(row: Int, column: Int) -> some View {
        let text = model.cell(row: row, column: column)?.text ?? ""
        let shown = text.isEmpty ? "–" : text
        switch model.state(row: row, column: column) {
        case .read:
            Text(verbatim: shown).font(.caption)
        case .uncertain:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(OGTheme.warnLabel)
                Text(verbatim: shown)
            }
            .font(.caption)
            .accessibilityLabel(Text("\(shown), not read clearly"))
        case .checked:
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(OGTheme.okLabel)
                Text(verbatim: shown)
            }
            .font(.caption)
            .accessibilityLabel(Text("\(shown), checked"))
        case .disagree:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(OGTheme.errorLabel)
                Text(verbatim: shown)
            }
            .font(.caption)
            .accessibilityLabel(Text("\(shown), checks disagree"))
        }
    }

    private func open(_ target: Editing) {
        guard canCheck else { return }
        if case .cell(let row, let column) = target {
            draft = model.cell(row: row, column: column)?.text ?? ""
        }
        editing = target
    }

    // MARK: - Checking one

    @ViewBuilder
    private func editor(_ target: Editing) -> some View {
        NavigationStack {
            Form {
                switch target {
                case .cell(let row, let column):
                    Section {
                        LabeledContent("Row") { Text(verbatim: TableLookup.rowName(model.table.rows[row])) }
                        LabeledContent("Column") { Text(verbatim: model.table.columns[column].name) }
                        LabeledContent("Read from the picture") {
                            Text(verbatim: (model.readText(row: row, column: column) ?? "").isEmpty
                                 ? "–" : model.readText(row: row, column: column) ?? "")
                        }
                    }
                    if case .disagree(let marks) = model.state(row: row, column: column) {
                        Section {
                            ForEach(marks.indices, id: \.self) { index in
                                markLine(marks[index])
                            }
                        } header: {
                            Text("Checks disagree")
                        } footer: {
                            Text("No value is given from this cell until it is checked again. Type what the page prints.")
                        }
                    } else if case .checked(let mark) = model.state(row: row, column: column) {
                        Section { markLine(mark) }
                    }
                    Section {
                        TextField("What the page prints", text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") { saveCell(row: row, column: column) }
                            .buttonStyle(.ogProminent)
                    } footer: {
                        Text("Type the value exactly as the page prints it, footnote mark included. Leave it empty if the page prints nothing there.")
                    }
                case .rowKey(let row):
                    Section {
                        Text(verbatim: TableLookup.rowName(model.table.rows[row]))
                        Button("Confirm this row's name") {
                            save(model.confirmRowKey(row, by: checker, at: Date()).map { [$0] } ?? [])
                        }
                        .buttonStyle(.ogProminent)
                    } footer: {
                        Text("Confirm only if the page prints this name exactly. A row whose name was misread can't be corrected here: its values are not given, and the page is shown instead.")
                    }
                case .heading(let column):
                    Section {
                        Text(verbatim: model.table.columns[column].name)
                        Button("Confirm this heading") {
                            save(model.confirmHeading(column, by: checker, at: Date()).map { [$0] } ?? [])
                        }
                        .buttonStyle(.ogProminent)
                    } footer: {
                        Text("Confirm only if the page prints this heading exactly. A misread heading can't be corrected here: its column's values are not given, and the page is shown instead.")
                    }
                }
            }
            .ogFormStyle()
            .navigationTitle(Text("Check against the page"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editing = nil }
                }
            }
        }
    }

    private func markLine(_ mark: TableCheckMark) -> some View {
        let value = mark.value.isEmpty ? "–" : mark.value
        let day = TableChecks.day(mark.at)
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).font(.body.monospacedDigit())
            Text("Checked by \(mark.by) on \(day)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Saving

    /// Who a check is filed under: the name this phone gives whoever uses it.
    private var checker: String {
        TechnicianName.author(configured: Config.technicianDisplayName, deviceName: UIDevice.current.name)
    }

    private func saveCell(row: Int, column: Int) {
        guard let check = model.check(row: row, column: column, value: draft, by: checker, at: Date()) else { return }
        save([check])
    }

    private func markChecked() {
        save(model.confirmRemaining(by: checker, at: Date()))
    }

    private func save(_ made: [TableCheck]) {
        guard canCheck, !made.isEmpty else { return }
        do {
            try VaultTableChecks.record(made, vaultId: vaultId, photographed: photographed)
            model = model.with(checks: VaultTableChecks.checks(vaultId: vaultId, photographed: photographed))
            PrivacyLog.store(.ragDocuments, .saved, count: made.count, detail: PrivacyToken("table_checks"))
            editing = nil
        } catch {
            PrivacyLog.store(.ragDocuments, .saveFailed, count: made.count, detail: PrivacyToken("table_checks"))
            problem = error.localizedDescription
        }
    }

    /// Every check of this table's manual, not this table's alone: the file a second phone imports.
    private func shareChecks() {
        do {
            if let url = try VaultTableChecks.shareFile(VaultTableChecks.checks(vaultId: vaultId, photographed: photographed),
                                                        documentHash: model.documentHash) {
                share = ShareItem(items: [url])
            }
        } catch {
            problem = error.localizedDescription
        }
    }
}
