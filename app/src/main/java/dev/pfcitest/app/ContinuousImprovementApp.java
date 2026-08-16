package dev.pfcitest.app;

import dev.continuousimprovement.reporting.capture.ScreenshotService;
import dev.continuousimprovement.reporting.capture.ScreenMaskPolicy;
import dev.continuousimprovement.reporting.report.LocalReportBundleWriter;
import dev.continuousimprovement.reporting.report.ReportBundleRequest;
import dev.continuousimprovement.reporting.report.RemoteReportClient;
import dev.continuousimprovement.reporting.ui.MaskPreviewPane;
import dev.continuousimprovement.core.log.RingBufferLogCollector;
import dev.continuousimprovement.core.model.EnvironmentInfo;
import dev.continuousimprovement.core.model.LogEvent;
import dev.continuousimprovement.core.model.ReportCategory;
import dev.continuousimprovement.core.security.LogRedactor;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.scene.Node;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.GridPane;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;
import javafx.stage.Modality;
import javafx.stage.Stage;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.net.URI;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Executors;

public final class ContinuousImprovementApp extends Application {
    private final RingBufferLogCollector logs = new RingBufferLogCollector(500);
    private final ScreenshotService screenshotService = new ScreenshotService();
    private final LogRedactor logRedactor = new LogRedactor();
    private final java.util.concurrent.ExecutorService background = Executors.newSingleThreadExecutor();
    private VBox root;
    private TextField customerName;
    private TextField customerEmail;

    @Override
    public void start(Stage stage) {
        customerName = new TextField("山田 花子");
        customerEmail = new TextField("hanako@example.invalid");
        var project = new TextArea("改善対象の機能について入力してください。");
        var save = new Button("保存");
        save.setOnAction(event -> appendLog("INFO", "Saved draft for hanako@example.invalid sessionId=abc-123"));

        var form = new GridPane();
        form.setHgap(8);
        form.setVgap(8);
        form.addRow(0, new Label("顧客名"), customerName);
        form.addRow(1, new Label("メール"), customerEmail);
        form.addRow(2, new Label("内容"), project);
        form.add(save, 1, 3);

        var report = new Button("気になった点を報告");
        report.setOnAction(event -> openReportDialog(stage));
        root = new VBox(16, new Label("継続的改善デモ"), form, report);
        root.setPadding(new Insets(24));
        VBox.setVgrow(form, Priority.ALWAYS);

        stage.setTitle("Continuous Improvement Demo");
        stage.setScene(new Scene(root, 860, 580));
        stage.show();
        appendLog("INFO", "Application started");
        if ("true".equalsIgnoreCase(System.getenv("APP_SMOKE_TEST"))) {
            Platform.runLater(() -> {
                var capture = screenshotService.capture(root, new ScreenMaskPolicy("pfci-test/main", List.of(customerName, customerEmail)));
                if (capture.rawPng().length == 0 || capture.redactedPng().length == 0) throw new IllegalStateException("empty capture");
                System.out.println("SMOKE_CAPTURE_OK raw=" + capture.rawPng().length + " redacted=" + capture.redactedPng().length);
                Platform.exit();
            });
        }
    }

