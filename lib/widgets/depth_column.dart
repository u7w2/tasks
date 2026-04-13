import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../graph_provider.dart';
import 'node_card.dart';

class DepthColumn extends StatelessWidget {
  final int depth;
  final List<CategoryNode> nodes;

  const DepthColumn({super.key, required this.depth, required this.nodes});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              // Interleave gaps: gap(0), node(0), gap(1), node(1), ..., node(n-1), gap(n)
              itemCount: nodes.length * 2 + 1,
              itemBuilder: (context, index) {
                if (index.isEven) {
                  return _ColumnGap(
                    gapIndex: index ~/ 2,
                    depth: depth,
                    columnNodes: nodes,
                  );
                }
                return NodeCard(node: nodes[index ~/ 2]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A gap DragTarget shown between nodes in a column.
/// Only accepts drags where all dragged nodes are from the same column (same depth),
/// treating the drop as a reorder rather than a dependency link.
class _ColumnGap extends StatelessWidget {
  final int gapIndex;
  final int depth;
  final List<CategoryNode> columnNodes;

  const _ColumnGap({
    required this.gapIndex,
    required this.depth,
    required this.columnNodes,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<List<CategoryNode>>(
      onWillAcceptWithDetails: (details) {
        // Only accept if ALL dragged nodes are in this column
        return details.data.every((n) => n.depth == depth);
      },
      onAcceptWithDetails: (details) {
        context.read<GraphProvider>().reorderNodes(
          details.data,
          gapIndex,
          columnNodes,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: isActive ? 20.0 : 8.0,
          alignment: Alignment.center,
          child: isActive
              ? Container(
                  height: 3.0,
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}
