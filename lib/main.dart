import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

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
  final ScrollController _scrollController = ScrollController();
  String? _lastGraphId;

  @override
  void dispose() {
    _scrollController.dispose();
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
    var graph = context.watch<GraphProvider>();
    var uiState = context.watch<UIStateProvider>();
    var workflows = context.watch<WorkflowsProvider>();

    bool hasActiveState = uiState.selectedNodes.isNotEmpty || uiState.editingNode != null || uiState.searchQuery.isNotEmpty;

    return PopScope(
      canPop: !hasActiveState,
      onPopInvokedWithResult: (didPop, dynamic result) {
        if (didPop) return;
        uiState.clearSelection();
        if (uiState.searchQuery.isNotEmpty) uiState.clearSearch();
        if (uiState.editingNode != null) uiState.stopEditing();
      },
      child: Scaffold(
        drawer: const WorkflowsDrawer(),
        appBar: AppBar(
        title: const _SearchBar(),
        actions: [
          if (uiState.selectedNodes.length == 1)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => uiState.startEditing(uiState.selectedNodes.first),
            ),
          if (uiState.selectedNodes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                var nodesToDelete = uiState.selectedNodes;
                graph.removeNodes(nodesToDelete);
                uiState.clearSelection();
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'export') {
                try {
                  var currentMeta = workflows.workflows.firstWhere((w) => w.id == workflows.currentWorkflowId);
                  String jsonString = await StorageService().exportWorkflow(currentMeta);

                  // Write to a temp file so share_plus can attach it
                  final dir = await getTemporaryDirectory();
                  final safeFileName = currentMeta.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
                  final file = File('${dir.path}/$safeFileName.json');
                  await file.writeAsString(jsonString);

                  final xFile = XFile(file.path, mimeType: 'application/json');
                  await SharePlus.instance.share(
                    ShareParams(
                      files: [xFile],
                      subject: currentMeta.name,
                    ),
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to export: $e')),
                    );
                  }
                }
              } else if (value == 'import') {
                FilePickerResult? result = await FilePicker.pickFiles(
                  dialogTitle: 'Import Workflow',
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                  withData: true, // read bytes directly — avoids path issues on iOS
                );
                if (result != null && result.files.single.bytes != null) {
                  try {
                    String jsonString = String.fromCharCodes(result.files.single.bytes!);
                    var imported = await workflows.importWorkflow(jsonString);
                    if (context.mounted) {
                      if (imported != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Workflow imported successfully')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to parse workflow file')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error importing: $e')),
                      );
                    }
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
              const PopupMenuItem(value: 'export', child: Text('Export Workflow')),
              const PopupMenuItem(value: 'import', child: Text('Import Workflow')),
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
          if (uiState.selectedNodes.isNotEmpty) {
            parentNodes = uiState.selectedNodes.toSet();
          }
          var newNode = graph.addNode(
            "New Task",
            parents: parentNodes,
          );
          uiState.clearSelection();
          uiState.toggleSelection(newNode);

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
                  return ListTile(
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
                      context.read<UIStateProvider>().clearSelection();
                      context.read<UIStateProvider>().clearSearch();
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
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text("New Workflow"),
              onTap: () {
                context.read<UIStateProvider>().clearSelection();
                context.read<UIStateProvider>().clearSearch();
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

  @override
  void initState() {
    super.initState();
    _onScroll = () => setState(() {});
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
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
          child: GestureDetector(
          onTap: () {
            uiState.clearSelection();
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
        )));  // Stack, GestureDetector, NotificationListener
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
                  _onChanged("");
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