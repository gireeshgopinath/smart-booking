package dev.booking.baseline;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Properties;
import org.junit.jupiter.api.Test;

class BaselineProbeTest {

    private static final String JACKSON_METADATA =
            "/META-INF/maven/com.fasterxml.jackson.core/jackson-databind/pom.properties";

    @Test
    void jsonRoundTripKeepsValues() throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        BaselineProbe probe = new BaselineProbe("api-contracts", "0.1.0");

        String json = mapper.writeValueAsString(probe);
        BaselineProbe parsed = mapper.readValue(json, BaselineProbe.class);

        assertEquals(probe, parsed);
    }

    @Test
    void blankComponentIsRejected() {
        assertThrows(IllegalArgumentException.class, () -> new BaselineProbe(" ", "0.1.0"));
        assertThrows(IllegalArgumentException.class, () -> new BaselineProbe("api-contracts", null));
    }

    @Test
    void compiledBytecodeTargetsTheRunningJdk() throws Exception {
        int expected = Runtime.version().feature() + 44;
        try (InputStream classBytes = BaselineProbe.class.getResourceAsStream("BaselineProbe.class")) {
            assertNotNull(classBytes, "compiled baseline class is missing from the test classpath");
            byte[] header = classBytes.readNBytes(8);
            assertEquals(8, header.length, "class file header is truncated");
            int major = ((header[6] & 0xFF) << 8) | (header[7] & 0xFF);
            assertTrue(
                    major == expected,
                    "bytecode target " + major + " does not match running JDK feature target " + expected);
        }
    }

    @Test
    void resolvedJacksonMatchesManifestPin() throws Exception {
        String pinned = System.getProperty("baseline.jacksonVersion");
        assertNotNull(pinned, "surefire did not publish the pinned baseline.jacksonVersion property");

        Properties properties = new Properties();
        try (InputStream metadata = BaselineProbeTest.class.getResourceAsStream(JACKSON_METADATA)) {
            assertNotNull(metadata, "resolved jackson-databind jar is missing its Maven pom.properties");
            properties.load(new InputStreamReader(metadata, StandardCharsets.UTF_8));
        }
        String resolved = properties.getProperty("version");
        assertEquals(pinned, resolved, "the resolved jackson-databind version drifted from the recorded manifest pin");
    }
}
