import 'package:flutter/material.dart';
import '../graph_provider.dart';
import '../ui_state_provider.dart';

class LinePainter extends CustomPainter {
  final GraphProvider graph;
  final UIStateProvider uiState;
  final BuildContext context;

  LinePainter(this.graph, this.uiState, this.context);

  @override
  void paint(Canvas canvas, Size size) {
    if (graph.rootNodes.isEmpty) return;

    var paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    var highlightPaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    RenderBox? overlayBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;

    for (var child in graph.getAllNodes()) {
      for (var parent in child.parents) {
        var childKey = uiState.getNodeKey(child.uuid);
        var parentKey = uiState.getNodeKey(parent.uuid);

        if (childKey.currentContext == null || parentKey.currentContext == null) continue;

        var childBox = childKey.currentContext!.findRenderObject() as RenderBox?;
        var parentBox = parentKey.currentContext!.findRenderObject() as RenderBox?;

        if (childBox == null || parentBox == null) continue;

        // Convert coordinates relative to the Stack/CustomPaint boundary
        Offset childPos = childBox.localToGlobal(childBox.size.centerLeft(Offset.zero), ancestor: overlayBox);
        Offset parentPos = parentBox.localToGlobal(parentBox.size.centerRight(Offset.zero), ancestor: overlayBox);

        bool isHighlighted = uiState.isSelected(child) || uiState.isSelected(parent);
        
        var path = Path();
        path.moveTo(parentPos.dx, parentPos.dy);
        path.cubicTo(
          parentPos.dx + 30, parentPos.dy,
          childPos.dx - 30, childPos.dy,
          childPos.dx, childPos.dy,
        );

        canvas.drawPath(path, isHighlighted ? highlightPaint : paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LinePainter oldDelegate) => true; 
}
