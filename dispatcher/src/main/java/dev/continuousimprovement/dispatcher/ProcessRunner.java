package dev.continuousimprovement.dispatcher;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.TimeUnit;

public final class ProcessRunner {
    private static final Set<String> SAFE_ENV = Set.of("PATH","JAVA_HOME","LANG","LC_ALL","TERM","TMPDIR","GRADLE_USER_HOME","XDG_CACHE_HOME");
    public Result run(List<String> command, Path directory, Duration timeout, Map<String,String> additions) throws IOException, InterruptedException {
        return run(command,directory,timeout,additions,false);
    }
    public Result runControl(List<String> command, Path directory, Duration timeout, Map<String,String> additions) throws IOException, InterruptedException {
        return run(command,directory,timeout,additions,true);
    }
    private Result run(List<String> command, Path directory, Duration timeout, Map<String,String> additions, boolean control) throws IOException, InterruptedException {
        if(command.isEmpty() || timeout.isNegative() || timeout.isZero()) throw new IllegalArgumentException("invalid process request");
        Path outputFile=Files.createTempFile("improvement-process-",".log");
        var builder=new ProcessBuilder(command).directory(directory.toFile()).redirectErrorStream(true).redirectOutput(outputFile.toFile());
        var original=System.getenv();builder.environment().clear();if(control)builder.environment().putAll(original);else SAFE_ENV.forEach(k->{if(original.containsKey(k))builder.environment().put(k,original.get(k));});
        additions.forEach((k,v)->{if(!control&&!SAFE_ENV.contains(k))throw new IllegalArgumentException("environment variable not allowed: "+k);builder.environment().put(k,v);});
        Process process;try{process=builder.start();}catch(IOException e){Files.deleteIfExists(outputFile);throw e;}boolean finished;try{finished=process.waitFor(timeout.toMillis(),TimeUnit.MILLISECONDS);}catch(InterruptedException e){process.descendants().forEach(ProcessHandle::destroyForcibly);process.destroyForcibly();Files.deleteIfExists(outputFile);throw e;}
        if(!finished){process.descendants().forEach(ProcessHandle::destroyForcibly);process.destroyForcibly();process.waitFor(5,TimeUnit.SECONDS);}
        byte[] captured;try(var stream=Files.newInputStream(outputFile)){captured=stream.readNBytes(5*1024*1024+1);}finally{Files.deleteIfExists(outputFile);}String output=new String(captured,0,Math.min(captured.length,5*1024*1024),StandardCharsets.UTF_8)+(captured.length>5*1024*1024?"\n[OUTPUT_TRUNCATED]":"");
        return new Result(finished?process.exitValue():-1,output,!finished);
    }
    public record Result(int exitCode,String output,boolean timedOut){public boolean succeeded(){return !timedOut&&exitCode==0;}}
}
