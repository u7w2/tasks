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

  /// Imports a workflow from a JSON string, returns a mapped meta object representing the new workflow mapping
  Future<WorkflowMeta?> importWorkflow(String jsonString) async {
    try {
      Map<String, dynamic> parsed = jsonDecode(jsonString);
      
      // Check for required components
      if (!parsed.containsKey('workflow') || !parsed.containsKey('graph')) {
        debugPrint("Import failed: Missing 'workflow' or 'graph' data.");
        return null;
      }
      
      // We can use this version number later to migrate data if the format changes
      int version = parsed['schema_version'] ?? 0;
      debugPrint("Importing workflow with schema version: $version");

      Map<String, dynamic> metaJson = parsed['workflow'];
      Map<String, dynamic> graphData = parsed['graph'];
      
      String newId = const Uuid().v4();
      
      String baseName = metaJson['name'] ?? 'Imported Workflow';
      WorkflowMeta meta = WorkflowMeta(id: newId, name: baseName);
      
      // Save the graph data immediately under the new ID
      await saveGraphData(newId, graphData);
      
      return meta;
    } catch (e) {
      debugPrint("Error importing workflow: $e");
      return null;
    }
  }
}
