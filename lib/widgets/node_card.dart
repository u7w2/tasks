import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
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

  void _handleTap(GraphProvider graph) {
    _tapCount++;

    if (_tapCount == 1) {
      graph.toggleSelection(widget.node);
    } else if (_tapCount == 2) {
      graph.ensureSelected(widget.node);
      graph.doubleTapSelect(widget.node);
    } else if (_tapCount >= 3) {
      graph.ensureSelected(widget.node);
      graph.tripleTapSelect(widget.node);
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

  Color? _getInheritedColor(CategoryNode node) {
    CategoryNode? current = node;
    while (current != null) {
      if (current.colorValue != null) {
        return Color(current.colorValue!);
      }
      if (current.parents.isNotEmpty) {
        current = current.parents.first;
      } else {
        current = null;
      }
    }
    return null;
  }

  Widget _buildIconInfo(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${months[date.month - 1]} ${date.day}";
  }

  bool _isOverdue(DateTime date) {
    if (widget.node.isCompleted) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return date.isBefore(today);
  }

  @override
  Widget build(BuildContext context) {
    var uiState = context.watch<UIStateProvider>();
    var graph = context.watch<GraphProvider>();
    bool isSelected = graph.isSelected(widget.node);

    Widget buildCard({bool useKey = false, CategoryNode? overrideNode}) {
      CategoryNode targetNode = overrideNode ?? widget.node;
      bool isLocalSelected = graph.isSelected(targetNode);
      bool isLocalError = uiState.isErrorNode(targetNode);
      bool isInvalidTarget =
          uiState.isDragging && uiState.invalidDragTargets.contains(targetNode);
      var localKey = uiState.getNodeKey(targetNode.uuid);

      Color? inheritedColor = _getInheritedColor(targetNode);
      Color? cardBaseColor = inheritedColor?.withValues(alpha: 0.08);
      Color borderSideColor =
          inheritedColor?.withValues(alpha: 0.3) ??
          Theme.of(context).dividerColor.withValues(alpha: 0.1);

      return Opacity(
        opacity: isInvalidTarget ? 0.3 : (targetNode.isCompleted ? 0.8 : 1.0),
        child: Card(
          key: useKey ? localKey : null,
          margin: EdgeInsets.zero,
          color: cardBaseColor,
          shape: isLocalError
              ? RoundedRectangleBorder(
                  side: const BorderSide(color: Colors.red, width: 3),
                  borderRadius: BorderRadius.circular(8),
                )
              : RoundedRectangleBorder(
                  side: BorderSide(
                    color: isLocalSelected
                        ? Colors.blueAccent
                        : borderSideColor,
                    width: isLocalSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
          child: InkWell(
            canRequestFocus: false,
            onTap: (overrideNode == null && uiState.editingNode != targetNode)
                ? () => _handleTap(graph)
                : null,
            onLongPress: (overrideNode == null)
                ? () => showTaskEditor(context, targetNode)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.scale(
                    scale: 0.9,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: targetNode.isCompleted,
                        onChanged: (val) {
                          if (val != null) {
                            graph.updateNode(targetNode, isCompleted: val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (targetNode.priority != TaskPriority.low)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: targetNode.priority.color.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: targetNode.priority.color.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: Text(
                                targetNode.priority.label.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: targetNode.priority.color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        // Inline editor removed in favor of Modal Bottom Sheet
                        Text(
                          targetNode.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            decoration: targetNode.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: targetNode.isCompleted ? Colors.grey : null,
                          ),
                        ),
                        if (targetNode.description != null &&
                            targetNode.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          MarkdownLite(
                            text: targetNode.description!,
                            style: TextStyle(
                              fontSize: 14,
                              decoration: targetNode.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: targetNode.isCompleted
                                  ? Colors.grey
                                  : (inheritedColor != null
                                        ? inheritedColor.withValues(alpha: 0.8)
                                        : null),
                            ),
                          ),
                        ],
                        if (targetNode.weight != null ||
                            targetNode.dueDate != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (targetNode.weight != null)
                                _buildIconInfo(
                                  Icons.fitness_center,
                                  targetNode.weight.toString(),
                                  Colors.blueGrey,
                                ),
                              if (targetNode.weight != null &&
                                  targetNode.dueDate != null)
                                const SizedBox(width: 12),
                              if (targetNode.dueDate != null)
                                _buildIconInfo(
                                  Icons.calendar_today,
                                  _formatDate(targetNode.dueDate!),
                                  _isOverdue(targetNode.dueDate!)
                                      ? Colors.red
                                      : Colors.blueGrey,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double currentWidth = constraints.maxWidth;

        return DragTarget<List<CategoryNode>>(
          onWillAcceptWithDetails: (details) {
            if (graph.isSelected(widget.node)) return false;
            if (uiState.invalidDragTargets.contains(widget.node)) return false;
            uiState.setHoverTarget(widget.node);
            return true;
          },
          onLeave: (data) => uiState.clearHoverTarget(),
          onAcceptWithDetails: (details) {
            var graph = context.read<GraphProvider>();
            List<CategoryNode> draggedNodes = details.data;
            CategoryNode targetNode = widget.node;

            bool hasCycle = false;
            for (var draggedNode in draggedNodes) {
              bool hasDirectLink =
                  targetNode.children.contains(draggedNode) ||
                  draggedNode.children.contains(targetNode);
              if (!hasDirectLink &&
                  graph.wouldCreateCycle(targetNode, draggedNode)) {
                hasCycle = true;
                break;
              }
            }

            if (hasCycle) {
              uiState.flashError([targetNode, ...draggedNodes]);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cannot link: Circular dependency!'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            bool anyLinkExists = draggedNodes.any(
              (node) =>
                  targetNode.children.contains(node) ||
                  node.children.contains(targetNode),
            );

            for (var draggedNode in draggedNodes) {
              if (anyLinkExists) {
                // If any link exists, we ensure ALL are removed
                if (targetNode.children.contains(draggedNode)) {
                  graph.removeLink(targetNode, draggedNode);
                }
                if (draggedNode.children.contains(targetNode)) {
                  graph.removeLink(draggedNode, targetNode);
                }
              } else {
                // No links existed at all, so create new ones
                graph.addLink(targetNode, draggedNode);
              }
            }
            uiState.clearHoverTarget();
          },
          builder: (context, candidateData, rejectedData) {
            bool isHovered = candidateData.isNotEmpty;
            Color? borderColor;
            if (isHovered) {
              bool isDeletion = false;
              for (var draggedNode in candidateData.first!) {
                if (widget.node.children.contains(draggedNode) ||
                    draggedNode.children.contains(widget.node)) {
                  isDeletion = true;
                  break;
                }
              }
              borderColor = isDeletion ? Colors.red : Colors.green;
            }

            Widget cardWrap = Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: borderColor != null
                    ? Border.all(color: borderColor, width: 3)
                    : null,
              ),
              child: buildCard(useKey: true),
            );

            if (!isSelected) {
              return cardWrap;
            }

            List<CategoryNode> draggedData = graph.selectedNodes.toList();

            List<CategoryNode> stackOrder = List.from(draggedData);
            stackOrder.remove(widget.node);
            stackOrder = stackOrder.take(4).toList();
            stackOrder.add(widget.node);

            return Draggable<List<CategoryNode>>(
              data: draggedData,
              onDragStarted: () {
                var graph = context.read<GraphProvider>();
                context.read<UIStateProvider>().startDragging(
                  draggedData,
                  graph,
                );
              },
              onDragEnd: (details) =>
                  context.read<UIStateProvider>().stopDragging(),
              onDraggableCanceled: (velocity, offset) =>
                  context.read<UIStateProvider>().stopDragging(),
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: currentWidth + (stackOrder.length - 1) * 8.0,
                  height: 100 + (stackOrder.length - 1) * 8.0,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: List.generate(stackOrder.length, (index) {
                      bool isTop = index == stackOrder.length - 1;
                      int offsetIndex = (stackOrder.length - 1) - index;
                      return Positioned(
                        top: offsetIndex * 8.0,
                        left: offsetIndex * 8.0,
                        width: currentWidth,
                        child: Material(
                          color: Colors.transparent,
                          elevation: isTop ? 8.0 : 2.0,
                          borderRadius: BorderRadius.circular(8),
                          child: Opacity(
                            opacity: isTop
                                ? 1.0
                                : (1.0 - (offsetIndex * 0.15)).clamp(0.1, 1.0),
                            child: buildCard(overrideNode: stackOrder[index]),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: cardWrap),
              child: cardWrap,
            );
          },
        );
      },
    );
  }
}

void showTaskEditor(BuildContext context, CategoryNode node) {
  final graph = context.read<GraphProvider>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => ChangeNotifierProvider.value(
      value: graph,
      child: TaskEditorSheet(node: node),
    ),
  );
}

class TaskEditorSheet extends StatefulWidget {
  final CategoryNode node;
  const TaskEditorSheet({super.key, required this.node});

  @override
  TaskEditorSheetState createState() => TaskEditorSheetState();
}

class TaskEditorSheetState extends State<TaskEditorSheet> {
  late TextEditingController _controller;
  late TextEditingController _weightController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.node.name);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.node.name.length,
    );
    _weightController = TextEditingController(
      text: widget.node.weight?.toString() ?? '',
    );
    _focusNode = FocusNode();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _weightController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    // Only invoke uiState/graph if still mounted
    if (!mounted) return;
    var graph = context.read<GraphProvider>();
    var uiState = context.read<UIStateProvider>();

    int? weight;
    if (_weightController.text.trim().isNotEmpty) {
      weight = int.tryParse(_weightController.text.trim());
    }

    if (_controller.text.trim().isNotEmpty) {
      graph.updateNode(
        widget.node,
        name: _controller.text.trim(),
        priority: _tempPriority,
        weight: weight,
        dueDate: _tempDate,
        colorValue: _tempColorValue,
      );
    }
    // Prevent double invocation
    if (uiState.editingNode == widget.node) {
      uiState.stopEditing();
    }
  }

  TaskPriority? _tempPriority;
  DateTime? _tempDate;
  int? _tempColorValue;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _tempDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _tempDate) {
      setState(() {
        _tempDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _tempPriority ??= widget.node.priority;
    _tempDate ??= widget.node.dueDate;
    _tempColorValue ??= widget.node.colorValue;

    return TapRegion(
      onTapOutside: (_) => Navigator.pop(context),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Edit Task",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  PlatformTextButton(
                    onPressed: () {
                      _submit();
                      Navigator.pop(context);
                    },
                    child: const Text(
                      "Done",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PlatformTextField(
                controller: _controller,
                focusNode: _focusNode,
                onSubmitted: (_) {
                  _submit();
                  Navigator.pop(context);
                },
                material: (_, _) => MaterialTextFieldData(
                  decoration: InputDecoration(
                    labelText: "Task Name",
                    border: const OutlineInputBorder(),
                  ),
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Weight",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        PlatformTextField(
                          controller: _weightController,
                          keyboardType: TextInputType.number,
                          material: (_, _) => MaterialTextFieldData(
                            decoration: const InputDecoration(
                              hintText: "0",
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Due Date",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        PlatformTextButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => _selectDate(context),
                          child: Text(
                            _tempDate == null
                                ? "Set Date"
                                : "${_tempDate!.day}/${_tempDate!.month}/${_tempDate!.year}",
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                "Priority",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: TaskPriority.values.map((p) {
                    bool isSelected = _tempPriority == p;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(p.label),
                        selected: isSelected,
                        selectedColor: p.color.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? p.color : Colors.grey,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _tempPriority = p;
                            });
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Color Theme",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildColorOption(null, context), // Default/None
                    ...[
                      0xFF7C3AED, // Claude Purple
                      0xFF3B82F6, // Blue
                      0xFF10B981, // Emerald
                      0xFFF59E0B, // Amber
                      0xFFEF4444, // Rose
                      0xFF6366F1, // Indigo
                      0xFFEC4899, // Pink
                      0xFF14B8A6, // Teal
                    ].map((c) => _buildColorOption(c, context)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorOption(int? colorVal, BuildContext context) {
    bool isSelected = _tempColorValue == colorVal;
    return GestureDetector(
      onTap: () {
        setState(() {
          _tempColorValue = colorVal ?? -1;
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 10.0),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colorVal != null ? Color(colorVal) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Colors.black
                  : Colors.grey.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: isSelected && colorVal == null
              ? const Icon(Icons.close, size: 14, color: Colors.grey)
              : (isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null),
        ),
      ),
    );
  }
}

class MarkdownLite extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const MarkdownLite({super.key, required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    List<String> lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        String trimmed = line.trim();
        if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
          return Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("• ", style: style?.copyWith(fontWeight: FontWeight.bold)),
                Expanded(child: _buildRichLine(context, trimmed.substring(2))),
              ],
            ),
          );
        }
        if (trimmed.startsWith('[ ]') || trimmed.startsWith('[x]')) {
          bool isChecked = trimmed.startsWith('[x]');
          return Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Row(
              children: [
                Icon(
                  isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: isChecked ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(child: _buildRichLine(context, trimmed.substring(3))),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: _buildRichLine(context, line),
        );
      }).toList(),
    );
  }

  Widget _buildRichLine(BuildContext context, String line) {
    List<TextSpan> spans = [];
    RegExp exp = RegExp(r'\*\*(.*?)\*\*');
    int lastMatchEnd = 0;
    for (var match in exp.allMatches(line)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: line.substring(lastMatchEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < line.length) {
      spans.add(TextSpan(text: line.substring(lastMatchEnd)));
    }
    return RichText(
      text: TextSpan(
        style: style ?? Theme.of(context).textTheme.bodyMedium,
        children: spans,
      ),
    );
  }
}
