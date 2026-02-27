//
//  TaskHandle.swift
//  ResourceQueue
//
//  Created by Andrew on 27.02.2026.
//

/// A handle to an enqueued task in a ``ResourceQueue``.
///
/// Use the handle to:
/// - Await the task's result via ``value``.
/// - Cancel the task via ``cancel()``.
/// - Change the task's priority via ``updatePriority(_:)``.
///
/// ```swift
/// let handle = try queue.enqueue(priority: .high) {
///     try await performWork()
/// }
///
/// // Optionally boost priority before it starts
/// await handle.updatePriority(.high)
///
/// // Await the result
/// let result = try await handle.value
/// ```
public final class TaskHandle<T: Sendable, P: PriorityProtocol, R: Resolver<P>>: Sendable {

    private let id: UInt64
    private let queue: ResourceQueue<P, R>

    init(id: UInt64, queue: ResourceQueue<P, R>) {
        self.id = id
        self.queue = queue
    }

    /// The result of the enqueued operation.
    ///
    /// Suspends until the task completes. If the operation throws, the error is rethrown.
    /// If the task was cancelled, throws `CancellationError`.
    public var value: T {
        get async throws {
            let result = try await queue.awaitResult(id: id)
            // Safe force cast: we control the type going in via enqueue<T>
            return result as! T
        }
    }

    /// Cancels the task.
    ///
    /// - If the task is **pending**, it is removed from the queue and any awaiter
    ///   of ``value`` receives a `CancellationError`.
    /// - If the task is **running**, it is cooperatively cancelled via Swift's
    ///   task cancellation mechanism.
    /// - If the task is already **completed** or **cancelled**, this is a no-op.
    public func cancel() async {
        await queue.cancel(id: id)
    }

    /// Updates the priority of a pending task.
    ///
    /// If the task is still in the pending list, it is re-sorted with the new priority
    /// and the drain loop is triggered, potentially starting it immediately.
    ///
    /// If the task is already running or completed, this is a no-op.
    ///
    /// - Parameter newPriority: The new priority to assign.
    public func updatePriority(_ newPriority: P) async {
        await queue.updatePriority(id: id, to: newPriority)
    }
}
