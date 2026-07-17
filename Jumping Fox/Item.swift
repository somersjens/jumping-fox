//
//  Item.swift
//  Jumping Fox
//
//  Created by Jens Somers on 17/07/2026.
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
