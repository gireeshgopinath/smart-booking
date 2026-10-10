package dev.booking.baseline;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.InputStream;
import org.junit.jupiter.api.Test;

class ToolchainBaselineTest {

    @Test
    void runtimeMatchesPinnedJavaVersion() {
        String pinned = System.getProperty("baseline.javaVersion");
        assertNotNull(pinned, "surefire did not publish the pinned baseline.javaVersion property");
        int expected = Integer.parseInt(pinned);
        assertEquals(expected, Runtime.version().feature(), "the JVM executing tests is not the pinned JDK feature");
    }

    @Test
    void compiledBytecodeTargetsTheRunningJdk() throws Exception {
        int expected = Runtime.version().feature() + 44;
        try (InputStream classBytes = ToolchainBaselineTest.class.getResourceAsStream("ToolchainBaselineTest.class")) {
            assertNotNull(classBytes, "compiled baseline test class is missing from the test classpath");
            byte[] header = classBytes.readNBytes(8);
            assertEquals(8, header.length, "class file header is truncated");
            int major = ((header[6] & 0xFF) << 8) | (header[7] & 0xFF);
            assertTrue(
                    major == expected,
                    "bytecode target " + major + " does not match running JDK feature target " + expected);
        }
    }
}
