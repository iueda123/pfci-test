package dev.continuousimprovement.app.report;

import dev.continuousimprovement.core.JsonSupport;
import dev.continuousimprovement.core.io.ArtifactManifest;
import dev.continuousimprovement.core.io.Hashing;
import dev.continuousimprovement.core.model.ArtifactDescriptor;
import dev.continuousimprovement.core.model.ArtifactKind;
import dev.continuousimprovement.core.model.ReportDraft;
import dev.continuousimprovement.core.security.LogRedactor;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.nio.file.attribute.PosixFilePermissions;

public final class LocalReportBundleWriter {
    public Path write(Path outputRoot, ReportBundleRequest request) throws IOException {
        var reportDirectory = outputRoot.resolve(request.reportId().toString()).normalize();
        if (!reportDirectory.startsWith(outputRoot.normalize())) throw new IOException("unsafe report directory");
        var raw = reportDirectory.resolve("raw");
        var redacted = reportDirectory.resolve("redacted");
        Files.createDirectories(raw);
        Files.createDirectories(redacted);
        ownerOnly(reportDirectory, true); ownerOnly(raw, true); ownerOnly(redacted, true);

        List<ArtifactDescriptor> artifacts = new ArrayList<>();
        writeIfPresent(raw.resolve("screenshot.png"), request.rawScreenshot(), ArtifactKind.RAW_SCREENSHOT,
                "image/png", request.reportId(), artifacts);
        writeIfPresent(raw.resolve("logs.jsonl"), request.rawLog(), ArtifactKind.RAW_LOG,
                "application/x-ndjson", request.reportId(), artifacts);
        writeIfPresent(redacted.resolve("screenshot.png"), request.redactedScreenshot(), ArtifactKind.REDACTED_SCREENSHOT,
                "image/png", request.reportId(), artifacts);
        writeIfPresent(redacted.resolve("logs.jsonl"), request.redactedLog(), ArtifactKind.REDACTED_LOG,
                "application/x-ndjson", request.reportId(), artifacts);

        var draft = new ReportDraft(
                request.reportId(), request.reporterName(), request.category(), request.comment(), request.expected(),
                request.consentedAt(), request.appVersion(), request.buildSha(), request.environment(), artifacts
        );
        var manifest = new ArtifactManifest(
                request.reportId(), Instant.now(), LogRedactor.RULE_VERSION,
                request.redactionApproved() ? ArtifactManifest.RedactionStatus.APPROVED : ArtifactManifest.RedactionStatus.REVIEW_REQUIRED,
                artifacts
        );
        JsonSupport.MAPPER.writerWithDefaultPrettyPrinter().writeValue(reportDirectory.resolve("report.json").toFile(), draft);
        JsonSupport.MAPPER.writerWithDefaultPrettyPrinter().writeValue(reportDirectory.resolve("manifest.json").toFile(), manifest);
        ownerOnly(reportDirectory.resolve("report.json"), false); ownerOnly(reportDirectory.resolve("manifest.json"), false);
        return reportDirectory;
    }

    private void writeIfPresent(Path file, byte[] bytes, ArtifactKind kind, String contentType, java.util.UUID reportId,
                                List<ArtifactDescriptor> artifacts) throws IOException {
        if (bytes == null || bytes.length == 0) return;
        Files.write(file, bytes);
        ownerOnly(file, false);
        var relative = "reports/" + reportId + "/" + file.getParent().getFileName() + "/" + file.getFileName();
        artifacts.add(new ArtifactDescriptor(kind, contentType, bytes.length, Hashing.sha256(bytes), relative));
    }

    private void ownerOnly(Path path, boolean directory) throws IOException {
        try { Files.setPosixFilePermissions(path, PosixFilePermissions.fromString(directory ? "rwx------" : "rw-------")); }
        catch (UnsupportedOperationException ignored) { }
    }
}
