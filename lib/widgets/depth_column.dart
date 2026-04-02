import 'package:flutter/material.dart';
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
              itemCount: nodes.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: NodeCard(node: nodes[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
