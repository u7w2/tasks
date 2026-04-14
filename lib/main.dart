import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'graph_provider.dart';
import 'ui_state_provider.dart';
import 'widgets/depth_column.dart';
import 'widgets/line_painter.dart';
import 'workflows_provider.dart';
import 'settings_page.dart';
import 'storage_service.dart';

void main() {
  runApp(const TasksApp());
}

class TasksApp extends StatelessWidget {
  const TasksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => WorkflowsProvider()),
        ChangeNotifierProvider(create: (context) => UIStateProvider()),
      ],
      child: MaterialApp(
        title: "Tasks",
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.system,
        home: const TasksScreen(),
      ),
    );
  }
}

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var workflows = context.watch<WorkflowsProvider>();
    if (!workflows.isLoaded || workflows.currentGraph == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    var graph = workflows.currentGraph!;

    return ChangeNotifierProvider.value(
      value: graph,
      child: const TasksScreenContent(),
    );
  }
}

class TasksScreenContent extends StatefulWidget {
  const TasksScreenContent({super.key});

  @override
  State<TasksScreenContent> createState() => _TasksScreenContentState();
}

class _TasksScreenContentState extends State<TasksScreenContent> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  String? _lastGraphId;
  Timer? _drawerHoverTimer;

  @override
  void dispose() {
    _scrollController.dispose();
    _drawerHoverTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final graphId = context.read<GraphProvider>().id;
    if (_lastGraphId != null && _lastGraphId != graphId) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
    _lastGraphId = graphId;
  }

  @override
  Widget build(BuildContext context) {
    var workflows = context.watch<WorkflowsProvider>();
    var graph = context.watch<GraphProvider>();
    var uiState = context.watch<UIStateProvider>();

    bool hasActiveState = graph.selectedNodes.isNotEmpty || uiState.editingNode != null || uiState.searchQuery.isNotEmpty;

    return PopScope(
      canPop: !hasActiveState,
      onPopInvokedWithResult: (didPop, dynamic result) {
        if (didPop) return;
        graph.clearSelection();
        if (uiState.searchQuery.isNotEmpty) uiState.clearSearch(graph);
        if (uiState.editingNode != null) uiState.stopEditing();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const WorkflowsDrawer(),
        appBar: AppBar(
        title: const _SearchBar(),
        actions: [
          if (graph.canUndo)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              onPressed: () => graph.undo(),
            ),
          if (graph.selectedNodes.length == 1)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => uiState.startEditing(graph.selectedNodes.first),
            ),
          if (graph.selectedNodes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                var nodesToDelete = graph.selectedNodes;
                graph.removeNodes(nodesToDelete);
                graph.clearSelection();
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'export') {
                // Let user pick which workflows to export
                final allWorkflows = workflows.workflows;
                final List<bool> checked = List.filled(allWorkflows.length, false);
                final selected = await showDialog<List<WorkflowMeta>>(
                  context: context,
                  builder: (ctx) => StatefulBuilder(
                    builder: (ctx, setState) => AlertDialog(
                      title: const Text('Select workflows to export'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: allWorkflows.length,
                          itemBuilder: (_, i) => CheckboxListTile(
                            title: Text(allWorkflows[i].name),
                            value: checked[i],
                            onChanged: (v) => setState(() => checked[i] = v ?? false),
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        TextButton(
                          onPressed: checked.contains(true)
                              ? () => Navigator.pop(ctx, [
                                  for (int i = 0; i < allWorkflows.length; i++)
                                    if (checked[i]) allWorkflows[i]
                                ])
                              : null,
                          child: const Text('Export'),
                        ),
                      ],
                    ),
                  ),
                );
                if (selected != null && selected.isNotEmpty && context.mounted) {
                  try {
                    final jsonString = await StorageService().exportWorkflows(selected);
                    final bytes = Uint8List.fromList(utf8.encode(jsonString));
                    final outputPath = await FilePicker.saveFile(
                      dialogTitle: 'Save exported workflows',
                      fileName: 'workflows_export.json',
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                      bytes: bytes,
                    );
                    if (outputPath != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Exported ${selected.length} workflow${selected.length == 1 ? '' : 's'}')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
                    }
                  }
                }
              } else if (value == 'import') {
                final result = await FilePicker.pickFiles(
                  dialogTitle: 'Import Workflows',
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                  allowMultiple: true,
                  withData: true,
                );
                if (result != null) {
                  int total = 0;
                  for (final picked in result.files) {
                    if (picked.bytes == null) continue;
                    try {
                      final jsonString = String.fromCharCodes(picked.bytes!);
                      total += await workflows.importWorkflows(jsonString);
                    } catch (e) {
                      debugPrint('Failed to import file ${picked.name}: $e');
                    }
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      total > 0
                          ? SnackBar(content: Text('Imported $total workflow${total == 1 ? '' : 's'}'))
                          : const SnackBar(content: Text('No workflows found in selected files')),
                    );
                  }
                }
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'export', child: Text('Export Workflows')),
              const PopupMenuItem(value: 'import', child: Text('Import Workflows')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Set<CategoryNode>? parentNodes;
          if (graph.selectedNodes.isNotEmpty) {
            parentNodes = graph.selectedNodes.toSet();
          }
          var newNode = graph.addNode(
            "New Task",
            parents: parentNodes,
          );
          graph.clearSelection();
          graph.toggleSelection(newNode);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            bool needsScroll = false;
            if (_scrollController.hasClients) {
              int targetDepth = newNode.depth ?? 0;
              double targetScroll = (targetDepth * 120.0).clamp(0.0, _scrollController.position.maxScrollExtent);
              needsScroll = (targetScroll - _scrollController.offset).abs() > 1.0;
              if (needsScroll) {
                _scrollController.animateTo(
                  targetScroll,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                );
              }
            }

            if (needsScroll) {
              Future.delayed(const Duration(milliseconds: 320), () {
                uiState.startEditing(newNode);
              });
            } else {
              uiState.startEditing(newNode);
            }
          });
        },
      ),
      body: GraphBody(scrollController: _scrollController),
    ));
  }
}

