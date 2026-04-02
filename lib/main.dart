import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'graph_provider.dart';
import 'ui_state_provider.dart';
import 'widgets/depth_column.dart';
import 'widgets/line_painter.dart';

void main() {
  runApp(const TasksApp());
}

class TasksApp extends StatelessWidget {
  const TasksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => GraphProvider()),
        ChangeNotifierProvider(create: (context) => UIStateProvider()),
      ],
      child: MaterialApp(
        title: "Tasks",
        theme: ThemeData.dark(),
        home: const TasksScreen(),
      ),
    );
  }
}

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var graph = context.watch<GraphProvider>();
    var uiState = context.watch<UIStateProvider>();

    bool hasActiveState = uiState.selectedNodes.isNotEmpty || uiState.editingNode != null;

    return PopScope(
      canPop: !hasActiveState,
      onPopInvokedWithResult: (didPop, dynamic result) {
        if (didPop) return;
        uiState.clearSelection();
        if (uiState.editingNode != null) uiState.stopEditing();
      },
      child: Scaffold(
        appBar: AppBar(
        title: const Text("Tasks"),
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
                // To avoid concurrent modification issues while deleting
                var nodesToDelete = uiState.selectedNodes.toList();
                for (var node in nodesToDelete) {
                  graph.removeNode(node);
                }
                uiState.clearSelection();
              },
            ),
          const SizedBox(width: 16),
          Row(
            children: [
              Text(uiState.isEditMode ? "Edit Mode" : "View Mode"),
              Switch(
                value: uiState.isEditMode,
                onChanged: (_) => context.read<UIStateProvider>().toggleEditMode(graph),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          var newNode = graph.addNode("New Task");
          uiState.setEditMode(true, graph);
          uiState.startEditing(newNode);
        },
      ),
      body: GraphBody(),
    ));
  }
}

class GraphBody extends StatefulWidget {
  const GraphBody({super.key});

  @override
  State<GraphBody> createState() => _GraphBodyState();
}

class _GraphBodyState extends State<GraphBody> {
  final ScrollController _scrollController = ScrollController();
  bool _needsRepaint = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var graph = context.watch<GraphProvider>();
    var uiState = context.watch<UIStateProvider>();

    Map<int, List<CategoryNode>> depthMap = {};
    for (var node in graph.getAllNodes()) {
      int depth = uiState.getDisplayDepth(node);
      depthMap.putIfAbsent(depth, () => []).add(node);
    }
    
    List<int> sortedDepths = depthMap.keys.toList()..sort();

    if (_needsRepaint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() { _needsRepaint = false; });
        }
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double screenWidth = constraints.maxWidth;
        double scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
        double defaultColWidth = 120.0;
        
        // Focus mode handled below dynamically

        return GestureDetector(
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
              controller: _scrollController,
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
        ));
      }
    );
  }
}
