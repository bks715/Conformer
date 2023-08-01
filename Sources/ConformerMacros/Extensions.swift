//
//  File.swift
//  
//
//  Created by Braden Smith on 7/29/23.
//

import Foundation

extension String {
    
    var camelToSnakeCase: String {
        var newString = ""
        for char in self{
            if char.isUppercase{
                newString.append("_")
                newString.append(char.lowercased())
            }else{
                newString.append(char)
            }
        }
        return newString
    }
    
    var snakeToCamelCase: String {
        var newString = ""
        var capitalizeNext = false
        for char in self{
            if char == "_"{
                capitalizeNext = true
            }else{
                if capitalizeNext{
                    newString.append(char.uppercased())
                    capitalizeNext = false
                }else{
                    newString.append(char)
                }
            }
        }
        return newString
    }
    
}
