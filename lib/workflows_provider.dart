import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'graph_provider.dart';

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

  Future<void> _loadWorkflows() async {
    final prefs = await SharedPreferences.getInstance();
    
    String? workflowsJson = prefs.getString('workflows_list');
    if (workflowsJson != null) {
      try {
        List<dynamic> decoded = jsonDecode(workflowsJson);
        _workflows = decoded.map((e) => WorkflowMeta.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (e) {
        debugPrint("Error loading workflows: $e");
      }
    }

    String? lastActiveId = prefs.getString('workflows_active_id');
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
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> jsonList = _workflows.map((w) => w.toJson()).toList();
    await prefs.setString('workflows_list', jsonEncode(jsonList));
    if (_currentWorkflowId != null) {
      await prefs.setString('workflows_active_id', _currentWorkflowId!);
    }
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
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('tasks_graph_data_$id');
      });
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
}
