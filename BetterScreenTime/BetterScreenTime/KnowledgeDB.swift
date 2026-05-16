import Foundation
import SQLite3

enum DBError: Error, LocalizedError {
    case cannotCopy(String)
    case cannotOpen
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotCopy(let m):  return "Cannot copy DB: \(m)"
        case .cannotOpen:         return "Cannot open database."
        case .queryFailed(let m): return "Query failed: \(m)"
        }
    }
}

actor KnowledgeDB {
    private static let appleEpoch: Double = 978307200
    private static let dbURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")

    func fetchEvents(for date: Date) async throws -> [AppEvent] {
        // Copy DB + WAL companion files so SQLite can reconcile WAL state
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmp = tmpDir.appendingPathComponent("knowledgeC.db")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        do {
            try FileManager.default.copyItem(at: Self.dbURL, to: tmp)
            for suffix in ["-wal", "-shm"] {
                let src = URL(fileURLWithPath: Self.dbURL.path + suffix)
                if FileManager.default.fileExists(atPath: src.path) {
                    try? FileManager.default.copyItem(at: src,
                         to: URL(fileURLWithPath: tmp.path + suffix))
                }
            }
        } catch {
            throw DBError.cannotCopy(error.localizedDescription)
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw DBError.cannotOpen
        }
        defer { sqlite3_close(db) }

        let stream = detectStream(db: db)
        let dayStart = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        let dayEnd = dayStart + 86400
        let epoch = Self.appleEpoch

        let sql = """
            SELECT ZVALUESTRING,
                   ZSTARTDATE + \(epoch),
                   ZENDDATE   + \(epoch),
                   ZENDDATE - ZSTARTDATE
            FROM ZOBJECT
            WHERE ZSTREAMNAME = '\(stream)'
              AND ZENDDATE IS NOT NULL
              AND ZENDDATE > ZSTARTDATE
              AND (ZSTARTDATE + \(epoch)) < \(dayEnd)
              AND (ZENDDATE   + \(epoch)) > \(dayStart)
            ORDER BY ZSTARTDATE ASC
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var raw: [AppEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bundleId = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "Unknown"
            let startUnix = sqlite3_column_double(stmt, 1)
            let endUnix   = sqlite3_column_double(stmt, 2)
            let duration  = sqlite3_column_double(stmt, 3)
            guard duration >= 5 else { continue }
            let s = max(startUnix, dayStart)
            let e = min(endUnix, dayEnd)
            guard e > s else { continue }
            raw.append(AppEvent(
                app:      BundleNames.resolve(bundleId),
                bundleId: bundleId,
                start:    Date(timeIntervalSince1970: s),
                end:      Date(timeIntervalSince1970: e)
            ))
        }

        return ScreenTimeCore.filterQualifiedBundles(
            ScreenTimeCore.mergeAdjacentEvents(raw)
        )
    }

    private func detectStream(db: OpaquePointer?) -> String {
        let sql = "SELECT DISTINCT ZSTREAMNAME FROM ZOBJECT WHERE ZSTREAMNAME LIKE '/app/%'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "/app/inFocus" }
        defer { sqlite3_finalize(stmt) }
        var streams: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let s = sqlite3_column_text(stmt, 0) { streams.insert(String(cString: s)) }
        }
        return streams.contains("/app/inFocus") ? "/app/inFocus" : "/app/usage"
    }

    
}
