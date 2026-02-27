import Foundation
import os
import Testing
@testable import ResourceQueue

// MARK: - Priority Tests

@Suite("Priority ordering")
struct PriorityTests {

    @Test func lowIsLessThanMedium() {
        #expect(Priority.low < Priority.medium)
    }

    @Test func mediumIsLessThanHigh() {
        #expect(Priority.medium < Priority.high)
    }

    @Test func lowIsLessThanHigh() {
        #expect(Priority.low < Priority.high)
    }

    @Test func samePrioritiesAreEqual() {
        #expect(Priority.high == Priority.high)
        #expect(Priority.medium == Priority.medium)
        #expect(Priority.low == Priority.low)
    }

    @Test func sortedArrayMatchesExpectedOrder() {
        let shuffled: [Priority] = [.high, .low, .medium]
        let sorted = shuffled.sorted()
        #expect(sorted == [.low, .medium, .high])
    }
}

// MARK: - OrderedPriority Tests

@Suite("OrderedPriority ordering")
struct OrderedPriorityTests {

    @Test func levelTakesPrecedenceOverOrder() {
        let lowHighOrder = OrderedPriority(level: .low, order: 100)
        let highLowOrder = OrderedPriority(level: .high, order: 0)
        #expect(lowHighOrder < highLowOrder)
    }

    @Test func sameLevel_higherOrderWins() {
        let first = OrderedPriority(level: .medium, order: 1)
        let second = OrderedPriority(level: .medium, order: 10)
        #expect(first < second)
    }

    @Test func sameLevelAndOrder_areEqual() {
        let a = OrderedPriority(level: .high, order: 5)
        let b = OrderedPriority(level: .high, order: 5)
        #expect(a == b)
    }

    @Test func sortedArrayMatchesExpectedOrder() {
        let items = [
            OrderedPriority(level: .high, order: 1),
            OrderedPriority(level: .low, order: 0),
            OrderedPriority(level: .high, order: 10),
            OrderedPriority(level: .medium, order: 5),
        ]
        let sorted = items.sorted()
        #expect(sorted == [
            OrderedPriority(level: .low, order: 0),
            OrderedPriority(level: .medium, order: 5),
            OrderedPriority(level: .high, order: 1),
            OrderedPriority(level: .high, order: 10),
        ])
    }
}

// MARK: - Int as PriorityProtocol Tests

@Suite("Int as PriorityProtocol")
struct IntPriorityTests {

    @Test func intComparison() {
        let low: Int = 1
        let high: Int = 10
        #expect(low < high)
    }

    @Test func intsSortCorrectly() {
        let priorities = [5, 1, 10, 3]
        let sorted = priorities.sorted()
        #expect(sorted == [1, 3, 5, 10])
    }
}

// MARK: - FixedResolver Tests

@Suite("FixedResolver")
struct FixedResolverTests {

    @Test func allowsWhenBelowConcurrency() {
        let resolver = FixedResolver<Priority>(concurrency: 3)
        #expect(resolver.shouldStart(executingCount: 0, priority: .low))
        #expect(resolver.shouldStart(executingCount: 1, priority: .low))
        #expect(resolver.shouldStart(executingCount: 2, priority: .low))
    }

    @Test func blocksWhenAtConcurrency() {
        let resolver = FixedResolver<Priority>(concurrency: 3)
        #expect(!resolver.shouldStart(executingCount: 3, priority: .high))
    }

    @Test func blocksWhenAboveConcurrency() {
        let resolver = FixedResolver<Priority>(concurrency: 3)
        #expect(!resolver.shouldStart(executingCount: 5, priority: .high))
    }

    @Test func ignoresPriority() {
        let resolver = FixedResolver<Priority>(concurrency: 2)
        // Same executingCount, different priorities — same result
        #expect(resolver.shouldStart(executingCount: 1, priority: .low))
        #expect(resolver.shouldStart(executingCount: 1, priority: .high))
        #expect(!resolver.shouldStart(executingCount: 2, priority: .low))
        #expect(!resolver.shouldStart(executingCount: 2, priority: .high))
    }

    @Test func zeroConcurrencyBlocksEverything() {
        let resolver = FixedResolver<Priority>(concurrency: 0)
        #expect(!resolver.shouldStart(executingCount: 0, priority: .high))
    }
}

// MARK: - LaneResolver Tests

@Suite("LaneResolver")
struct LaneResolverTests {

    private func makeResolver() -> LaneResolver<Priority> {
        LaneResolver<Priority> { priority in
            switch priority {
            case .high:   10
            case .medium:  5
            case .low:     2
            }
        }
    }

