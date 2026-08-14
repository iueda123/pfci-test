package dev.continuousimprovement.core.log;

import dev.continuousimprovement.core.model.LogEvent;
import dev.continuousimprovement.core.security.LogRedactor;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;

import static org.junit.jupiter.api.Assertions.*;

class RingBufferLogCollectorTest {
    @Test
    void keepsCapacityAndTimeWindow() {
        var now = Instant.parse("2026-08-11T00:00:00Z");
        var collector = new RingBufferLogCollector(2);
        collector.append(event(now.minusSeconds(600), "old"));
        collector.append(event(now.minusSeconds(30), "password=secret"));
        collector.append(event(now, "latest"));

        var output = collector.toRedactedJsonLines(Duration.ofMinutes(5), now, new LogRedactor());
        assertFalse(output.contains("old"));
        assertFalse(output.contains("password=secret"));
        assertTrue(output.contains("[REDACTED:SECRET]"));
        assertTrue(output.contains("latest"));
    }

    private LogEvent event(Instant timestamp, String message) {
        return new LogEvent(timestamp, "INFO", "test", "main", message, null, null);
    }
}
