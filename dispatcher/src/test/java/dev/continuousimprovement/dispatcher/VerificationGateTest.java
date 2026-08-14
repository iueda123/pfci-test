package dev.continuousimprovement.dispatcher;
import org.junit.jupiter.api.*;import org.junit.jupiter.api.io.TempDir;import java.nio.file.*;import java.util.*;import static org.junit.jupiter.api.Assertions.*;
class VerificationGateTest {
 @TempDir Path repo;
 @BeforeEach void git()throws Exception{run("git","init","-q");run("git","config","user.email","test@example.invalid");run("git","config","user.name","Test");Files.writeString(repo.resolve("safe.txt"),"base\n");run("git","add",".");run("git","commit","-qm","base");}
 @Test void acceptsSmallSafeDiff()throws Exception{Files.writeString(repo.resolve("safe.txt"),"fixed\n");var result=new VerificationGate(new ProcessRunner(),100).verify(repo,List.of(List.of("true")));assertTrue(result.passed(),result.reason());}
 @Test void rejectsSecret()throws Exception{Files.writeString(repo.resolve("safe.txt"),"sk-abcdefghijklmnopqrstuvwxyz123456\n");assertFalse(new VerificationGate(new ProcessRunner(),100).verify(repo,List.of()).passed());}
 @Test void includesNewUntrackedFiles()throws Exception{Files.writeString(repo.resolve("new.txt"),"new\n");var result=new VerificationGate(new ProcessRunner(),100).verify(repo,List.of());assertTrue(result.passed());assertEquals(List.of("new.txt"),result.files());}
 private void run(String...c)throws Exception{var p=new ProcessBuilder(c).directory(repo.toFile()).start();assertEquals(0,p.waitFor(),new String(p.getErrorStream().readAllBytes()));}
}
