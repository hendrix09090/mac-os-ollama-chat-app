//
//  Item.swift
//  DRS-Studio-AI
//
//  Created by danny on 2025/2/20.
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
