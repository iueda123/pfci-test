package dev.continuousimprovement.app.capture;
import javafx.scene.Node;import java.util.List;
public record ScreenMaskPolicy(String screenId,List<Node> sensitiveNodes) {
 public ScreenMaskPolicy {if(screenId==null||screenId.isBlank())throw new IllegalArgumentException("registered screenId required");sensitiveNodes=List.copyOf(sensitiveNodes);if(sensitiveNodes.isEmpty())throw new IllegalArgumentException("at least one sensitive node required");}
}