    @Test func highPriorityUsesFullCapacity() {
        let resolver = makeResolver()
        #expect(resolver.shouldStart(executingCount: 0, priority: .high))
        #expect(resolver.shouldStart(executingCount: 9, priority: .high))
        #expect(!resolver.shouldStart(executingCount: 10, priority: .high))
    }

    @Test func mediumPriorityLimitedToOwnAndLowerSlots() {
        let resolver = makeResolver()
        #expect(resolver.shouldStart(executingCount: 4, priority: .medium))
        #expect(!resolver.shouldStart(executingCount: 5, priority: .medium))
    }

    @Test func lowPriorityOnlyUsesOwnSlots() {
        let resolver = makeResolver()
        #expect(resolver.shouldStart(executingCount: 1, priority: .low))
        #expect(!resolver.shouldStart(executingCount: 2, priority: .low))
    }

    @Test func zeroCapacityDisablesPriority() {
        let resolver = LaneResolver<Priority> { priority in
            switch priority {
            case .high:   5
            case .medium:  0
            case .low:     0
            }
        }
        #expect(!resolver.shouldStart(executingCount: 0, priority: .low))
        #expect(!resolver.shouldStart(executingCount: 0, priority: .medium))
        #expect(resolver.shouldStart(executingCount: 0, priority: .high))
    }

    @Test func dynamicCapacityIsReEvaluated() {
        var constrained = false
        // nonisolated(unsafe) since we're mutating from a single test context
        nonisolated(unsafe) let isConstrained = { constrained }

        let resolver = LaneResolver<Priority> { priority in
            if isConstrained() {
                return priority == .high ? 2 : 0
            }
            return 10
        }

        // Normal mode: medium allowed at 5
        #expect(resolver.shouldStart(executingCount: 5, priority: .medium))

        // Switch to constrained
        constrained = true
        #expect(!resolver.shouldStart(executingCount: 0, priority: .medium))
        #expect(resolver.shouldStart(executingCount: 1, priority: .high))
        #expect(!resolver.shouldStart(executingCount: 2, priority: .high))
    }

    @Test func worksWithIntPriority() {
        let resolver = LaneResolver<Int> { priority in
            switch priority {
            case 8...:   10
            case 4..<8:   5
            default:      1
            }
        }
        #expect(resolver.shouldStart(executingCount: 0, priority: 1))
        #expect(!resolver.shouldStart(executingCount: 1, priority: 1))
        #expect(resolver.shouldStart(executingCount: 4, priority: 5))
        #expect(!resolver.shouldStart(executingCount: 5, priority: 5))
        #expect(resolver.shouldStart(executingCount: 9, priority: 10))
        #expect(!resolver.shouldStart(executingCount: 10, priority: 10))
    }

    @Test func worksWithOrderedPriority() {
        let resolver = LaneResolver<OrderedPriority> { priority in
            switch priority.level {
            case .high:   10
            case .medium:  5
            case .low:     1
            }
        }
        let highTask = OrderedPriority(level: .high, order: 1)
        let lowTask = OrderedPriority(level: .low, order: 1)

        #expect(resolver.shouldStart(executingCount: 9, priority: highTask))
        #expect(!resolver.shouldStart(executingCount: 1, priority: lowTask))
    }
}

// MARK: - ResourceQueue Tests

@Suite("ResourceQueue")
struct ResourceQueueTests {

