import SwiftUI

struct MarketsView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var markets: [Market] = []
    @State private var loading = false
    @State private var book: Book?
    @State private var bookTitle = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        TextField("Search markets…", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await search() } }
                        Button("Search") { Task { await search() } }
                            .buttonStyle(PanelButton())
                    }
                    if loading {
                        Text("Loading…").font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    } else if markets.isEmpty {
                        Text("Search or wait for top markets.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(markets) { m in
                                marketRow(m)
                                Divider().overlay(Theme.border.opacity(0.5))
                            }
                        }
                    }
                }
                .card()

                if let book {
                    bookCard(book)
                }
            }
            .padding(18)
        }
        .task { if markets.isEmpty { await search() } }
    }

    private func marketRow(_ m: Market) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(m.question ?? "?")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("24h vol \(fmtUSD(m.volume24hr))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            ForEach(Array((m.clobTokenIds ?? []).prefix(2).enumerated()), id: \.offset) { i, tok in
                Button("book \(i == 0 ? "①" : "②")") {
                    Task { await loadBook(tok, title: "\(m.question ?? "") [\(i)]") }
                }
                .buttonStyle(PanelButton(small: true))
            }
        }
        .padding(.vertical, 7)
    }

    private func bookCard(_ b: Book) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bookTitle)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(Theme.text)
            HStack(alignment: .top, spacing: 24) {
                side("Bids", b.bids ?? [], Theme.green)
                side("Asks", b.asks ?? [], Theme.red)
            }
        }
        .card()
    }

    private func side(_ title: String, _ levels: [BookLevel], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
            if levels.isEmpty {
                Text("empty").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            ForEach(levels) { l in
                HStack(spacing: 12) {
                    Text(l.price ?? "?")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(color)
                        .frame(width: 60, alignment: .leading)
                    Text(l.size ?? "?")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func search() async {
        loading = true
        defer { loading = false }
        if let r: MarketsPayload = try? await store.api.get(
            "/api/markets", query: ["q": query, "limit": "30"]) {
            markets = r.markets
        }
    }

    private func loadBook(_ token: String, title: String) async {
        bookTitle = title
        if let r: BookPayload = try? await store.api.get(
            "/api/book", query: ["token": token]) {
            book = r.book
        }
    }
}
