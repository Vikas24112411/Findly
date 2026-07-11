import Testing
import Foundation
@testable import Findly

// MARK: - TagGraphTraverser Tests

@Suite("TagGraphTraverser")
struct TagGraphTraverserTests {

    // MARK: - Descendants

    @Test("allDescendants returns root only for leaf node")
    func leafNodeDescendants() {
        let leaf = Tag(name: "Lion")
        let result = TagGraphTraverser.allDescendants(of: leaf)
        #expect(result.count == 1)
        #expect(result.contains(leaf))
    }

    @Test("allDescendants traverses multi-level hierarchy")
    func multiLevelDescendants() {
        let animals   = Tag(name: "Animals")
        let mammals   = Tag(name: "Mammals")
        let lion      = Tag(name: "Lion")

        // Wire up: Animals → Mammals → Lion
        mammals.parents.append(animals)
        animals.children.append(mammals)
        lion.parents.append(mammals)
        mammals.children.append(lion)

        let result = TagGraphTraverser.allDescendants(of: animals)
        #expect(result.count == 3)
        #expect(result.contains(animals))
        #expect(result.contains(mammals))
        #expect(result.contains(lion))
    }

    @Test("allDescendants handles DAG with shared children")
    func dagSharedDescendant() {
        let wildlife  = Tag(name: "Wildlife")
        let africa    = Tag(name: "Africa")
        let lion      = Tag(name: "Lion") // has two parents

        wildlife.children.append(lion)
        lion.parents.append(wildlife)
        africa.children.append(lion)
        lion.parents.append(africa)

        let wildlifeDesc = TagGraphTraverser.allDescendants(of: wildlife)
        #expect(wildlifeDesc.count == 2) // wildlife + lion (no duplicates)

        let africaDesc = TagGraphTraverser.allDescendants(of: africa)
        #expect(africaDesc.count == 2) // africa + lion
    }

    // MARK: - Cycle detection

    @Test("wouldCreateCycle detects self-loop")
    func selfLoop() {
        let tag = Tag(name: "A")
        #expect(TagGraphTraverser.wouldCreateCycle(adding: tag, to: tag) == true)
    }

    @Test("wouldCreateCycle detects cycle in chain")
    func chainCycle() {
        let a = Tag(name: "A")
        let b = Tag(name: "B")
        let c = Tag(name: "C")

        // A → B → C
        a.children.append(b); b.parents.append(a)
        b.children.append(c); c.parents.append(b)

        // Adding A as child of C would create C → A → B → C cycle
        #expect(TagGraphTraverser.wouldCreateCycle(adding: c, to: a) == true)
    }

    @Test("wouldCreateCycle returns false for valid edge")
    func noCycle() {
        let a = Tag(name: "A")
        let b = Tag(name: "B")
        // No edges yet — adding A as parent of B is valid
        #expect(TagGraphTraverser.wouldCreateCycle(adding: a, to: b) == false)
    }

    // MARK: - Path

    @Test("pathFromRoot returns correct breadcrumb")
    func breadcrumb() {
        let animals = Tag(name: "Animals")
        let mammals = Tag(name: "Mammals")
        let lion    = Tag(name: "Lion")

        mammals.parents.append(animals)
        animals.children.append(mammals)
        lion.parents.append(mammals)
        mammals.children.append(lion)

        let path = TagGraphTraverser.pathFromRoot(to: lion)
        #expect(path.map(\.name) == ["Animals", "Mammals", "Lion"])
    }
}

// MARK: - FileType detection tests

@Suite("FileType Detection")
struct FileTypeDetectionTests {

    @Test("detects image from extension")
    func imageExtension() {
        #expect(FileType.detect(fileExtension: "jpg")  == .image)
        #expect(FileType.detect(fileExtension: "png")  == .image)
        #expect(FileType.detect(fileExtension: "heic") == .image)
    }

    @Test("detects PDF from MIME type")
    func pdfMime() {
        #expect(FileType.detect(mimeType: "application/pdf") == .pdf)
    }

    @Test("fallback to other for unknown extension")
    func unknownExtension() {
        #expect(FileType.detect(fileExtension: "xyz123") == .other)
    }
}