    @Test func basicEnqueueAndGetResult() async throws {
        let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 2))
        let handle = try await queue.enqueue(priority: .high) {
            42
        }
        let result = try await handle.value
        #expect(result == 42)
    }

    @Test func enqueueReturnsCorrectType() async throws {
        let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 1))
        let handle = try await queue.enqueue(priority: .medium) {
            "hello"
        }
        let result = try await handle.value
        #expect(result == "hello")
    }

    @Test func operationErrorPropagates() async throws {
        struct TestError: Error {}
        let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 1))
        let handle = try await queue.enqueue(priority: .high) {
            throw TestError()
            return 0
        }
        await #expect(throws: TestError.self) {
            try await handle.value
        }
    }

    @Test func pendingLimitExceeded() async throws {
        let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 0), pendingLimit: 2)
        // concurrency=0 means nothing starts, so all tasks stay pending
        try await queue.enqueue(priority: .low) { 1 }
        try await queue.enqueue(priority: .low) { 2 }

        await #expect(throws: ResourceQueueError.self) {
            try await queue.enqueue(priority: .low) { 3 }
        }
    }

    @Test func concurrencyLimitRespected() async throws {
        let maxConcurrent = OSAllocatedUnfairLock(initialState:0)
        let currentConcurrent = OSAllocatedUnfairLock(initialState:0)

        let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 2))

        // Launch 6 tasks that each take a bit of time
        var handles: [TaskHandle<Int, Priority, FixedResolver<Priority>>] = []
        for i in 0..<6 {
            let handle = try await queue.enqueue(priority: .medium) {
                currentConcurrent.withLock { $0 += 1 }
                let current = currentConcurrent.withLock { $0 }
                maxConcurrent.withLock { $0 = max($0, current) }
                try await Task.sleep(for: .milliseconds(50))
                currentConcurrent.withLock { $0 -= 1 }
                return i
            }
            handles.append(handle)
        }

        // Await all results
        for handle in handles {
            _ = try await handle.value
        }

        let peak = maxConcurrent.withLock { $0 }
        #expect(peak <= 2)
    }

    @Test func highPriorityExecutesFirst() async throws {
        let executionOrder = OSAllocatedUnfairLock<[String]>(initialState: [])

        // Use concurrency=1 so tasks execute one at a time in priority order
        let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 1))

        // First, enqueue a blocking task to hold the slot
        let blocker = OSAllocatedUnfairLock(initialState:true)
        try await queue.enqueue(priority: .high) {
            while blocker.withLock({ $0 }) {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        // While blocked, enqueue low then high
        let lowHandle = try await queue.enqueue(priority: .low) {
            executionOrder.withLock { $0.append("low") }
        }
        let highHandle = try await queue.enqueue(priority: .high) {
            executionOrder.withLock { $0.append("high") }
        }

        // Release the blocker
        blocker.withLock { $0 = false }

        _ = try await highHandle.value
        _ = try await lowHandle.value

        let order = executionOrder.withLock { $0 }
        #expect(order == ["high", "low"])
    }

    @Test func cancelPendingTask() async throws {
        // concurrency=0 so nothing starts — tasks stay pending
        let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 0), pendingLimit: 10)
        let handle = try await queue.enqueue(priority: .medium) { 42 }

        await handle.cancel()

        await #expect(throws: CancellationError.self) {
            try await handle.value
        }
    }

    @Test func cancelRunningTask() async throws {
        let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 1))
        let started = OSAllocatedUnfairLock(initialState:false)

        let handle = try await queue.enqueue(priority: .high) {
            started.withLock { $0 = true }
            // Long-running work that checks for cancellation
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(10))
            }
            throw CancellationError()
            return 0
        }

        // Wait for it to start
        while !started.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(10))
        }

        await handle.cancel()

        await #expect(throws: CancellationError.self) {
            try await handle.value
        }
    }

    @Test func updatePriorityOfPendingTask() async throws {
        let executionOrder = OSAllocatedUnfairLock<[String]>(initialState: [])

        let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 1))

        // Block the slot
        let blocker = OSAllocatedUnfairLock(initialState:true)
        try await queue.enqueue(priority: .high) {
            while blocker.withLock({ $0 }) {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        // Enqueue two tasks: medium and low
        let mediumHandle = try await queue.enqueue(priority: .medium) {
            executionOrder.withLock { $0.append("medium") }
        }
        let lowHandle = try await queue.enqueue(priority: .low) {
            executionOrder.withLock { $0.append("was-low-now-high") }
        }

        // Boost the low task above medium
        await lowHandle.updatePriority(Priority.high)

        // Release blocker
        blocker.withLock { $0 = false }

        _ = try await lowHandle.value
        _ = try await mediumHandle.value

        let order = executionOrder.withLock { $0 }
        #expect(order == ["was-low-now-high", "medium"])
    }

    @Test func laneResolverIntegration() async throws {
        let maxConcurrent = OSAllocatedUnfairLock(initialState:0)
        let currentConcurrent = OSAllocatedUnfairLock(initialState:0)

        let resolver = LaneResolver<Priority> { priority in
            switch priority {
            case .high:   4
            case .medium:  2
            case .low:     1
            }
        }
        let queue = ResourceQueue(resolver: resolver)

        // Enqueue 4 low-priority tasks
        var handles: [TaskHandle<Void, Priority, LaneResolver<Priority>>] = []
        for _ in 0..<4 {
            let handle = try await queue.enqueue(priority: .low) {
                currentConcurrent.withLock { $0 += 1 }
                let current = currentConcurrent.withLock { $0 }
                maxConcurrent.withLock { $0 = max($0, current) }
                try await Task.sleep(for: .milliseconds(50))
                currentConcurrent.withLock { $0 -= 1 }
            }
            handles.append(handle)
        }

        for handle in handles {
            try await handle.value
        }

        // Low priority capacity is 1, so at most 1 should run at a time
        let peak = maxConcurrent.withLock { $0 }
        #expect(peak <= 1)
    }
}
