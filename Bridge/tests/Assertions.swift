// Small assertion adapter for Command Line Tools installations without XCTest.
// The same test cases can also run under XCTest when full Xcode is installed.
import Foundation
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    precondition(a == b, "\(a) != \(b)", file: file, line: line)
}
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(abs(a - b) <= accuracy, "\(a) != \(b)", file: file, line: line)
}
func XCTAssertLessThan(_ a: Double, _ b: Double) { precondition(a < b) }
func XCTAssertGreaterThan(_ a: Double, _ b: Double) { precondition(a > b) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "Unexpected nil in test", code: 1) }
    return value
}
