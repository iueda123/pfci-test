package dev.continuousimprovement.core.model;

import java.time.Instant;

public record LogEvent(
        Instant timestamp,
        String level,
        String logger,
        String thread,
        String message,
        String throwable,
        String correlationId
) {
    public LogEvent {
        if (timestamp == null) timestamp = Instant.now();
        level = valueOr(level, "INFO");
        logger = valueOr(logger, "application");
        thread = valueOr(thread, "unknown");
        message = valueOr(message, "");
    }

    private static String valueOr(String value, String fallback) {
        return value == null ? fallback : value;
    }
}