class WorkflowsDrawer extends StatefulWidget {
  const WorkflowsDrawer({super.key});

  @override
  State<WorkflowsDrawer> createState() => _WorkflowsDrawerState();
}

class _WorkflowsDrawerState extends State<WorkflowsDrawer> {
  String? _editingWorkflowId;

  void _startEditing(String id) {
    setState(() {
      _editingWorkflowId = id;
    });
  }

  void _stopEditing() {
    if (mounted) {
      setState(() {
        _editingWorkflowId = null;
      });
    }
  }

  Future<void> _attemptDelete(BuildContext context, String workflowId, String workflowName, WorkflowsProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    bool doNotShow = prefs.getBool('hide_delete_workflow_prompt') ?? false;

    if (doNotShow) {
      provider.deleteWorkflow(workflowId);
      return;
    }

    if (!context.mounted) return;

    bool rememberChoice = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text("Delete Workflow"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Are you sure you want to delete '$workflowName'?"),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: rememberChoice,
                      onChanged: (bool? value) {
                        setState(() {
                          rememberChoice = value ?? false;
                        });
                      },
                    ),
                    const Expanded(child: Text("Do not show again")),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  if (rememberChoice) {
                    prefs.setBool('hide_delete_workflow_prompt', true);
                  }
                  provider.deleteWorkflow(workflowId);
                  Navigator.pop(context);
                },
                child: const Text("Delete", style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var workflowsProvider = context.watch<WorkflowsProvider>();
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Workflows',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: workflowsProvider.workflows.length,
                itemBuilder: (context, index) {
                  var workflow = workflowsProvider.workflows[index];
                  bool isSelected = workflow.id == workflowsProvider.currentWorkflowId;
                  bool isEditing = workflow.id == _editingWorkflowId;
                  final tile = ListTile(
                    leading: Icon(isSelected ? Icons.folder_open : Icons.folder),
                    title: isEditing 
                      ? _InlineWorkflowEditor(
                          workflowId: workflow.id,
                          initialName: workflow.name,
                          onComplete: (newName) {
                            if (newName.trim().isNotEmpty) {
                              context.read<WorkflowsProvider>().updateWorkflowName(workflow.id, newName.trim());
                            }
                            _stopEditing();
                          },
                        ) 
                      : Text(
                          workflow.name,
                          style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                        ),
                    selected: isSelected,
                    onTap: () {
                      if (isEditing) return;
                      var uiState = context.read<UIStateProvider>();
                      uiState.clearSearch(context.read<GraphProvider>());
                      workflowsProvider.switchWorkflow(workflow.id);
                    },
                    onLongPress: () {
                      _startEditing(workflow.id);
                    },
                    trailing: isSelected ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _attemptDelete(context, workflow.id, workflow.name, workflowsProvider);
                      },
                    ) : null,
                  );

