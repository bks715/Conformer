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
        
        guard let tableName = structDecl.memberBlock.members.first(where: {
            $0.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "tableName"
        })?.decl.as(VariableDeclSyntax.self)?.bindings.first?.initializer?.value.description else { return [""] }
        
        guard let columnMembers = structDecl.memberBlock.members.first(where: {$0.decl.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "columns" }),
              let columns = columnMembers.decl.as(VariableDeclSyntax.self)?.bindings.first?.initializer?.value.as(FunctionCallExprSyntax.self)?.calledExpression.as(ClosureExprSyntax.self)?.statements,
              let elements = columns.first?.item.as(ReturnStmtSyntax.self)?.expression?.as(ArrayExprSyntax.self)?.elements
        else {
            return ["MARK: Add the variable columns to your struct. var columns: [any TableColumnProtocol] = [* Add Each Column in your table to the array *]"]
        }
        var tableColumns: [TableColumnParser] = []
        //MARK: Add Variables to Code
        let variables = elements.compactMap{ element in
            guard let individualElement = element.expression.as(FunctionCallExprSyntax.self),
                  let individualType = individualElement.calledExpression.as(IdentifierExprSyntax.self)?.identifier.text
            else { return "" }
            let tableColumn = TableColumnParser(individualElement.argumentList)
            tableColumns.append(tableColumn)
            //Check if the Column is Foreign Key or Normal
            switch individualType{
            case "ForeignKeyColumn":
                if let targetColumn = tableColumn.targetColumn{
                    return "public var \(targetColumn): String?"
                }
            default:
                if let name = tableColumn.name, let valueType = tableColumn.valueType{
                    return "public var \(name): \(valueType)"
                }
            }
            return ""
        }
        
        let staticVars = tableColumns.filter({$0.isForeignKey == true }).map{ tableColumn in
            if let name = tableColumn.name, let valueType = tableColumn.valueType{
                return "public static let \(name) = hasMany(\(valueType).self)"
            }
            return ""
        }
        //First we add the variables for each of the table's standard columns
        //Then we add the static variables for the foreign key columns
        //Then we add things to conform to codable... Coding Keys, encode method, init from decoder
        return [
                """
                public static let databaseTableName = \(raw: tableName.camelToSnakeCase)
                \(raw: variables.joined(separator: "\n"))
                public var isDeleted: Bool = false
                public var updatedAt: Date?
                \n
                \(raw: conformToCodable(tableColumns))
                \n
                \(raw: createTable(tableName, tableColumns))
                \n
                \(raw: createRemoteFetchRequest(name: tableName))
                """
        ]
    }
    
    private static func conformToCodable(_ elements: [TableColumnParser] ) -> String {
        var codingKeys: [String] = []
        for element in elements{
            //Create Coding Keys
            guard element.isForeignKey != true else {
                //The element is a foreign key
                guard let name = element.targetColumn ?? element.sourceColumn else { continue }
                codingKeys.append("case \(name) = \"\(name.camelToSnakeCase)\"")
                continue
            }
            guard let name = element.name else { continue }
            codingKeys.append("case \(name) = \"\(name.camelToSnakeCase)\"")
            //Encode
            //Decode
            
        }
        return """
                public enum CodingKeys: String, CodingKey {
                    \(codingKeys.joined(separator: "\n    "))
                    case isDeleted = "is_deleted"
                    case updatedAt = "updated_at"
                }
                """
    }
    
    private static func createTable(_ tableName: String, _ elements: [TableColumnParser] ) -> String {
        let primaryKeys = elements.filter{ $0.isPrimaryKey == true }
        let primaryKeyStatements: String = primaryKeys.enumerated().reduce("t.primaryKey([", { string, columnItem in
            let (index, column) = columnItem
            let comma = index == (primaryKeys.count - 1) ? "" : ","
            guard column.isForeignKey == nil, let name = column.name else { return "" }
            return  """
                \(string) "\(name.camelToSnakeCase)"\(comma)
                """
        })
        
        let creationStatements: [String] = elements.compactMap({ column in
            guard let name = column.name, let valueType = column.valueType, let grdbType = column.grdbType else { return nil }
            let isOptional = valueType.contains("?") ? "" : ".notNull()"
            if column.isForeignKey == true {
                //Actually Handle Foreign Key Here
                guard let sourceColumn = column.sourceColumn, let sourceName = column.sourceName, let targetColumn = column.targetColumn else { return nil }
                return """
                       t.column("\(targetColumn.camelToSnakeCase)", .text)
                            .references("\(sourceName.camelToSnakeCase)", column: "\(sourceColumn.camelToSnakeCase)", onDelete: .cascade)
                    """
            }else{
                return """
                       t.column("\(name.camelToSnakeCase)", \(grdbType))\(isOptional)
                       """
            }
        })
        
        return """
            public static func createTable(_ db: Database) throws {
                try db.create(table: \(tableName.camelToSnakeCase)){ t in
                    //Add the Columns
                    \(creationStatements.joined(separator: "\n  "))
                    //Add isDeleted and updatedAt
                    t.column("updated_at", Database.ColumnType.datetime)
                    t.column("is_deleted", Database.ColumnType.boolean).notNull()
                    //Add the Primary Keys
                    \(primaryKeys.isEmpty ? "" : primaryKeyStatements)])
                    //
                }
            }
            """
    }
    
    private static func createRemoteFetchRequest(name: String) -> String {
        return """
                public static func fetchFromRemote(_ client: SupabaseClient, lastUpdate: Date) async throws -> [Self]{
                    let data: [Self] = try await client.database.from(tableName).select().eq(column: "is_deleted", value: false).greaterThanOrEquals(column: "updated_at", value: lastUpdate.ISO8601Format()).execute().value
                    return data
                }
        """
    }
    
    //Make a camel case to snake case function
    
}

