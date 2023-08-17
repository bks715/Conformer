// The Swift Programming Language
// https://docs.swift.org/swift-book

/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,

@attached(extension)
@attached(member, names: arbitrary)
public macro Supamodeled() = #externalMacro(module: "ConformerMacros", type: "SupamodeledMacro")
