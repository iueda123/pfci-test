package dev.continuousimprovement.core.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class LogRedactorTest {
    private final LogRedactor redactor = new LogRedactor();

    @Test
    void removesKnownSensitiveValues() {
        var input = "email=alice@example.com Authorization: Bearer abc123 password=hunter2 path=/home/alice/work";
        var result = redactor.redact(input);

        assertFalse(result.value().contains("alice@example.com"));
        assertFalse(result.value().contains("abc123"));
        assertFalse(result.value().contains("hunter2"));
        assertFalse(result.value().contains("/home/alice"));
        assertTrue(result.replacementCount() >= 4);
    }

    @Test
    void removesSessionConnectionStringAndStandaloneToken() {
        var value = new LogRedactor().redact("session_id=abc123 postgresql://demo:fake@db.invalid/x ghp_abcdefghijklmnopqrstuvwxyz123456").value();
        assertFalse(value.contains("abc123"));assertFalse(value.contains("demo:fake"));assertFalse(value.contains("ghp_"));
    }

    @Test
    void normalizesNewlinesToPreventLogInjection() {
        assertEquals("first second", redactor.redact("first\r\nsecond").value());
    }
}
