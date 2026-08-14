package dev.continuousimprovement.app.capture;

import org.junit.jupiter.api.Test;

import java.awt.Color;
import java.awt.image.BufferedImage;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ScreenshotServiceTest {
    @Test
    void appliesBlackMaskInsideImageBounds() {
        var source = new BufferedImage(10, 10, BufferedImage.TYPE_INT_ARGB);
        var graphics = source.createGraphics();
        graphics.setColor(Color.WHITE);
        graphics.fillRect(0, 0, 10, 10);
        graphics.dispose();

        var masked = ScreenshotService.applyMasks(source, List.of(new MaskRegion(2, 3, 4, 2)));
        assertEquals(Color.BLACK.getRGB(), masked.getRGB(2, 3));
        assertEquals(Color.WHITE.getRGB(), masked.getRGB(1, 1));
    }
}
