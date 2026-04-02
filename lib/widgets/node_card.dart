import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../graph_provider.dart';
import '../ui_state_provider.dart';

class NodeCard extends StatelessWidget {
  final CategoryNode node;

  const NodeCard({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    var uiState = context.watch<UIStateProvider>();
    var graph = context.watch<GraphProvider>();
    bool isSelected = uiState.isSelected(node);
    bool isEditMode = uiState.isEditMode;

    var key = uiState.getNodeKey(node.uuid);

    Widget buildCard({bool useKey = false}) {
      return Card(
        key: useKey ? key : null,
        margin: EdgeInsets.zero,
        shape: isSelected
            ? RoundedRectangleBorder(
                side: const BorderSide(color: Colors.blueAccent, width: 2),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: InkWell(
          onTap: () => uiState.toggleSelection(node),
          onDoubleTap: () => uiState.longPressSelect(node),
          onLongPress: () => uiState.startEditing(node),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (uiState.editingNode == node)
                  _InlineEditor(node: node)
                else
                  Text(
                    node.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                if (node.description != null && node.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(node.description!, style: const TextStyle(fontSize: 14)),
                ],
                const SizedBox(height: 8),
                Text(
                  'Dependencies: ${graph.countTotalDependencies(node)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  'Dependents: ${graph.countTotalDependents(node)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!isEditMode) return buildCard(useKey: true);

    return DragTarget<CategoryNode>(
      onWillAcceptWithDetails: (details) {
        return details.data.uuid != node.uuid;
      },
      onAcceptWithDetails: (details) {
        var graph = context.read<GraphProvider>();
        CategoryNode draggedNode = details.data;
        CategoryNode targetNode = node; // Dropping A onto B makes B the parent, A the child

        bool hasChildLink = targetNode.children.contains(draggedNode);
        bool hasParentLink = draggedNode.children.contains(targetNode);

        if (hasChildLink) {
           graph.removeLink(targetNode, draggedNode);
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link removed!')));
        } else if (hasParentLink) {
           graph.removeLink(draggedNode, targetNode);
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link removed!')));
        } else {
           if (graph.wouldCreateCycle(targetNode, draggedNode)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Cannot link: Circular dependency!'),
                backgroundColor: Colors.red,
              ));
           } else {
              graph.addLink(targetNode, draggedNode);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link created!')));
           }
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Draggable<CategoryNode>(
          data: node,
          feedback: Material(
            elevation: 8.0,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 250,
              child: buildCard(useKey: false),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: buildCard(useKey: true),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: candidateData.isNotEmpty
                  ? Border.all(color: Colors.green, width: 3)
                  : null,
            ),
            child: buildCard(useKey: true),
          ),
        );
      },
    );
  }
}

class _InlineEditor extends StatefulWidget {
  final CategoryNode node;
  const _InlineEditor({required this.node});

  @override
  _InlineEditorState createState() => _InlineEditorState();
}

class _InlineEditorState extends State<_InlineEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.node.name);
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: widget.node.name.length);
    _focusNode = FocusNode();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    // Only invoke uiState/graph if still mounted
    if (!mounted) return;
    var graph = context.read<GraphProvider>();
    var uiState = context.read<UIStateProvider>();
    if (_controller.text.trim().isNotEmpty) {
      graph.updateNode(widget.node, name: _controller.text.trim());
    }
    // Prevent double invocation
    if (uiState.editingNode == widget.node) {
      uiState.stopEditing();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
      ),
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      cursorColor: Colors.blueAccent,
    );
  }
}
