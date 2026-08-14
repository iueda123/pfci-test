package dev.continuousimprovement.app.report;

import dev.continuousimprovement.core.model.EnvironmentInfo;
import dev.continuousimprovement.core.model.ReportCategory;

import java.time.Instant;
import java.util.UUID;

public record ReportBundleRequest(
        UUID reportId,
        String reporterName,
        ReportCategory category,
        String comment,
        String expected,
        Instant consentedAt,
        String appVersion,
        String buildSha,
        EnvironmentInfo environment,
        byte[] rawScreenshot,
        byte[] redactedScreenshot,
        byte[] rawLog,
        byte[] redactedLog,
        boolean redactionApproved
) {
}
