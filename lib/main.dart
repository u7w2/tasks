import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoThemeData, CupertinoIcons, CupertinoActionSheet, CupertinoActionSheetAction, DefaultCupertinoLocalizations, CupertinoColors;
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
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
      child: PlatformProvider(
        builder: (context) => PlatformApp(
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
            DefaultCupertinoLocalizations.delegate,
          ],
          title: "Tasks",
          material: (_, _) => MaterialAppData(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: ThemeMode.system,
          ),
          cupertino: (_, _) => CupertinoAppData(
            theme: const CupertinoThemeData(brightness: Brightness.light),
          ),
          home: const TasksScreen(),
        ),
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
      return PlatformScaffold(body: Center(child: PlatformCircularProgressIndicator()));
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

  void _addNewTask(GraphProvider graph, UIStateProvider uiState) {
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
      child: PlatformScaffold(
        widgetKey: _scaffoldKey,
        material: (_, _) => MaterialScaffoldData(
          drawer: const WorkflowsDrawer(),
          floatingActionButton: FloatingActionButton(
            child: const Icon(Icons.add),
            onPressed: () => _addNewTask(graph, uiState),
          ),
        ),
        appBar: PlatformAppBar(
          leading: isCupertino(context) 
            ? PlatformIconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(CupertinoIcons.bars),
                onPressed: () => showPlatformModalSheet(
                  context: context,
                  builder: (_) => const WorkflowsDrawer(),
                ),
              )
            : null,
          title: const _SearchBar(),
        trailingActions: [
          if (graph.canUndo)
            PlatformIconButton(
              padding: EdgeInsets.zero,
              icon: PlatformWidget(
                material: (_, _) => const Icon(Icons.undo),
                cupertino: (_, _) => const Icon(CupertinoIcons.arrow_uturn_left),
              ),
              onPressed: () => graph.undo(),
            ),
        if (graph.selectedNodes.length == 1)
          PlatformIconButton(
            padding: EdgeInsets.zero,
            icon: Icon(PlatformIcons(context).edit),
            onPressed: () => uiState.startEditing(graph.selectedNodes.first),
          ),
        if (graph.selectedNodes.isNotEmpty)
          PlatformIconButton(
            padding: EdgeInsets.zero,
            icon: Icon(PlatformIcons(context).delete),
            onPressed: () {
              var nodesToDelete = graph.selectedNodes;
              graph.removeNodes(nodesToDelete);
              graph.clearSelection();
            },
          ),
        PlatformWidget(
          material: (_, _) => PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async => _handleMenuAction(value, workflows, context),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'export', child: Text('Export Workflows')),
              const PopupMenuItem(value: 'import', child: Text('Import Workflows')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
          cupertino: (_, _) => PlatformIconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(CupertinoIcons.ellipsis),
            onPressed: () {
              showPlatformModalSheet(
                  context: context,
                  builder: (_) => PlatformWidget(
                        material: (_, _) => Container(),
                        cupertino: (_, _) => CupertinoActionSheet(
                          actions: [
                            CupertinoActionSheetAction(
                              onPressed: () {
                                Navigator.pop(context);
                                _handleMenuAction('export', workflows, context);
                              },
                              child: const Text('Export Workflows'),
                            ),
                            CupertinoActionSheetAction(
                              onPressed: () {
                                Navigator.pop(context);
                                _handleMenuAction('import', workflows, context);
                              },
                              child: const Text('Import Workflows'),
                            ),
                            CupertinoActionSheetAction(
                              onPressed: () {
                                Navigator.pop(context);
                                _handleMenuAction('settings', workflows, context);
                              },
                              child: const Text('Settings'),
                            ),
                          ],
                          cancelButton: CupertinoActionSheetAction(
                            isDefaultAction: true,
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ));
            },
          ),
        ),
        PlatformWidget(
          cupertino: (_, _) => PlatformIconButton(
            padding: EdgeInsets.zero,
            icon: Icon(PlatformIcons(context).add),
            onPressed: () => _addNewTask(graph, uiState),
          ),
          material: (_, _) => const SizedBox(width: 8),
        ),
      ],
    ),
    body: GraphBody(scrollController: _scrollController),
  ),
);
  }

  Future<void> _handleMenuAction(String value, WorkflowsProvider workflows, BuildContext context) async {
    if (value == 'export') {
      final allWorkflows = workflows.workflows;
      final selected = await _showWorkflowSelectionDialog(context, allWorkflows);

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
        platformPageRoute(context: context, builder: (context) => const SettingsPage()),
      );
    }
  }

  Future<List<WorkflowMeta>?> _showWorkflowSelectionDialog(BuildContext context, List<WorkflowMeta> allWorkflows) async {
    final List<bool> checked = List.filled(allWorkflows.length, false);

    return showPlatformModalSheet<List<WorkflowMeta>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: isMaterial(context) ? Theme.of(context).canvasColor : CupertinoColors.systemBackground.resolveFrom(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Select Workflows to Export',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: allWorkflows.length,
                    itemBuilder: (_, i) => CheckboxListTile(
                      title: Text(allWorkflows[i].name),
                      value: checked[i],
                      onChanged: (v) => setState(() => checked[i] = v ?? false),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PlatformTextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 16),
                      PlatformElevatedButton(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WorkflowsDrawer extends StatefulWidget {
  const WorkflowsDrawer({super.key});

  @override
  State<WorkflowsDrawer> createState() => _WorkflowsDrawerState();
}

class _WorkflowsDrawerState extends State<WorkflowsDrawer> {
  String? _editingWorkflowId;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _startEditing(String id) {
    setState(() {
      _editingWorkflowId = id;
    });
    // Scroll to the bottom to ensure the new workflow is visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
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
          return PlatformAlertDialog(
            title: const Text("Delete Workflow"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Are you sure you want to delete '$workflowName'?"),
                const SizedBox(height: 16),
                Material(
                  color: Colors.transparent,
                  child: Row(
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
                ),
              ],
            ),
            actions: [
              PlatformDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              PlatformDialogAction(
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
    
    Widget content(BuildContext context) => Column(
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
                controller: _scrollController,
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
                            final provider = context.read<WorkflowsProvider>();
                            if (newName.trim().isNotEmpty) {
                              provider.updateWorkflowName(workflow.id, newName.trim());
                            }
                            // If this workflow isn't current yet, switch to it now
                            if (provider.currentWorkflowId != workflow.id) {
                              provider.switchWorkflow(workflow.id);
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
                      workflowsProvider.switchWorkflow(workflow.id);
                      Navigator.pop(context);
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
                      Navigator.pop(context);
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
                // createNewWorkflow switches to the new workflow and notifies listeners.
                // We do NOT close the sheet — we let the user name it first.
                final newId = workflowsProvider.createNewWorkflow(switchToNew: false);
                _startEditing(newId);
              },
            ),
            const SizedBox(height: 8),
          ],
        );

    return PlatformWidget(
      material: (context, _) => Drawer(child: SafeArea(child: content(context))),
      cupertino: (context, _) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(child: content(context)),
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
    return PlatformTextField(
      controller: _controller,
      focusNode: _focusNode,
      onSubmitted: (_) => _submit(),
      onTapOutside: (_) => _submit(),
      material: (_, _) => MaterialTextFieldData(
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
        ),
      ),
      cupertino: (_, _) => CupertinoTextFieldData(
        padding: EdgeInsets.zero,
        decoration: null,
      ),
      style: const TextStyle(fontSize: 16),
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
    return PlatformTextField(
      controller: _controller,
      focusNode: _focusNode..skipTraversal = true,
      material: (_, _) => MaterialTextFieldData(
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
      ),
      cupertino: (_, _) => CupertinoTextFieldData(
        placeholder: "Search nodes (Regex)...",
        placeholderStyle: const TextStyle(color: Colors.grey),
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        prefix: const Padding(
          padding: EdgeInsets.only(left: 8.0),
          child: Icon(CupertinoIcons.search, color: Colors.grey, size: 20),
        ),
        suffix: _controller.text.isNotEmpty
            ? PlatformIconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(CupertinoIcons.clear_circled_solid, color: Colors.grey, size: 20),
                onPressed: () {
                  _controller.clear();
                  var graph = context.read<GraphProvider>();
                  var uiState = context.read<UIStateProvider>();
                  uiState.clearSearch(graph);
                  FocusScope.of(context).unfocus();
                },
              )
            : null,
        decoration: null,
      ),
      onChanged: _onChanged,
      style: const TextStyle(fontSize: 16),
    );
  }
}