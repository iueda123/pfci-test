package dev.continuousimprovement.dispatcher;
import dev.continuousimprovement.core.security.SecretDetector;import java.nio.file.*;import java.time.Duration;import java.util.*;
public final class VerificationGate {
 private static final Set<String> BLOCKED=Set.of(".git","local-reports","artifacts/raw");private final ProcessRunner runner;private final int maxLines;
 public VerificationGate(ProcessRunner runner,int maxLines){this.runner=runner;this.maxLines=maxLines;}
 public Result verify(Path worktree,List<List<String>> testCommands)throws Exception{
  var names=runner.run(List.of("git","status","--porcelain=v1","--untracked-files=all"),worktree,Duration.ofSeconds(30),Map.of());if(!names.succeeded())return Result.fail("cannot inspect diff");
  var files=names.output().lines().filter(s->s.length()>3).map(s->s.substring(3)).map(s->s.contains(" -> ")?s.substring(s.indexOf(" -> ")+4):s).toList();for(String f:files)if(f.startsWith("/")||f.contains("..")||BLOCKED.stream().anyMatch(x->f.equals(x)||f.startsWith(x+"/")))return Result.fail("blocked path: "+f);
  var stat=runner.run(List.of("git","diff","--numstat","HEAD"),worktree,Duration.ofSeconds(30),Map.of());int lines=stat.output().lines().mapToInt(l->{var p=l.split("\\s+");try{return Integer.parseInt(p[0])+Integer.parseInt(p[1]);}catch(Exception e){return 0;}}).sum();for(String f:files){Path p=worktree.resolve(f);if(Files.isRegularFile(p)&&!stat.output().contains("\t"+f))try(var content=Files.lines(p)){lines+=content.limit(maxLines+1L).count();}catch(Exception ignored){}}if(lines>maxLines)return Result.fail("diff exceeds "+maxLines+" lines");
  var diff=runner.run(List.of("git","diff","--no-ext-diff","HEAD"),worktree,Duration.ofSeconds(30),Map.of());var detector=new SecretDetector();var secrets=new ArrayList<>(detector.detect(diff.output()));for(String f:files){Path p=worktree.resolve(f);if(Files.isRegularFile(p))try{secrets.addAll(detector.detect(Files.readString(p)));}catch(Exception ignored){}}if(!secrets.isEmpty())return Result.fail("secret scan: "+String.join(",",new LinkedHashSet<>(secrets)));
  List<String> tests=new ArrayList<>();for(var command:testCommands){var result=runner.run(command,worktree,Duration.ofMinutes(10),Map.of());tests.add(String.join(" ",command)+": "+(result.succeeded()?"passed":"failed"));if(!result.succeeded())return new Result(false,"verification command failed",files,tests);}
  return new Result(true,"verified",files,tests);
 }
 public record Result(boolean passed,String reason,List<String> files,List<String> tests){static Result fail(String r){return new Result(false,r,List.of(),List.of());}}
}
