package dev.continuousimprovement.core.model;

import dev.continuousimprovement.core.security.TextSanitizer;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

public record ReportDraft(
        UUID idempotencyKey,
        String reporterName,
        ReportCategory category,
        String comment,
        String expected,
        Instant consentedAt,
        String appVersion,
        String buildSha,
        EnvironmentInfo environment,
        List<ArtifactDescriptor> artifacts
) {
    public ReportDraft {
        Objects.requireNonNull(idempotencyKey, "idempotencyKey");
        Objects.requireNonNull(category, "category");
        Objects.requireNonNull(consentedAt, "consentedAt");
        Objects.requireNonNull(environment, "environment");
        reporterName = TextSanitizer.reporterName(reporterName);
        comment = TextSanitizer.requiredMultiline(comment, "comment", 4_000);
        expected = TextSanitizer.optionalMultiline(expected, 4_000);
        appVersion = TextSanitizer.requiredSingleLine(appVersion, "appVersion", 100);
        buildSha = TextSanitizer.optionalSingleLine(buildSha, 100);
        artifacts = artifacts == null ? List.of() : List.copyOf(artifacts);
        if (artifacts.size() > 4) throw new IllegalArgumentException("at most four artifacts are allowed");
    }
}
