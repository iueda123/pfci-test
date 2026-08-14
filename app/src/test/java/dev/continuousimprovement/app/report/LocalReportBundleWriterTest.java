package dev.continuousimprovement.app.report;

import dev.continuousimprovement.core.JsonSupport;
import dev.continuousimprovement.core.io.ArtifactManifest;
import dev.continuousimprovement.core.model.EnvironmentInfo;
import dev.continuousimprovement.core.model.ReportCategory;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.UUID;
import java.nio.file.attribute.PosixFilePermission;

import static org.junit.jupiter.api.Assertions.*;

class LocalReportBundleWriterTest {
    @TempDir Path temporaryDirectory;

    @Test
    void writesSeparatedRawAndRedactedArtifacts() throws Exception {
        var id = UUID.randomUUID();
        var request = new ReportBundleRequest(
                id, "tester", ReportCategory.BUG, "broken", "fixed", Instant.now(), "1", "abc",
                new EnvironmentInfo("Ubuntu", "24.04", "amd64", "25", "25", "ja-JP", "main", "wayland"),
                "raw-image".getBytes(StandardCharsets.UTF_8), "safe-image".getBytes(StandardCharsets.UTF_8),
                "password=raw".getBytes(StandardCharsets.UTF_8), "password=[REDACTED:SECRET]".getBytes(StandardCharsets.UTF_8), true
        );

        var result = new LocalReportBundleWriter().write(temporaryDirectory, request);
        assertTrue(Files.exists(result.resolve("raw/logs.jsonl")));
        assertTrue(Files.exists(result.resolve("redacted/logs.jsonl")));
        var manifest = JsonSupport.MAPPER.readValue(result.resolve("manifest.json").toFile(), ArtifactManifest.class);
        assertEquals(ArtifactManifest.RedactionStatus.APPROVED, manifest.redactionStatus());
        assertEquals(4, manifest.artifacts().size());
        if (Files.getFileStore(result).supportsFileAttributeView("posix")) {
            assertFalse(Files.getPosixFilePermissions(result.resolve("raw/logs.jsonl")).contains(PosixFilePermission.OTHERS_READ));
        }
    }
}
