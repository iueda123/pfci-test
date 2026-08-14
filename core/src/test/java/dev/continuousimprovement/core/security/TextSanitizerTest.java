package dev.continuousimprovement.core.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class TextSanitizerTest {
    @Test
    void reporterNameCannotCreateGitHubMention() {
        assertEquals("octocat", TextSanitizer.reporterName(" @octocat\n"));
        assertNull(TextSanitizer.reporterName("@@"));
    }

    @Test
    void rejectsOversizedValues() {
        assertThrows(IllegalArgumentException.class, () -> TextSanitizer.reporterName("x".repeat(51)));
    }
}