                  return DragTarget<List<CategoryNode>>(
                    onWillAcceptWithDetails: (details) => !isSelected,
                    onAcceptWithDetails: (details) {
                      workflowsProvider.moveNodes(details.data.toSet(), workflow.id);
                      var uiState = context.read<UIStateProvider>();
                      uiState.stopDragging();
                      Scaffold.of(context).closeDrawer();
                    },
                    builder: (context, candidateData, rejectedData) {
                      bool isHovered = candidateData.isNotEmpty;
                      return Container(
                        decoration: BoxDecoration(
                          color: isHovered ? Colors.blueAccent.withValues(alpha: 0.1) : null,
                        ),
                        child: tile,
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text("New Workflow"),
              onTap: () {
                var uiState = context.read<UIStateProvider>();
                uiState.clearSearch(context.read<GraphProvider>());
                String newId = workflowsProvider.createNewWorkflow();
                _startEditing(newId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _InlineWorkflowEditor extends StatefulWidget {
  final String workflowId;
  final String initialName;
  final Function(String) onComplete;

  const _InlineWorkflowEditor({
    required this.workflowId,
    required this.initialName,
    required this.onComplete,
  });

  @override
  _InlineWorkflowEditorState createState() => _InlineWorkflowEditorState();
}

class _InlineWorkflowEditorState extends State<_InlineWorkflowEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: widget.initialName.length);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onComplete(_controller.text);
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
      style: const TextStyle(fontSize: 16),
      cursorColor: Colors.blueAccent,
    );
  }
}

class GraphBody extends StatefulWidget {
  final ScrollController scrollController;
  const GraphBody({super.key, required this.scrollController});

  @override
  State<GraphBody> createState() => _GraphBodyState();
}

class _GraphBodyState extends State<GraphBody> {
  late VoidCallback _onScroll;
  Timer? _scrollTimer;
  Timer? _drawerHoverTimer;

  void _startScrollTimer(double delta) {
    if (_scrollTimer != null) return;
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!widget.scrollController.hasClients) return;
      double newOffset = widget.scrollController.offset + delta;
      newOffset = newOffset.clamp(0.0, widget.scrollController.position.maxScrollExtent);
      widget.scrollController.jumpTo(newOffset);
    });
  }

  void _stopScrollTimer() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  void _handlePointerMove(PointerMoveEvent event, UIStateProvider uiState) {
    if (!uiState.isDragging) {
      _stopScrollTimer();
      _drawerHoverTimer?.cancel();
      _drawerHoverTimer = null;
      return;
    }

    double x = event.localPosition.dx;
    double screenWidth = MediaQuery.of(context).size.width;
    const double scrollThreshold = 80.0;
    const double drawerThreshold = 30.0;

    // Sidebar hover
    if (x < drawerThreshold) {
      _drawerHoverTimer ??= Timer(const Duration(milliseconds: 400), () {
        Scaffold.of(context).openDrawer();
      });
    } else {
      _drawerHoverTimer?.cancel();
      _drawerHoverTimer = null;
    }

    // Auto-scroll
    if (x < scrollThreshold) {
      _startScrollTimer(-5.0);
    } else if (x > screenWidth - scrollThreshold) {
      _startScrollTimer(5.0);
    } else {
      _stopScrollTimer();
    }
  }

  @override
  void initState() {
    super.initState();
    _onScroll = () => setState(() {});
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _scrollTimer?.cancel();
    _drawerHoverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var graph = context.watch<GraphProvider>();
    var uiState = context.watch<UIStateProvider>();

    Map<int, List<CategoryNode>> depthMap = {};
    for (var node in graph.getAllNodes()) {
      int depth = node.depth ?? 0;
      depthMap.putIfAbsent(depth, () => []).add(node);
    }
    // Sort nodes within each column by sortIndex; nulls go to the end
    for (var list in depthMap.values) {
      list.sort((a, b) {
        final ai = a.sortIndex;
        final bi = b.sortIndex;
        if (ai == null && bi == null) return 0;
        if (ai == null) return 1;
        if (bi == null) return -1;
        return ai.compareTo(bi);
      });
    }
    
    List<int> sortedDepths = depthMap.keys.toList()..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        double screenWidth = constraints.maxWidth;
        double defaultColWidth = 120.0;
        int extraCols = sortedDepths.length > 1 ? sortedDepths.length - 1 : 0;
        double calculatedMaxScroll = extraCols * defaultColWidth;
        
        double rawScrollOffset = widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
        double scrollOffset = rawScrollOffset.clamp(0.0, calculatedMaxScroll);

        return NotificationListener<ScrollNotification>(
          onNotification: (_) {
            setState(() {});
            return false;
          },
          child: Listener(
            onPointerMove: (e) => _handlePointerMove(e, uiState),
            onPointerUp: (_) {
               _stopScrollTimer();
               _drawerHoverTimer?.cancel();
               _drawerHoverTimer = null;
            },
            child: GestureDetector(
          onTap: () {
            graph.clearSelection();
            if (uiState.editingNode != null) uiState.stopEditing();
          },
          behavior: HitTestBehavior.translucent,
          child: Stack(
            fit: StackFit.expand,
            children: [
            CustomPaint(
              painter: LinePainter(graph, uiState, context),
            ),
            SingleChildScrollView(
              controller: widget.scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sortedDepths.map((depth) {
                  bool isFirst = depth == sortedDepths.first;
                  
                  if (!isFirst) {
                    return SizedBox(
                      width: defaultColWidth,
                      child: DepthColumn(depth: depth, nodes: depthMap[depth]!),
                    );
                  }

                  // FIRST COLUMN LOGIC
                  // Maintain physical Row size to prevent 2x warped scrolling, while transforming internal layout
                  double maxOffset = screenWidth > defaultColWidth ? screenWidth - defaultColWidth : 0.0;
                  double offset = scrollOffset.clamp(0.0, maxOffset);
                  double visualWidth = (screenWidth - scrollOffset).clamp(defaultColWidth, screenWidth);

                  return SizedBox(
                    width: screenWidth, // Keep layout geometry completely solid
                    child: Stack(
                      children: [
                        Positioned(
                          left: offset,
                          width: visualWidth,
                          top: 0,
                          bottom: 0,
                          child: DepthColumn(depth: depth, nodes: depthMap[depth]!),
                        ),
                      ],
                    ),
                  );
                 }).toList(),
              ),
            ),
          ],
        ))));  // Stack, GestureDetector, Listener, NotificationListener
      }
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar();

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var uiState = context.watch<UIStateProvider>();
    if (uiState.searchQuery.isEmpty && _controller.text.isNotEmpty) {
      _controller.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    var uiState = context.read<UIStateProvider>();
    var graph = context.read<GraphProvider>();
    uiState.searchNodes(query, graph);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode..skipTraversal = true,
      decoration: InputDecoration(
        hintText: "Search nodes (Regex)...",
        border: InputBorder.none,
        icon: const Icon(Icons.search, color: Colors.grey),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  var graph = context.read<GraphProvider>();
                  var uiState = context.read<UIStateProvider>();
                  uiState.clearSearch(graph);
                  FocusScope.of(context).unfocus();
                },
              )
            : null,
      ),
      onChanged: _onChanged,
      style: const TextStyle(fontSize: 16),
    );
  }
}