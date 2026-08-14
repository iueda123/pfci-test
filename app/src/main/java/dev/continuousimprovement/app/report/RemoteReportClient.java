package dev.continuousimprovement.app.report;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import dev.continuousimprovement.core.JsonSupport;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Map;
import java.util.ArrayList;

public final class RemoteReportClient implements AutoCloseable {
    private final URI baseUri;
    private final String publishableKey;
    private final HttpClient client;

    public RemoteReportClient(URI baseUri, String publishableKey) {
        this.baseUri = baseUri;
        this.publishableKey = publishableKey;
        this.client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    }

    public SubmissionResult submit(Path bundleDirectory) throws IOException, InterruptedException {
        var draft = JsonSupport.MAPPER.readTree(bundleDirectory.resolve("report.json").toFile());
        var manifest = JsonSupport.MAPPER.readTree(bundleDirectory.resolve("manifest.json").toFile());
        var artifacts = new ArrayList<Map<String,Object>>();
        for (var artifact : manifest.path("artifacts")) {
            artifacts.add(Map.of("kind", wireKind(artifact.path("kind").asText()), "contentType", artifact.path("contentType").asText(),
                    "bytes", artifact.path("bytes").asLong(), "sha256", artifact.path("sha256").asText()));
        }
        byte[] manifestBytes=Files.readAllBytes(bundleDirectory.resolve("manifest.json"));
        artifacts.add(Map.of("kind","manifest","contentType","application/json","bytes",manifestBytes.length,
                "sha256",dev.continuousimprovement.core.io.Hashing.sha256(manifestBytes)));
        var payload=new java.util.LinkedHashMap<String,Object>();
        payload.put("idempotencyKey",draft.path("idempotencyKey").asText());payload.put("reporterName",draft.path("reporterName").isNull()?null:draft.path("reporterName").asText());
        payload.put("category",draft.path("category").asText().toLowerCase());payload.put("comment",draft.path("comment").asText());payload.put("expected",draft.path("expected").isNull()?null:draft.path("expected").asText());payload.put("consentedAt",draft.path("consentedAt").asText());
        payload.put("app",Map.of("version",draft.path("appVersion").asText(),"buildSha",draft.path("buildSha").asText()));payload.put("environment",JsonSupport.MAPPER.convertValue(draft.path("environment"),Map.class));payload.put("artifacts",artifacts);
        byte[] report = JsonSupport.MAPPER.writeValueAsBytes(payload);
        var create = request("create-report", HttpRequest.BodyPublishers.ofByteArray(report), "application/json");
        var createResponse = sendWithRetry(create);
        requireSuccess(createResponse, "create-report");
        var created = JsonSupport.MAPPER.readValue(createResponse.body(), CreateResponse.class);

        for (var upload : created.uploads()) {
            if (upload.localPath() == null || upload.localPath().isBlank()) {
                throw new IOException("create-report returned an invalid upload path");
            }
            var localFile = bundleDirectory.resolve(upload.localPath()).normalize();
            if (!localFile.startsWith(bundleDirectory.normalize())) throw new IOException("unsafe upload path");
            var uploadRequest = HttpRequest.newBuilder(URI.create(upload.url()))
                    .timeout(Duration.ofSeconds(30))
                    .header("Content-Type", upload.contentType())
                    .header("x-upsert", "false")
                    .PUT(HttpRequest.BodyPublishers.ofFile(localFile))
                    .build();
            var uploaded=sendWithRetry(uploadRequest);if(uploaded.statusCode()!=409)requireSuccess(uploaded, "artifact upload");
        }

        byte[] finalizeBody = JsonSupport.MAPPER.writeValueAsBytes(Map.of("reportId", created.reportId()));
        var finalizeResponse = sendWithRetry(
                request("finalize-report", HttpRequest.BodyPublishers.ofByteArray(finalizeBody), "application/json"),
                3);
        requireSuccess(finalizeResponse, "finalize-report");
        return JsonSupport.MAPPER.readValue(finalizeResponse.body(), SubmissionResult.class);
    }

    private HttpResponse<String> sendWithRetry(HttpRequest request) throws IOException, InterruptedException { return sendWithRetry(request,3); }
    private HttpResponse<String> sendWithRetry(HttpRequest request,int attempts) throws IOException, InterruptedException {
        for(int i=0;i<attempts;i++){
            try {
                var response=client.send(request,HttpResponse.BodyHandlers.ofString());
                if(response.statusCode()<500 || i+1==attempts)return response;
            } catch(IOException exception) {
                if(i+1==attempts)throw exception;
            }
            Thread.sleep(100L*(1L<<i));
        }
        throw new IOException("request failed without a response");
    }

    private String wireKind(String value) { return switch(value){case "RAW_SCREENSHOT"->"rawScreenshot";case "RAW_LOG"->"rawLog";case "REDACTED_SCREENSHOT"->"redactedScreenshot";case "REDACTED_LOG"->"redactedLog";default->throw new IllegalArgumentException("unknown artifact kind");}; }

    private HttpRequest request(String function, HttpRequest.BodyPublisher body, String contentType) {
        return HttpRequest.newBuilder(baseUri.resolve("/functions/v1/" + function))
                .timeout(Duration.ofSeconds(30))
                .header("Content-Type", contentType)
                .header("apikey", publishableKey)
                .POST(body)
                .build();
    }

    private void requireSuccess(HttpResponse<?> response, String operation) throws IOException {
        if (response.statusCode() / 100 != 2) {
            String code = response.body() instanceof String body ? responseErrorCode(body) : null;
            throw new IOException(operation + " failed with HTTP " + response.statusCode()
                    + (code == null ? "" : " (" + code + ")"));
        }
    }

    private String responseErrorCode(String body) {
        try {
            String code = JsonSupport.MAPPER.readTree(body).path("error").path("code").asText();
            return code.matches("[a-z0-9_]{1,80}") ? code : null;
        } catch (Exception ignored) {
            return null;
        }
    }

    @Override
    public void close() {
        client.close();
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record Upload(String localPath, String url, String contentType) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record CreateResponse(String reportId, java.util.List<Upload> uploads) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record SubmissionResult(String reportId, String status, String issueUrl) {
    }
}
