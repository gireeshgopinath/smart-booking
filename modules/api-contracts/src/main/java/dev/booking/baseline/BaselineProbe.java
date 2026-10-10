package dev.booking.baseline;

/**
 * Build-only baseline artifact. T01 uses it to prove that shared compilation,
 * managed dependency resolution and test execution work on the pinned toolchain.
 * It carries no booking domain behaviour.
 */
public record BaselineProbe(String component, String version) {

    public BaselineProbe {
        requireText(component, "component");
        requireText(version, "version");
    }

    private static void requireText(String value, String field) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(field + " must not be blank");
        }
    }
}
