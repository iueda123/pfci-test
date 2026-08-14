package dev.continuousimprovement.core.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertThrows;

class ArtifactDescriptorTest {
    @Test
    void rejectsPathTraversal() {
        assertThrows(IllegalArgumentException.class, () -> new ArtifactDescriptor(
                ArtifactKind.RAW_LOG, "application/x-ndjson", 1, "a".repeat(64), "../secret"
        ));
    }
}
