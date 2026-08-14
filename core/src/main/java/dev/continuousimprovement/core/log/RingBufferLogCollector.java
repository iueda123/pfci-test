package dev.continuousimprovement.core.log;

import dev.continuousimprovement.core.JsonSupport;
import dev.continuousimprovement.core.model.LogEvent;
import dev.continuousimprovement.core.security.LogRedactor;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

public final class RingBufferLogCollector {
    private final int capacity;
    private final Deque<LogEvent> events;

    public RingBufferLogCollector(int capacity) {
        if (capacity <= 0 || capacity > 10_000) throw new IllegalArgumentException("invalid capacity");
        this.capacity = capacity;
        this.events = new ArrayDeque<>(capacity);
    }

    public synchronized void append(LogEvent event) {
        if (events.size() == capacity) events.removeFirst();
        events.addLast(event);
    }

    public synchronized List<LogEvent> recent(Duration duration, Instant now) {
        var threshold = now.minus(duration);
        return events.stream().filter(event -> !event.timestamp().isBefore(threshold)).toList();
    }

    public synchronized String toRedactedJsonLines(Duration duration, Instant now, LogRedactor redactor) {
        return toJsonLines(recent(duration, now).stream().map(redactor::redact).toList());
    }

    public synchronized String toJsonLines(Duration duration, Instant now) {
        return toJsonLines(recent(duration, now));
    }

    private String toJsonLines(List<LogEvent> source) {
        List<String> lines = new ArrayList<>();
        for (var event : source) {
            try {
                lines.add(JsonSupport.MAPPER.writeValueAsString(event));
            } catch (Exception e) {
                throw new IllegalStateException("failed to serialize log event", e);
            }
        }
        return String.join("\n", lines) + (lines.isEmpty() ? "" : "\n");
    }
}
