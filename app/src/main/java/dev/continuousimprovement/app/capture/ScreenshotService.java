package dev.continuousimprovement.app.capture;

import javafx.embed.swing.SwingFXUtils;
import javafx.geometry.Bounds;
import javafx.scene.Node;
import javafx.scene.SnapshotParameters;
import javafx.scene.image.WritableImage;

import javax.imageio.ImageIO;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

public final class ScreenshotService {
    public ScreenshotBundle capture(Node root, List<Node> sensitiveNodes) {
        return capture(root,new ScreenMaskPolicy("legacy",sensitiveNodes));
    }

    public ScreenshotBundle capture(Node root, ScreenMaskPolicy policy) {
        if (!javafx.application.Platform.isFxApplicationThread()) {
            throw new IllegalStateException("capture must run on the JavaFX Application Thread");
        }
        var snapshot = root.snapshot(new SnapshotParameters(), null);
        var raw = SwingFXUtils.fromFXImage(snapshot, null);
        var masks = automaticMasks(root, policy.sensitiveNodes(), raw.getWidth(), raw.getHeight());
        return new ScreenshotBundle(toPng(raw), toPng(applyMasks(raw, masks)), masks);
    }

    public byte[] addMasks(byte[] png, List<MaskRegion> masks) {
        try {
            var image = ImageIO.read(new ByteArrayInputStream(png));
            if (image == null) throw new IllegalArgumentException("invalid PNG");
            return toPng(applyMasks(image, masks));
        } catch (IOException e) {
            throw new IllegalStateException("failed to read screenshot", e);
        }
    }

    static BufferedImage applyMasks(BufferedImage source, List<MaskRegion> masks) {
        var copy = new BufferedImage(source.getWidth(), source.getHeight(), BufferedImage.TYPE_INT_ARGB);
        Graphics2D graphics = copy.createGraphics();
        try {
            graphics.drawImage(source, 0, 0, null);
            graphics.setColor(Color.BLACK);
            for (var mask : masks) {
                int x = clamp((int) Math.floor(mask.x()), 0, source.getWidth());
                int y = clamp((int) Math.floor(mask.y()), 0, source.getHeight());
                int maxWidth = source.getWidth() - x;
                int maxHeight = source.getHeight() - y;
                int width = clamp((int) Math.ceil(mask.width()), 0, maxWidth);
                int height = clamp((int) Math.ceil(mask.height()), 0, maxHeight);
                graphics.fillRect(x, y, width, height);
            }
        } finally {
            graphics.dispose();
        }
        return copy;
    }

    private List<MaskRegion> automaticMasks(Node root, List<Node> nodes, int imageWidth, int imageHeight) {
        Bounds rootBounds = root.localToScene(root.getBoundsInLocal());
        double scaleX = imageWidth / rootBounds.getWidth();
        double scaleY = imageHeight / rootBounds.getHeight();
        List<MaskRegion> result = new ArrayList<>();
        for (var node : nodes) {
            if (!node.isVisible() || node.getScene() != root.getScene()) throw new IllegalStateException("sensitive node is not capturable");
            Bounds bounds = node.localToScene(node.getBoundsInLocal());
            double x = Math.max(0, (bounds.getMinX() - rootBounds.getMinX()) * scaleX);
            double y = Math.max(0, (bounds.getMinY() - rootBounds.getMinY()) * scaleY);
            double width = Math.min(imageWidth - x, bounds.getWidth() * scaleX);
            double height = Math.min(imageHeight - y, bounds.getHeight() * scaleY);
            if (width > 0 && height > 0) result.add(new MaskRegion(x, y, width, height));
        }
        return result;
    }

    private byte[] toPng(BufferedImage image) {
        try {
            var output = new ByteArrayOutputStream();
            if (!ImageIO.write(image, "png", output)) throw new IllegalStateException("PNG writer is unavailable");
            return output.toByteArray();
        } catch (IOException e) {
            throw new IllegalStateException("failed to encode screenshot", e);
        }
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(value, max));
    }
}
