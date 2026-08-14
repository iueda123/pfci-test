package dev.continuousimprovement.core.io;

import dev.continuousimprovement.core.model.ArtifactDescriptor;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record ArtifactManifest(
        UUID reportId,
        Instant createdAt,
        String redactionVersion,
        RedactionStatus redactionStatus,
        List<ArtifactDescriptor> artifacts
) {
    public ArtifactManifest {
        if (reportId == null || createdAt == null) throw new IllegalArgumentException("reportId and createdAt are required");
        if (redactionVersion == null || redactionVersion.isBlank()) throw new IllegalArgumentException("redactionVersion is required");
        if (redactionStatus == null) throw new IllegalArgumentException("redactionStatus is required");
        artifacts = List.copyOf(artifacts);
    }

    public enum RedactionStatus { APPROVED, REVIEW_REQUIRED, REJECTED }
}