    private void openReportDialog(Stage owner) {
        appendLog("INFO", "Report dialog requested");
        var screenshot = screenshotService.capture(root, new ScreenMaskPolicy("pfci-test/main", List.of(customerName, customerEmail)));
        var preview = new MaskPreviewPane(screenshot.redactedPng());

        var reporter = new TextField();
        reporter.setPromptText("任意（未入力なら匿名）");
        var category = new ComboBox<ReportCategory>();
        category.getItems().setAll(ReportCategory.values());
        category.setValue(ReportCategory.BUG);
        var comment = new TextArea();
        comment.setPromptText("何をしようとして、何が起きたか");
        var expected = new TextArea();
        expected.setPromptText("本来どうなってほしいか");
        var includeScreenshot = new CheckBox("スクリーンショットを含める");
        includeScreenshot.setSelected(true);
        var includeLogs = new CheckBox("直前5分のログを含める");
        includeLogs.setSelected(true);
        var consent = new CheckBox("previewを確認し、送信に同意する");
        var clearMasks = new Button("追加の黒塗りを消す");
        clearMasks.setOnAction(event -> preview.clearManualMasks());
        var send = new Button("ローカルbundleを作成");
        var cancel = new Button("キャンセル");
        var status = new Label("画像上をドラッグすると追加の黒塗りができます。");

        var content = new VBox(8,
                new Label("ユーザー名"), reporter,
                new Label("種別"), category,
                new Label("状況"), comment,
                new Label("期待結果"), expected,
                includeScreenshot, includeLogs,
                new Label("マスク済みpreview"), preview, clearMasks,
                consent, new ToolBar(send, cancel), status
        );
        content.setPadding(new Insets(16));
        var scroll = new ScrollPane(content);
        scroll.setFitToWidth(true);

        var dialog = new Stage();
        dialog.initOwner(owner);
        dialog.initModality(Modality.WINDOW_MODAL);
        dialog.setTitle("フィードバックを送る");
        dialog.setScene(new Scene(scroll, 800, 760));
        cancel.setOnAction(event -> dialog.close());
        send.setOnAction(event -> {
            if (comment.getText().isBlank() || !consent.isSelected()) {
                status.setText("状況の入力と送信同意が必要です。");
                return;
            }
            send.setDisable(true);
            status.setText("bundleを作成しています…");
            byte[] redactedScreenshot = screenshotService.addMasks(screenshot.redactedPng(), preview.manualMasks());
            String rawLogs = logs.toJsonLines(Duration.ofMinutes(5), Instant.now());
            String redactedLogs = logs.toRedactedJsonLines(Duration.ofMinutes(5), Instant.now(), logRedactor);
            var request = new ReportBundleRequest(
                    UUID.randomUUID(), reporter.getText(), category.getValue(), comment.getText(), expected.getText(),
                    Instant.now(), "0.1.0-SNAPSHOT", "local-dev", EnvironmentInfo.current("pfci-test/main"),
                    includeScreenshot.isSelected() ? screenshot.rawPng() : null,
                    includeScreenshot.isSelected() ? redactedScreenshot : null,
                    includeLogs.isSelected() ? rawLogs.getBytes(StandardCharsets.UTF_8) : null,
                    includeLogs.isSelected() ? redactedLogs.getBytes(StandardCharsets.UTF_8) : null,
                    true
            );
            background.submit(() -> {
                try {
                    var rootPath = Path.of(System.getenv().getOrDefault("REPORT_OUTPUT_DIR", "local-reports"));
                    var written = new LocalReportBundleWriter().write(rootPath, request);
                    String completed = "作成しました: " + written.toAbsolutePath();
                    String remoteUrl=System.getenv("REPORT_API_URL"),publishable=System.getenv("SUPABASE_PUBLISHABLE_KEY");
                    if(remoteUrl!=null&&!remoteUrl.isBlank()&&publishable!=null&&!publishable.isBlank()){
                        try(var remote=new RemoteReportClient(URI.create(remoteUrl),publishable)){var submitted=remote.submit(written);completed="送信しました: "+submitted.issueUrl();}
                    }
                    String message=completed;
                    Platform.runLater(() -> {
                        status.setText(message);
                        send.setDisable(false);
                    });
                } catch (Exception exception) {
                    Platform.runLater(() -> {
                        status.setText("失敗: " + exception.getMessage());
                        send.setDisable(false);
                    });
                }
            });
        });
        dialog.show();
    }

    private void appendLog(String level, String message) {
        logs.append(new LogEvent(Instant.now(), level, getClass().getName(), Thread.currentThread().getName(), message, null, UUID.randomUUID().toString()));
    }

    @Override
    public void stop() {
        background.shutdownNow();
    }

    public static void main(String[] args) {
        launch(args);
    }
}
