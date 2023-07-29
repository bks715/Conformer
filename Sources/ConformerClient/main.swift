import Conformer
import GRDB
import Foundation

@Supamodeled
struct TaskThing {
    static var tableName: String = "task_thing"
    var columns: [any TableColumnProtocol] = { return [ TableColumn(name: "id", valueType: String.self, isPrimaryKey: true),
                                                        TableColumn(name: "name", valueType: String.self),
                                                        TableColumn(name: "createdAt", valueType: Date?.self),
                                                        ForeignKeyColumn(name: "otherThing", valueType: BlankThing.self, sourceColumn: "id", targetColumn: "blank_thing_id")
                                                ] }()
}

@Supamodeled
struct BlankThing {
    static var tableName = "blank_thing"
    var columns: [any TableColumnProtocol] = {
        return [
            TableColumn(name: "id", valueType: String.self),
            TableColumn(name: "name", valueType: String.self)
        ]
    }()
}








//MARK: Jargon -
public protocol TableColumnProtocol{
    associatedtype varType
    var name: String {get}
    var valueType: varType.Type {get}
    var isPrimaryKey: Bool { get }
    //Name, If it's ID or Not, If so is it Automatic, Value
}

extension TableColumnProtocol{
    
    public var isPrimaryKey: Bool { return false }
    
}

public struct TableColumn<A: Codable>: TableColumnProtocol{
    public typealias varType = A
    public var name: String
    public var valueType: varType.Type
    public var isPrimaryKey: Bool = false
}

public protocol SupaModel: FetchableRecord, PersistableRecord {
    static var tableName: String {get}
    var columns: [any TableColumnProtocol] {get}
}

public struct ForeignKeyColumn<A: SupaModel>: TableColumnProtocol {
    public var name: String
    public var valueType: A.Type
    public var sourceColumn: String
    public var targetColumn: String
    
    public init(name: String, valueType: A.Type, sourceColumn: String, targetColumn: String? = nil ){
        self.name = name
        self.valueType = valueType
        self.sourceColumn = sourceColumn
        self.targetColumn = targetColumn ?? sourceColumn
    }
}
