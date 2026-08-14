package dev.continuousimprovement.app.capture;

public record MaskRegion(double x, double y, double width, double height) {
    public MaskRegion {
        if (x < 0 || y < 0 || width <= 0 || height <= 0) {
            throw new IllegalArgumentException("invalid mask region");
        }
    }
}
