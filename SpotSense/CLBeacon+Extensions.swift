//
//  CLBeacon+Extensions.swift
//  SpotSense
//
//  Created by 小玉敦郎 on 2025/04/09.
//

import CoreLocation

extension CLBeacon {
    var uniqueID: String {
        "\(uuid.uuidString)-\(major)-\(minor)"
    }
}
