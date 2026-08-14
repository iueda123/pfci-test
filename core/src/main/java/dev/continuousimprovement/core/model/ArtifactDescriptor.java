package dev.continuousimprovement.core.model;

public record ArtifactDescriptor(
        ArtifactKind kind,
        String contentType,
        long bytes,
        String sha256,
        String path
) {
    public ArtifactDescriptor {
        if (kind == null) throw new IllegalArgumentException("kind is required");
        if (contentType == null || contentType.isBlank()) throw new IllegalArgumentException("contentType is required");
        if (bytes < 0) throw new IllegalArgumentException("bytes must be non-negative");
        if (sha256 == null || !sha256.matches("[0-9a-f]{64}")) {
            throw new IllegalArgumentException("sha256 must be lowercase hex");
        }
        if (path == null || path.isBlank() || path.startsWith("/") || path.contains("..")) {
            throw new IllegalArgumentException("unsafe artifact path");
        }
    }
}
