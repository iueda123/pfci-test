package dev.continuousimprovement.app.ui;

import dev.continuousimprovement.app.capture.MaskRegion;
import javafx.geometry.Pos;
import javafx.scene.canvas.Canvas;
import javafx.scene.image.Image;
import javafx.scene.image.ImageView;
import javafx.scene.layout.StackPane;
import javafx.scene.paint.Color;

import java.io.ByteArrayInputStream;
import java.util.ArrayList;
import java.util.List;

public final class MaskPreviewPane extends StackPane {
    private final Image image;
    private final ImageView imageView;
    private final Canvas overlay;
    private final List<MaskRegion> manualMasks = new ArrayList<>();
    private double startX;
    private double startY;

    public MaskPreviewPane(byte[] redactedPng) {
        this.image = new Image(new ByteArrayInputStream(redactedPng));
        this.imageView = new ImageView(image);
        this.imageView.setPreserveRatio(true);
        this.imageView.setFitWidth(Math.min(720, image.getWidth()));
        this.overlay = new Canvas(imageView.getFitWidth(), displayedHeight());
        setAlignment(Pos.TOP_LEFT);
        getChildren().addAll(imageView, overlay);

        overlay.setOnMousePressed(event -> {
            startX = bounded(event.getX(), overlay.getWidth());
            startY = bounded(event.getY(), overlay.getHeight());
        });
        overlay.setOnMouseReleased(event -> {
            double endX = bounded(event.getX(), overlay.getWidth());
            double endY = bounded(event.getY(), overlay.getHeight());
            double x = Math.min(startX, endX);
            double y = Math.min(startY, endY);
            double width = Math.abs(endX - startX);
            double height = Math.abs(endY - startY);
            if (width >= 3 && height >= 3) {
                manualMasks.add(toImageRegion(x, y, width, height));
                redraw();
            }
        });
    }

    public List<MaskRegion> manualMasks() {
        return List.copyOf(manualMasks);
    }

    public void clearManualMasks() {
        manualMasks.clear();
        redraw();
    }

    private MaskRegion toImageRegion(double x, double y, double width, double height) {
        double scaleX = image.getWidth() / overlay.getWidth();
        double scaleY = image.getHeight() / overlay.getHeight();
        return new MaskRegion(x * scaleX, y * scaleY, width * scaleX, height * scaleY);
    }

    private void redraw() {
        var graphics = overlay.getGraphicsContext2D();
        graphics.clearRect(0, 0, overlay.getWidth(), overlay.getHeight());
        graphics.setFill(Color.rgb(0, 0, 0, 0.88));
        double scaleX = overlay.getWidth() / image.getWidth();
        double scaleY = overlay.getHeight() / image.getHeight();
        for (var mask : manualMasks) {
            graphics.fillRect(mask.x() * scaleX, mask.y() * scaleY, mask.width() * scaleX, mask.height() * scaleY);
        }
    }

    private double displayedHeight() {
        return image.getHeight() * imageView.getFitWidth() / image.getWidth();
    }

    private double bounded(double value, double maximum) {
        return Math.max(0, Math.min(value, maximum));
    }
}
