import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'graph_provider.dart';
import 'storage_service.dart';

class WorkflowMeta {
  final String id;
  String name;

  WorkflowMeta({required this.id, required this.name});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  factory WorkflowMeta.fromJson(Map<String, dynamic> json) {
    return WorkflowMeta(
      id: json['id'],
      name: json['name'],
    );
  }
}

class WorkflowsProvider extends ChangeNotifier {
  List<WorkflowMeta> _workflows = [];
  List<WorkflowMeta> get workflows => List.unmodifiable(_workflows);

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  String? _currentWorkflowId;
  String? get currentWorkflowId => _currentWorkflowId;

  final Map<String, GraphProvider> _graphProviders = {};

  GraphProvider? get currentGraph {
    if (!_isLoaded) return null;
    if (_currentWorkflowId == null || !_graphProviders.containsKey(_currentWorkflowId)) return null;
    return _graphProviders[_currentWorkflowId!];
  }

  WorkflowsProvider() {
    _loadWorkflows();
  }

  final StorageService _storageService = StorageService();

  Future<void> _loadWorkflows() async {
    _workflows = await _storageService.loadWorkflows();
    String? lastActiveId = await _storageService.loadActiveWorkflowId();
    if (_workflows.isNotEmpty) {
      if (lastActiveId != null && _workflows.any((w) => w.id == lastActiveId)) {
        _currentWorkflowId = lastActiveId;
      } else {
        _currentWorkflowId = _workflows.first.id;
      }
      for (var w in _workflows) {
        _ensureGraphProvider(w.id);
      }
    } else {
      createNewWorkflow();
    }
    
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _saveWorkflows() async {
    await _storageService.saveWorkflows(_workflows, _currentWorkflowId);
  }

  void _ensureGraphProvider(String id) {
    if (!_graphProviders.containsKey(id)) {
      _graphProviders[id] = GraphProvider(
        id: id,
      );
    }
  }

  String createNewWorkflow({bool switchToNew = true}) {
    String id = const Uuid().v4();
    String name = "New Workflow";
    
    _workflows.add(WorkflowMeta(id: id, name: name));
    _ensureGraphProvider(id);
    
    if (switchToNew) {
      _currentWorkflowId = id;
    }
    _saveWorkflows();
    notifyListeners();
    return id;
  }

  void switchWorkflow(String id) {
    if (_workflows.any((w) => w.id == id) && _currentWorkflowId != id) {
      _currentWorkflowId = id;
      _saveWorkflows();
      notifyListeners();
    }
  }

  void deleteWorkflow(String id) {
    // Determine the index to fallback sensibly
    int index = _workflows.indexWhere((w) => w.id == id);
    if (index != -1) {
      _workflows.removeAt(index);
      _graphProviders.remove(id);
      
      if (_workflows.isEmpty) {
        // If entirely empty, create a new one
        createNewWorkflow();
      } else if (_currentWorkflowId == id) {
        // Switch to the previous one, or next if we were at the start
        int fallbackIndex = index > 0 ? index - 1 : 0;
        _currentWorkflowId = _workflows[fallbackIndex].id;
      }
      _saveWorkflows();
      notifyListeners();
      
      // Clean up SharedPreferences for deleted workflow
      _storageService.deleteGraphData(id);
    }
  }

  void updateWorkflowName(String id, String newName) {
    var workflow = _workflows.firstWhere((w) => w.id == id);
    if (workflow.name != newName) {
      workflow.name = newName;
      _saveWorkflows();
      notifyListeners();
    }
  }

  Future<WorkflowMeta?> importWorkflow(String jsonString) async {
    WorkflowMeta? newWorkflow = await _storageService.importWorkflow(jsonString);
    if (newWorkflow != null) {
      _workflows.add(newWorkflow);
      _currentWorkflowId = newWorkflow.id;
      _ensureGraphProvider(newWorkflow.id);
      await _saveWorkflows();
      notifyListeners();
    }
    return newWorkflow;
  }

  void moveNodes(Set<CategoryNode> nodesToMove, String targetWorkflowId) {
    if (_currentWorkflowId == null || _currentWorkflowId == targetWorkflowId) return;
    
    final sourceGraph = currentGraph;
    final targetGraph = _graphProviders[targetWorkflowId];
    if (sourceGraph == null || targetGraph == null) return;

    // 1. Identify all descendants
    Set<CategoryNode> allToMove = {};
    List<CategoryNode> queue = nodesToMove.toList();
    int head = 0;
    while (head < queue.length) {
      CategoryNode current = queue[head++];
      if (allToMove.add(current)) {
        queue.addAll(current.children);
      }
    }

    // 2. Prepare data for transfer
    // We'll store node data and internal edges (links between nodes in allToMove)
    List<Map<String, dynamic>> nodesData = [];
    List<Map<String, String>> edgesData = [];
    
    Set<String> movedUuids = allToMove.map((n) => n.uuid).toSet();

    for (var node in allToMove) {
      nodesData.add({
        'uuid': node.uuid,
        'name': node.name,
        'description': node.description,
        'sortIndex': node.sortIndex,
      });
      for (var child in node.children) {
        if (movedUuids.contains(child.uuid)) {
          edgesData.add({
            'parent': node.uuid,
            'child': child.uuid,
          });
        }
      }
    }

    // 3. Remove from source
    sourceGraph.removeNodes(allToMove);

    // 4. Add to target
    targetGraph.importNodes(nodesData, edgesData);
    
    // 5. Cleanup
    notifyListeners();
  }
}
