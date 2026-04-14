import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'workflows_provider.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  /// Loads the list of workflows metadata
  Future<List<WorkflowMeta>> loadWorkflows() async {
    final prefs = await SharedPreferences.getInstance();
    String? workflowsJson = prefs.getString('workflows_list');
    if (workflowsJson != null) {
      try {
        List<dynamic> decoded = jsonDecode(workflowsJson);
        return decoded.map((e) => WorkflowMeta.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (e) {
        debugPrint("Error loading workflows: $e");
      }
    }
    return [];
  }

  /// Loads the currently active workflow ID
  Future<String?> loadActiveWorkflowId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('workflows_active_id');
  }

  /// Saves the list of workflows and active ID
  Future<void> saveWorkflows(List<WorkflowMeta> workflows, String? activeId) async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> jsonList = workflows.map((w) => w.toJson()).toList();
    await prefs.setString('workflows_list', jsonEncode(jsonList));
    if (activeId != null) {
      await prefs.setString('workflows_active_id', activeId);
    }
  }

  /// Loads graph data (nodes and edges) for a specific workflow
  Future<Map<String, dynamic>?> loadGraphData(String workflowId) async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('tasks_graph_data_$workflowId');
    if (jsonString != null) {
      try {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        debugPrint("Error loading graph data for $workflowId: $e");
      }
    }
    return null;
  }

  /// Saves graph data for a specific workflow
  Future<void> saveGraphData(String workflowId, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tasks_graph_data_$workflowId', jsonEncode(data));
  }

  /// Deletes graph data
  Future<void> deleteGraphData(String workflowId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tasks_graph_data_$workflowId');
  }

  /// Exports a workflow and its graph data into a single combined JSON string
  Future<String> exportWorkflow(WorkflowMeta meta) async {
    Map<String, dynamic> graphData = await loadGraphData(meta.id) ?? {'nodes': [], 'edges': []};
    
    Map<String, dynamic> exportData = {
      'schema_version': "0.2.1",
      'workflow': meta.toJson(),
      'graph': graphData,
    };
    
    return jsonEncode(exportData);
  }

  /// Exports multiple workflows into a single combined JSON string
  Future<String> exportWorkflows(List<WorkflowMeta> metas) async {
    List<Map<String, dynamic>> workflowsData = [];
    for (var meta in metas) {
      Map<String, dynamic> graphData = await loadGraphData(meta.id) ?? {'nodes': [], 'edges': []};
      workflowsData.add({'workflow': meta.toJson(), 'graph': graphData});
    }
    return jsonEncode({'schema_version': "0.3.0", 'workflows': workflowsData});
  }

  /// Imports a workflow from a JSON string — supports both single and multi-workflow formats.
  /// Returns a list of imported WorkflowMeta objects.
  Future<List<WorkflowMeta>> importWorkflows(String jsonString) async {
    try {
      Map<String, dynamic> parsed = jsonDecode(jsonString);
      List<WorkflowMeta> results = [];

      if (parsed.containsKey('workflows')) {
        // Multi-workflow format (schema 0.3.0+)
        for (var wd in parsed['workflows'] as List) {
          final meta = await _importSingle(wd['workflow'], wd['graph']);
          if (meta != null) results.add(meta);
        }
      } else if (parsed.containsKey('workflow') && parsed.containsKey('graph')) {
        // Legacy single-workflow format
        final meta = await _importSingle(parsed['workflow'], parsed['graph']);
        if (meta != null) results.add(meta);
      } else {
        debugPrint("Import failed: unrecognised format.");
      }
      return results;
    } catch (e) {
      debugPrint("Error importing workflows: $e");
      return [];
    }
  }

  Future<WorkflowMeta?> _importSingle(Map<String, dynamic> metaJson, Map<String, dynamic> graphData) async {
    try {
      String newId = const Uuid().v4();
      String baseName = metaJson['name'] ?? 'Imported Workflow';
      WorkflowMeta meta = WorkflowMeta(id: newId, name: baseName);
      await saveGraphData(newId, graphData);
      return meta;
    } catch (e) {
      debugPrint("Error saving imported graph: $e");
      return null;
    }
  }

  /// Legacy single-workflow import — kept for backwards compatibility.
  Future<WorkflowMeta?> importWorkflow(String jsonString) async {
    final results = await importWorkflows(jsonString);
    return results.isNotEmpty ? results.first : null;
  }
}
