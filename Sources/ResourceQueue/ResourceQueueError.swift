//
//  ResourceQueueError.swift
//  ResourceQueue
//
//  Created by Andrew on 27.02.2026.
//

/// Errors thrown by ``ResourceQueue``.
public enum ResourceQueueError: Error {
    /// The number of pending tasks has reached the configured limit.
    case pendingLimitExceeded
}
