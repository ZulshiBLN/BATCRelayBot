# ADR-004: Task-Based Polling vs Event-Driven Architecture

**Date:** 2026-08-30  
**Status:** ACCEPTED  
**Author:** Claude (Project AI)

## Context

The Discord bot must maintain connection, detect reconnection needs, and gracefully handle shutdown signals. Two architecture patterns are available:

1. **Task-Based Polling** - Background tasks that periodically check state (every 10s, every 1s)
2. **Event-Driven** - Respond to Discord connection events, shutdown signals via OS signals

Additional constraints:
- Must run as background process (no interactive terminal)
- Must detect shutdown signal file (`stop.signal`) created by PowerShell
- Must recover from connection drops
- Must support graceful shutdown

## Decision

We chose **Task-Based Polling** with background tasks.

## Rationale

### Why Task-Based Polling?

1. **Simplicity** - Background tasks are easier to understand and debug than event chains
2. **Signal file detection** - Polling for `stop.signal` file is simpler than OS signals (which require terminal)
3. **Connection recovery** - Periodic checks allow automatic reconnection without waiting for events
4. **Stateless design** - No need to track event listeners or subscriptions
5. **Debugging** - Easier to log what's happening ("checking every 10 seconds...")
6. **No signal handling** - Avoids complexity of OS signal handling in async context
7. **Cross-platform-friendly** - Polling doesn't rely on Unix signals (which don't work well on Windows)

### Why NOT event-driven?

- **Signal file complexity** - No native Windows event for file creation
- **Event listener overhead** - Would need FileSystemWatcher (adds dependencies)
- **Shutdown complexity** - OS signals don't work well with async Python on Windows
- **Race conditions** - Event-driven can miss signals in timing windows
- **Debugging difficulty** - Event chains harder to trace

## Consequences

### Positive
- **Simple implementation** - Straightforward task loops
- **Reliable shutdown detection** - Polling ensures we check within 1 second
- **Easy recovery** - Periodic connections attempt recovery automatically
- **Low coupling** - Tasks are independent of each other
- **Testable** - No event subscription/unsubscription to mock
- **Predictable behavior** - Happens on a schedule, not random events
- **Resilient** - Single event miss doesn't affect operation

### Negative
- **Resource usage** - Background tasks always running (even when idle)
- **Latency** - Up to 10 seconds to detect connection drop and retry
- **Not event-reactive** - Doesn't respond immediately to Discord events
- **Polling overhead** - Continuous checks (minor CPU usage)

## Related Decisions

- ADR-005: Shutdown mechanism uses file-based signal (supports polling)

## Architecture Details

### Task Loops

```python
@tasks.loop(seconds=10)
async def watchdog():
    """Check connection every 10s, reconnect if needed"""
    try:
        await connect_and_stream()
    except Exception:
        log.exception("Error in watchdog cycle")

@tasks.loop(seconds=1)
async def shutdown_watcher():
    """Check for stop.signal file every 1s"""
    if not STOP_SIGNAL_PATH.exists():
        return
    
    # Graceful shutdown
    await bot.close()
```

### Polling Intervals

- **Watchdog (connection check):** 10 seconds
  - Rationale: Long enough to avoid excessive reconnects, short enough for quick recovery
  - Trade-off: Up to 10s latency for detecting disconnects

- **Shutdown watcher (signal check):** 1 second
  - Rationale: Responsive shutdown, still minimal resource impact
  - Trade-off: Up to 1s latency for processing shutdown signal

### Shutdown Signal File

Rather than OS signals, we use file-based signaling:

```powershell
# From Stop-BATCRelayBot.ps1
New-Item -Path $stopSignalFile -ItemType File -Force | Out-Null
```

Benefits:
- Works on Windows without special handling
- Works with background processes
- Visible and debuggable (file exists)
- PowerShell can create it easily
- Shutdown watcher polls for it

## Alternatives Considered

1. **Event-Driven with Discord API events** - Rejected for complexity, can't detect our own disconnects reliably
2. **OS Signals (SIGTERM)** - Rejected for poor Windows support
3. **Named Pipes** - Rejected for added complexity vs simple file-based signal
4. **Web API for control** - Rejected for added attack surface, not needed
5. **Pure event-driven** - Rejected for signal file complexity

## Implementation Notes

### Why discord.py Tasks?

```python
from discord.ext import tasks

@tasks.loop(seconds=10)
async def watchdog():
    ...
```

Discord.py's `@tasks.loop` decorator provides:
- Automatic task scheduling
- Proper async/await integration
- Easy start/stop management
- Built-in error handling with retry

### Testing Considerations

Task-based architecture makes testing harder:
- Need to mock task execution
- Async testing complexity
- Can't easily mock file system changes

This is why some async functions lack coverage (reflected in test coverage audit).

## Performance Implications

- **Watchdog:** 10s interval = 1 CPU wakeup per 10 seconds
- **Shutdown watcher:** 1s interval = 1 CPU wakeup per second
- **Impact:** Minimal (Discord.py async tasks are efficient)
- **Power usage:** Negligible (not blocking on CPU, just event loop notification)

## Future Alternatives

If requirements change:
1. Add Discord event listeners for real-time detection
2. Implement hybrid approach (task + event listeners)
3. Add health check endpoint for external monitoring
4. Support systemd integration for Linux (future cross-platform)

## Related Discord.py Concepts

- **discord.ext.tasks** - What we use for background tasks
- **@bot.event** - Event listeners (not used for main reconnect logic)
- **@bot.command** - Text commands (!status, !restart_stream, !leave)

## Conclusion

Task-based polling is simpler, more reliable, and better suited to our use case (background process with file-based shutdown signal) than event-driven architecture. The cost (up to 10s latency for reconnection) is acceptable given the benefits (simplicity, reliability, testability).
