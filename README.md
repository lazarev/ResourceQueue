# ResourceQueue

A priority-based concurrent task queue for Swift.

ResourceQueue manages async task execution with configurable concurrency limits per priority level. Higher-priority tasks can borrow execution slots from lower priorities, creating a lane-based scheduling model.

## Features

- **Priority-based scheduling** — tasks are executed in priority order
- **Lane-based concurrency** — higher-priority tasks can use lower-priority slots
- **Pluggable resolvers** — control admission logic via the `Resolver` protocol
- **Task handles** — cancel tasks, update priority, or await results
- **Backpressure** — configurable pending queue limit
- **Swift Concurrency** — built on actors, `async/await`, and structured concurrency

## Installation

Add ResourceQueue as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/lazarev/ResourceQueue.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "MyApp",
    dependencies: ["ResourceQueue"]
)
```

**Requirements:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+ · Swift 6.2+

## Quick Start

```swift
import ResourceQueue

// Create a queue with a fixed concurrency of 4
let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 4))

let handle = try queue.enqueue(priority: .high) {
    try await URLSession.shared.data(from: url)
}

let (data, response) = try await handle.value
```

## Priority Types

### Priority

A simple three-level enum: `.low`, `.medium`, `.high`.

```swift
let queue = ResourceQueue(resolver: FixedResolver<Priority>(concurrency: 4))

try queue.enqueue(priority: .high)   { /* runs first  */ }
try queue.enqueue(priority: .low)    { /* runs second */ }
```

### Int

`Int` conforms to `PriorityProtocol` out of the box. Higher values = higher priority.

```swift
let queue = ResourceQueue(resolver: FixedResolver<Int>(concurrency: 2))

try queue.enqueue(priority: 10) { /* high priority */ }
try queue.enqueue(priority: 1)  { /* low priority  */ }
```

### OrderedPriority

A composite type for sub-ordering within the same priority level:

```swift
let urgent  = OrderedPriority(level: .high, order: 10)
let routine = OrderedPriority(level: .high, order: 1)
// urgent runs before routine (same level, higher order)
```

### Custom Priorities

Conform any type to `PriorityProtocol` (which requires `Comparable` and `Sendable`):

```swift
enum JobPriority: Int, PriorityProtocol {
    case background = 0
    case normal = 1
    case critical = 2
}
```

## Resolvers

A resolver decides whether a pending task is allowed to start. The queue calls `shouldStart(executingCount:priority:)` each time a slot may become available.

### FixedResolver

Allows a fixed number of concurrent tasks, regardless of priority. Priority only affects the order in which pending tasks are picked.

```swift
let resolver = FixedResolver<Priority>(concurrency: 4)
let queue = ResourceQueue(resolver: resolver)
```

### LaneResolver

Divides concurrency into priority-based lanes. The closure returns the **cumulative capacity** — the total number of execution slots available to a task at that priority level (including all lower-priority slots).

```swift
let resolver = LaneResolver<Priority> { priority in
    switch priority {
    case .high:   10  // can use all 10 slots
    case .medium:  5  // can use up to 5 slots
    case .low:     2  // can use up to 2 slots
    }
}
```

This creates the following slot model:

| Priority | Own slots | Cumulative capacity |
|----------|-----------|---------------------|
| high     | 5         | 10 (5 + 3 + 2)     |
| medium   | 3         | 5 (3 + 2)           |
| low      | 2         | 2                   |

A `.high` task can start when fewer than 10 tasks are running. A `.low` task can only start when fewer than 2 are running. This means high-priority work can "borrow" slots that would otherwise be reserved for lower priorities.

Because the capacity is resolved via a closure, it can read from shared state and adapt to runtime conditions:

```swift
let resolver = LaneResolver<Priority> { priority in
    storage.cumulativeCapacity(for: priority)
}

// Later, when conditions change:
storage.update(low: 1, medium: 3, high: 5)
await queue.drain() // re-evaluate pending tasks
```

### Custom Resolvers

Implement the `Resolver` protocol for your own admission logic:

```swift
struct ThrottledResolver: Resolver {
    func shouldStart(executingCount: Int, priority: Priority) -> Bool {
        // your custom logic
    }
}
```

## Task Handles

`enqueue` returns a `TaskHandle` that provides control over the task:

```swift
let handle = try queue.enqueue(priority: .medium) {
    try await performWork()
}

// Await the result
let result = try await handle.value

// Cancel a task (removes from pending, or cooperatively cancels if running)
await handle.cancel()

// Update priority while pending (triggers re-evaluation)
await handle.updatePriority(.high)
```

## Re-evaluating Pending Tasks

When external conditions change (e.g., capacity values are updated), call `drain()` to trigger a re-evaluation of pending tasks:

```swift
await queue.drain()
```

This is useful with `LaneResolver` when capacity is determined dynamically.

## Backpressure

The queue enforces a configurable pending limit (default: 8192). When the limit is reached, `enqueue` throws `ResourceQueueError.pendingLimitExceeded`:

```swift
let queue = ResourceQueue(
    resolver: FixedResolver<Priority>(concurrency: 4),
    pendingLimit: 100
)

do {
    try queue.enqueue(priority: .low) { /* ... */ }
} catch ResourceQueueError.pendingLimitExceeded {
    // handle backpressure
}
```

## License

MIT
