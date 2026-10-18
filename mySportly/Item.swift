//
//  Item.swift
//  mySportly
//
//  Created by shimmy kohn on 10/18/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