struct TableColumnParser {
    
    var name: String?
    var valueType: String?
    var isForeignKey: Bool?
    var isPrimaryKey: Bool?
    var sourceName: String?
    var sourceColumn: String?
    var targetColumn: String?
    
    init(_ node: TupleExprElementListSyntax) {
        for element in node{
            let label = element.label?.text
            if label == "name", let stringLiteralExpr = element.expression.as(StringLiteralExprSyntax.self){
                self.name = stringLiteralExpr.segments.first?.as(StringSegmentSyntax.self)?.content.text
            } else if label == "valueType", let memberAccessExpr = element.expression.as(MemberAccessExprSyntax.self) {
                self.valueType = memberAccessExpr.base?.description
            } else if label == "isPrimaryKey", let booleanLiteralExpr = element.expression.as(BooleanLiteralExprSyntax.self) {
                self.isPrimaryKey = booleanLiteralExpr.booleanLiteral.text == "true"
            }else if label == "sourceColumn", let expression = element.expression.as(StringLiteralExprSyntax.self) {
                self.isForeignKey = true
                self.sourceColumn = expression.segments.description
                self.sourceName = valueType
            }else if label == "targetColumn", let expression = element.expression.as(StringLiteralExprSyntax.self) {
                self.targetColumn = expression.segments.description
            }
        }
        
    }
}
//MARK: GRDB Data Type Mapping -
extension TableColumnParser {
    
    var grdbType: String? {
        let valueType = valueType?.filter({ $0 != "?" })
        switch valueType {
           case "String":
               return "Database.ColumnType.text"
           case "Int", "Int64":
               return "Database.ColumnType.integer"
           case "Double":
               return "Database.ColumnType.double"
           case "Float":
               return "Database.ColumnType.real" // REAL is a floating-point value
           case "Bool":
               return "Database.ColumnType.boolean"
           case "Data":
               return "Database.ColumnType.blob"
           case "Date":
               return "Database.ColumnType.datetime" // or datetime, if you're storing date and time
           default:
               return "Database.ColumnType.any" // fallback type
           }
    }
    
}


@main
struct ConformerPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
        SupamodeledMacro.self,
    ]
}

