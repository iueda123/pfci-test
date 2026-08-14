package dev.continuousimprovement.app.capture;

import java.util.List;

public record ScreenshotBundle(byte[] rawPng, byte[] redactedPng, List<MaskRegion> automaticMasks) {
    public ScreenshotBundle {
        rawPng = rawPng.clone();
        redactedPng = redactedPng.clone();
        automaticMasks = List.copyOf(automaticMasks);
    }
}
