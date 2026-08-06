import XCTest
import CoreData
import UIKit
@testable import Anniversary

final class LedgerRepositoryTests: XCTestCase {
    private var pc: PersistenceController!
    private var couple: CDCouple!
    private var repo: LedgerRepository!
    private let myID = UUID()

    override func setUpWithError() throws {
        pc = PersistenceController(inMemory: true)
        couple = try CoupleRepository(context: pc.viewContext)
            .bootstrapIfNeeded(myName: "阿铖", partnerName: "小于", anniversary: nil)
        repo = LedgerRepository(context: pc.viewContext)
    }

    /// 真实可解码的最小图像（Thumbnailer 对非图像字节按契约返回 nil）
    private func makeImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.pngData()!
    }

    private func makeEntry(visibility: EntryVisibility = .sharedImmediately,
                           evidences: [Data] = []) throws -> CDLedgerEntry {
        try repo.createEntry(couple: couple, category: .praise, title: "下雨天来接我",
                             detail: "绕了四公里", happenedAt: Date(timeIntervalSince1970: 1_000),
                             visibility: visibility, place: nil,
                             evidenceDatas: evidences, authorID: myID)
    }

    func testCreateWritesFieldsAndEvidences() throws {
        let data1 = makeImageData(), data2 = Data([0x02])
        let entry = try makeEntry(evidences: [data1, data2])
        XCTAssertEqual(entry.categoryRaw, LedgerCategory.praise.rawValue)
        XCTAssertEqual(entry.title, "下雨天来接我")
        XCTAssertEqual(entry.detail, "绕了四公里")
        XCTAssertEqual(entry.authorPartnerID, myID)
        XCTAssertEqual(entry.visibilityRaw, EntryVisibility.sharedImmediately.rawValue)
        XCTAssertNil(entry.revealedAt)
        XCTAssertNotNil(entry.createdAt)
        let evidences = repo.evidencesSorted(entry)
        XCTAssertEqual(evidences.map(\.sortIndex), [0, 1])
        XCTAssertEqual(evidences[0].imageData, data1)
        XCTAssertNotNil(evidences[0].thumbnailData)   // 真实图像数据走缩略管线
        XCTAssertNil(evidences[1].thumbnailData)      // 非图像字节缩略为 nil（Thumbnailer 既有契约）
    }

    func testRevealSetsOnceAndIsIrreversible() throws {
        let entry = try makeEntry(visibility: .privateUntilRevealed)
        let first = Date(timeIntervalSince1970: 5_000)
        try repo.reveal(entry, at: first)
        XCTAssertEqual(entry.revealedAt, first)
        try repo.reveal(entry, at: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(entry.revealedAt, first)        // 二次 reveal 不改时戳
    }

    func testUpdateDoesNotTouchVisibility() throws {
        let entry = try makeEntry(visibility: .privateUntilRevealed)
        try repo.updateEntry(entry, category: .complaint, title: "改了", detail: nil,
                             happenedAt: Date(timeIntervalSince1970: 2_000), place: nil)
        XCTAssertEqual(entry.categoryRaw, LedgerCategory.complaint.rawValue)
        XCTAssertEqual(entry.title, "改了")
        XCTAssertNil(entry.detail)
        XCTAssertEqual(entry.visibilityRaw, EntryVisibility.privateUntilRevealed.rawValue)
        XCTAssertNil(entry.revealedAt)
    }

    func testAddAndDeleteEvidenceKeepsOrder() throws {
        let entry = try makeEntry(evidences: [Data([0x01])])
        try repo.addEvidences(entry, datas: [Data([0x02])])
        var evidences = repo.evidencesSorted(entry)
        XCTAssertEqual(evidences.map(\.sortIndex), [0, 1])   // 追加续接序号
        try repo.deleteEvidence(evidences[0])
        evidences = repo.evidencesSorted(entry)
        XCTAssertEqual(evidences.count, 1)
        XCTAssertEqual(evidences[0].imageData, Data([0x02]))
    }

    func testDeleteCascadesEvidences() throws {
        let entry = try makeEntry(evidences: [Data([0x01]), Data([0x02])])
        try repo.delete(entry)
        let left = try pc.viewContext.fetch(NSFetchRequest<CDEvidence>(entityName: "CDEvidence"))
        XCTAssertTrue(left.isEmpty)                    // 模型级联删证据
    }
}
