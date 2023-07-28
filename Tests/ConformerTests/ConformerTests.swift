import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import ConformerMacros

let testMacros: [String: Macro.Type] = [
    "stringify": StringifyMacro.self,
]

final class ConformerTests: XCTestCase {
    func testMacro() {
        assertMacroExpansion(
            """
            #stringify(a + b)
            """,
            expandedSource: """
            (a + b, "a + b")
            """,
            macros: testMacros
        )
    }

    func testMacroWithStringLiteral() {
        assertMacroExpansion(
            #"""
            #stringify("Hello, \(name)")
            """#,
            expandedSource: #"""
            ("Hello, \(name)", #""Hello, \(name)""#)
            """#,
            macros: testMacros
        )
    }
}
