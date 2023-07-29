import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `stringify` macro, which takes an expression
/// of any type and produces a tuple containing the value of that expression
/// and the source code that produced the value. For example
///
///     #stringify(x + y)
///
///  will expand to
///
///     (x + y, "x + y")
public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let argument = node.argumentList.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }

        return "(\(argument), \(literal: argument.description))"
    }
}

public struct SupamodeledMacro: ConformanceMacro, MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingConformancesOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [(TypeSyntax, GenericWhereClauseSyntax?)] {
        [("Codable, FetchableRecord, PersistableRecord, SupaModel", nil)]
    }
    
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
            let structDecl = declaration.cast(StructDeclSyntax.self)
            
        guard let columnMembers = structDecl.memberBlock.members.first(where: {$0.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "columns" }),
              let columns = columnMembers.decl.as(VariableDeclSyntax.self)?.bindings.first?.initializer?.value.as(FunctionCallExprSyntax.self)?.calledExpression.as(ClosureExprSyntax.self)?.statements,
              let elements = columns.first?.item.as(ReturnStmtSyntax.self)?.expression?.as(ArrayExprSyntax.self)?.elements
        else {
            return ["MARK: Add the variable columns to your struct. var columns: [any TableColumnProtocol] = [* Add Each Column in your table to the array *]"]
        }
        var newVariables: [(name: String,type: String)] = []
        //MARK: Add Variables to Code
        let variables = elements.compactMap{ element in
            guard let individualElement = element.expression.as(FunctionCallExprSyntax.self),
                  let individualType = individualElement.calledExpression.as(IdentifierExprSyntax.self)?.identifier.text,
                  let argumentList = element.expression.as(FunctionCallExprSyntax.self)?.argumentList,
                  let name = argumentList.first?.expression.as(StringLiteralExprSyntax.self)?.segments.first?.as(StringSegmentSyntax.self)?.content.text,
                  let valueDecl = argumentList.first(where: {$0.label?.text == "valueType"})?.expression.as(MemberAccessExprSyntax.self)?.base
            else { return "" }
            //Check if the Column is Foreign Key or Normal
            switch individualType{
            case "ForeignKeyColumn":
                if let value = valueDecl.as(IdentifierExprSyntax.self)?.identifier.text{
//                    newVariables.append((name: name, type: value))
                    return "static let \(name) = hasMany(\(value).self)"
                }else if let value = valueDecl.as(OptionalChainingExprSyntax.self)?.expression.as(IdentifierExprSyntax.self)?.identifier.text{
//                    newVariables.append((name: name, type: value))
                    return "static let \(name) = hasMany(\(value).self)"
                }
            default:
                if let value = valueDecl.as(IdentifierExprSyntax.self)?.identifier.text{
                    newVariables.append((name: name, type: value))
                    return "var \(name): \(value)"
                }else if let value = valueDecl.as(OptionalChainingExprSyntax.self)?.expression.as(IdentifierExprSyntax.self)?.identifier.text{
                    newVariables.append((name: name, type: value))
                    return "var \(name): \(value)"
                }
            }
            return ""
        }
        //First we add the variables for each of the table's standard columns
        //Then we add the static variables for the foreign key columns
        //Then we add things to conform to codable... Coding Keys, encode method, init from decoder
        return [
                """
                \(raw: variables.joined(separator: "\n"))
                \(raw: columnMembers.decl.debugDescription)
                \n\n
                \(raw: conformToCodable(newVariables))
                """
        ]
    }
    
    private static func conformToCodable(_ elements: [(name: String, type: String)]) -> String {
        var codingKeys: [String] = []
        for element in elements{
            //Create Coding Keys
            codingKeys.append(element.name)
            //Encode
            //Decode
            
        }
        return """
                enum CodingKeys: CodingKey {
                    \(codingKeys.joined(separator: ", "))
                """
    }
    
}

@main
struct ConformerPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
        SupamodeledMacro.self,
    ]
}

