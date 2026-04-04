import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../graph_provider.dart';
import '../ui_state_provider.dart';

class NodeCard extends StatefulWidget {
  final CategoryNode node;

  const NodeCard({super.key, required this.node});

  @override
  State<NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends State<NodeCard> {
  int _tapCount = 0;
  Timer? _tapTimer;

  void _handleTap(UIStateProvider uiState) {
    _tapCount++;
    
    if (_tapCount == 1) {
      uiState.toggleSelection(widget.node);
    } else if (_tapCount == 2) {
      uiState.ensureSelected(widget.node);
      uiState.doubleTapSelect(widget.node);
    } else if (_tapCount >= 3) {
      uiState.ensureSelected(widget.node);
      uiState.tripleTapSelect(widget.node);
      _tapCount = 0;
    }
    
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _tapCount = 0;
      }
    });
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var uiState = context.watch<UIStateProvider>();
    bool isSelected = uiState.isSelected(widget.node);


    Widget buildCard({bool useKey = false, CategoryNode? overrideNode}) {
      CategoryNode targetNode = overrideNode ?? widget.node;
      bool isLocalSelected = uiState.isSelected(targetNode);
      bool isLocalError = uiState.isErrorNode(targetNode);
      var localKey = uiState.getNodeKey(targetNode.uuid);

      return Card(
        key: useKey ? localKey : null,
        margin: EdgeInsets.zero,
        shape: isLocalError 
            ? RoundedRectangleBorder(
                side: const BorderSide(color: Colors.red, width: 3),
                borderRadius: BorderRadius.circular(8),
              )
            : isLocalSelected
            ? RoundedRectangleBorder(
                side: const BorderSide(color: Colors.blueAccent, width: 2),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: InkWell(
          onTap: overrideNode == null ? () => _handleTap(uiState) : null,
          onLongPress: overrideNode == null ? () => uiState.startEditing(widget.node) : null,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (uiState.editingNode == targetNode)
                  _InlineEditor(node: targetNode)
                else
                  Text(
                    targetNode.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                if (targetNode.description != null && targetNode.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(targetNode.description!, style: const TextStyle(fontSize: 14)),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    }

    return DragTarget<List<CategoryNode>>(
      onWillAcceptWithDetails: (details) {
        // Drop ignores Action if hovering over another selected node
        if (uiState.isSelected(widget.node)) return false;
        return true;
      },
      onAcceptWithDetails: (details) {
        var graph = context.read<GraphProvider>();
        var uiState = context.read<UIStateProvider>();
        List<CategoryNode> draggedNodes = details.data;
        CategoryNode targetNode = widget.node;

        bool hasCycle = false;
        for (var draggedNode in draggedNodes) {
          if (graph.wouldCreateCycle(targetNode, draggedNode)) {
            hasCycle = true;
            break;
          }
        }

        if (hasCycle) {
          uiState.flashError([targetNode, ...draggedNodes]);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cannot link: Circular dependency!'),
            backgroundColor: Colors.red,
          ));
          return;
        }

        for (var draggedNode in draggedNodes) {
           bool hasChildLink = targetNode.children.contains(draggedNode);
           bool hasParentLink = draggedNode.children.contains(targetNode);

           if (hasChildLink) {
              graph.removeLink(targetNode, draggedNode);
           } else if (hasParentLink) {
              graph.removeLink(draggedNode, targetNode);
           } else {
              graph.addLink(targetNode, draggedNode);
           }
        }
      },
      builder: (context, candidateData, rejectedData) {
        Widget cardWrap = Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: candidateData.isNotEmpty
                ? Border.all(color: Colors.green, width: 3)
                : null,
          ),
          child: buildCard(useKey: true),
        );

        if (!isSelected) {
          return cardWrap;
        }

        List<CategoryNode> draggedData = uiState.selectedNodes.toList();
        
        List<CategoryNode> stackOrder = List.from(draggedData);
        stackOrder.remove(widget.node);
        stackOrder = stackOrder.take(4).toList();
        stackOrder.add(widget.node);

        double baseWidth = 250.0;

        return Draggable<List<CategoryNode>>(
          data: draggedData,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
               width: baseWidth + (stackOrder.length - 1) * 8.0,
               height: 100 + (stackOrder.length - 1) * 8.0,
               child: Stack(
                 clipBehavior: Clip.none,
                 children: List.generate(stackOrder.length, (index) {
                    bool isTop = index == stackOrder.length - 1;
                    int offsetIndex = (stackOrder.length - 1) - index; 
                    return Positioned(
                       top: offsetIndex * 8.0,
                       left: offsetIndex * 8.0,
                       width: baseWidth,
                       child: Material(
                         color: Colors.transparent,
                         elevation: isTop ? 8.0 : 2.0,
                         borderRadius: BorderRadius.circular(8),
                         child: Opacity(
                            opacity: isTop ? 1.0 : (1.0 - (offsetIndex * 0.15)).clamp(0.1, 1.0),
                            child: buildCard(overrideNode: stackOrder[index]),
                         )
                       )
                    );
                 }),
               )
            )
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: cardWrap,
          ),
          child: cardWrap,
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
