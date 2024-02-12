//
//  InsulinType.swift
//  LoopKit
//
//  Created by Anna Quinlan on 12/8/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation

public enum InsulinType: Int, Codable, CaseIterable {
    case novolog
    case humalog
    case apidra
    case fiasp
    case lyumjev
    case afrezza
}
