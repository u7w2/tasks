import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:collection';

class CategoryNode {
  static const _uuidGenerator = Uuid();
  final String uuid;

  final List<CategoryNode> children;
  final List<CategoryNode> parents;

  String name;
  String? description;

  int? depth;

  CategoryNode(
    this.name, {
    this.description,
    String? uuid,
    List<CategoryNode>? children,
    List<CategoryNode>? parents,
    int? depth,
  }) : uuid = uuid ?? _uuidGenerator.v4(),
       children = children ?? [],
       parents = parents ?? [];
}

class GraphProvider extends ChangeNotifier {
  final List<CategoryNode> _rootNodes;
  List<CategoryNode> get rootNodes => List.unmodifiable(_rootNodes);

  GraphProvider({List<CategoryNode>? rootNodes})
    : _rootNodes = rootNodes ?? [] {
    for (CategoryNode node in _rootNodes) {
      node.parents.clear();
    }
    if (_rootNodes.isEmpty) {
      loadGraph();
    }
  }

  Future<void> saveGraph() async {
    final prefs = await SharedPreferences.getInstance();
    
    List<Map<String, dynamic>> nodesJson = [];
    List<Map<String, String>> edgesJson = [];
    
    for (var node in getAllNodes()) {
      nodesJson.add({
        'uuid': node.uuid,
        'name': node.name,
        'description': node.description,
        'depth': node.depth,
      });
      for (var child in node.children) {
        edgesJson.add({
          'parent': node.uuid,
          'child': child.uuid,
        });
      }
    }
    
    Map<String, dynamic> data = {
      'nodes': nodesJson,
      'edges': edgesJson,
    };
    
    await prefs.setString('tasks_graph_data', jsonEncode(data));
  }

  Future<void> loadGraph() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('tasks_graph_data');
    if (jsonString == null) return;
    
    try {
      Map<String, dynamic> data = jsonDecode(jsonString);
      List<dynamic> nodesJson = data['nodes'];
      List<dynamic> edgesJson = data['edges'];
      
      Map<String, CategoryNode> directory = {};
      
      for (var json in nodesJson) {
        var node = CategoryNode(
          json['name'],
          uuid: json['uuid'],
          description: json['description'],
          depth: json['depth'] as int?,
        );
        directory[node.uuid] = node;
      }
      
      for (var edge in edgesJson) {
        String parentId = edge['parent'];
        String childId = edge['child'];
        var parentNode = directory[parentId];
        var childNode = directory[childId];
        
        if (parentNode != null && childNode != null) {
          parentNode.children.add(childNode);
          childNode.parents.add(parentNode);
        }
      }
      
      _rootNodes.clear();
      for (var node in directory.values) {
        if (node.parents.isEmpty) {
          _rootNodes.add(node);
        }
      }
      
      updateDepths(_rootNodes);
    } catch (e) {
      debugPrint("Failed to load graph: $e");
    }
  }

  CategoryNode addNode(
    String name, {
    String? description,
    List<CategoryNode>? parents,
    List<CategoryNode>? children,
    int? index,
  }) {
    final CategoryNode node = CategoryNode(
      name,
      description: description,
      parents: parents,
      children: children,
    );
    if (parents == null) {
      _rootNodes.add(node);
    } else {
      for (CategoryNode parent in parents) {
        addLink(parent, node);
      }
    }
    updateDepths([node]);
    saveGraph();
    return node;
  }

  void removeNode(CategoryNode node) {
    // Snapshot before any mutation — removing links modifies these lists mid-iteration
    final parents = List<CategoryNode>.from(node.parents);
    final children = List<CategoryNode>.from(node.children);

    _rootNodes.remove(node);
    for (var parent in parents) { removeLink(parent, node); }
    for (var child in children) { removeLink(node, child); }

    // Reconnect: inherit edges (bypass if both being deleted — caller handles that)
    for (var parent in parents) {
      for (var child in children) { addLink(parent, child); }
    }

    // Promote stranded children to root
    if (parents.isEmpty) {
      for (var child in children) {
        if (child.parents.isEmpty && !_rootNodes.contains(child)) { _rootNodes.add(child); }
      }
    }

    // node.parents and node.children are now empty (removeLink already cleared them)
    updateDepths(parents + children);
    saveGraph();
  }

  void addLink(CategoryNode parent, CategoryNode child) {
    if (!parent.children.contains(child)) { parent.children.add(child); }
    if (!child.parents.contains(parent)) { child.parents.add(parent); }
    child.parents.isEmpty ? _rootNodes.add(child) : _rootNodes.remove(child);
    updateDepths([child]);
    saveGraph();
  }

  void removeLink(CategoryNode parent, CategoryNode child) {
    parent.children.remove(child);
    child.parents.remove(parent);
    if (child.parents.isEmpty) { _rootNodes.add(child); }
    updateDepths([child]);
    saveGraph();
  }

  void updateNode(CategoryNode node, {String? name, String? description}) {
    if (name != null) { node.name = name; }
    if (description != null) { node.description = description; }
    notifyListeners();
    saveGraph();
  }

  void updateDepths(List<CategoryNode> nodes) {
    Set<CategoryNode> descendants = {};
    final queue = Queue<CategoryNode>.from(nodes);

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      if (descendants.add(node)) { queue.addAll(node.children); }
    }

    for (CategoryNode node in descendants) { node.depth = null; }
    for (CategoryNode node in descendants) { _computeDepth(node, {}); }

    notifyListeners();
  }

  int _computeDepth(CategoryNode node, Set<CategoryNode> visiting) {
    if (node.depth != null) return node.depth!;
    
    if (visiting.contains(node)) return 0;
    if (node.parents.isEmpty) {
      node.depth = 0;
      return 0;
    }

    visiting.add(node);
    
    int maxDepth = 0;
    for (CategoryNode parent in node.parents) {
      int d = _computeDepth(parent, visiting);
      if (d > maxDepth) { maxDepth = d; }
    }
    
    visiting.remove(node);
    
    node.depth = maxDepth + 1;
    return node.depth!;
  }

  bool wouldCreateCycle(CategoryNode parent, CategoryNode child) {
    if (parent == child) return true;
    
    Set<CategoryNode> visiting = {};
    List<CategoryNode> queue = [child];
    int head = 0;
    
    while (head < queue.length) {
      CategoryNode current = queue[head++];
      if (current == parent) return true;
      if (visiting.add(current)) {
        queue.addAll(current.children);
      }
    }
    return false;
  }

  List<CategoryNode> getAllNodes() {
    Set<CategoryNode> allNodes = {};
    List<CategoryNode> queue = List.from(_rootNodes);
    
    int i = 0;
    while (i < queue.length) {
      CategoryNode node = queue[i++];
      if (allNodes.add(node)) {
        queue.addAll(node.children);
      }
    }
    return allNodes.toList();
  }

  int countTotalDependencies(CategoryNode node) {
    Set<CategoryNode> visited = {};
    List<CategoryNode> queue = List.from(node.parents);
    int head = 0;
    while (head < queue.length) {
      CategoryNode current = queue[head++];
      if (visited.add(current)) {
        queue.addAll(current.parents);
      }
    }
    return visited.length;
  }

  int countTotalDependents(CategoryNode node) {
    Set<CategoryNode> visited = {};
    List<CategoryNode> queue = List.from(node.children);
    int head = 0;
    while (head < queue.length) {
      CategoryNode current = queue[head++];
      if (visited.add(current)) {
        queue.addAll(current.children);
      }
    }
    return visited.length;
  }
}
