package dev.continuousimprovement.dispatcher;
import org.junit.jupiter.api.*;import org.junit.jupiter.api.io.TempDir;import java.nio.file.*;import java.time.Duration;import java.util.*;import static org.junit.jupiter.api.Assertions.*;
class ProcessRunnerTest {
 @TempDir Path temp;
 @Test void removesCredentialsFromAgentEnvironment()throws Exception{var r=new ProcessRunner().run(List.of("sh","-c","env"),temp,Duration.ofSeconds(5),Map.of());assertTrue(r.succeeded());assertFalse(r.output().contains("GH_TOKEN="));assertFalse(r.output().contains("SUPABASE_SERVICE_ROLE_KEY="));assertFalse(r.output().contains("DISPATCHER_TOKEN="));}
 @Test void killsTimedOutProcess()throws Exception{var r=new ProcessRunner().run(List.of("sh","-c","sleep 5"),temp,Duration.ofMillis(100),Map.of());assertTrue(r.timedOut());}
}
