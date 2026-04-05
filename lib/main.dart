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
    var graph = context.watch<GraphProvider>();
    var uiState = context.watch<UIStateProvider>();

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
                // To avoid concurrent modification issues while deleting
                var nodesToDelete = uiState.selectedNodes.toList();
                for (var node in nodesToDelete) {
                  graph.removeNode(node);
                }
                uiState.clearSelection();
              },
            ),
          const SizedBox(width: 16),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          var newNode = graph.addNode("New Task");
          uiState.clearSelection();
          uiState.toggleSelection(newNode);
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
        double defaultColWidth = 120.0;
        int extraCols = sortedDepths.length > 1 ? sortedDepths.length - 1 : 0;
        double calculatedMaxScroll = extraCols * defaultColWidth;
        
        double rawScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
        double scrollOffset = rawScrollOffset.clamp(0.0, calculatedMaxScroll);
        
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

class _SearchBar extends StatefulWidget {
  const _SearchBar();

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final TextEditingController _controller = TextEditingController();

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
