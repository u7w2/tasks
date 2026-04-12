
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'storage_service.dart';
import 'dart:collection';

class CategoryNode {
  static const _uuidGenerator = Uuid();
  final String uuid;

  final Set<CategoryNode> children;
  final Set<CategoryNode> parents;

  String name;
  String? description;

  int? depth;

  CategoryNode(
    this.name, {
    this.description,
    String? uuid,
    Set<CategoryNode>? children,
    Set<CategoryNode>? parents,
  }) : uuid = uuid ?? _uuidGenerator.v4(),
       children = children ?? {},  
       parents = parents ?? {};
}

class GraphProvider extends ChangeNotifier {
  final Set<CategoryNode> _rootNodes;
  Set<CategoryNode> get rootNodes => Set.unmodifiable(_rootNodes);

  final String id;
  bool _isLoaded = false;

  GraphProvider({required this.id, Set<CategoryNode>? rootNodes})
    : _rootNodes = rootNodes ?? {} {
    if (_rootNodes.isEmpty) {
      loadGraph();
    } else {
      // Nodes were provided directly — no async load needed
      _isLoaded = true;
    }
  }

  Future<void> saveGraph() async {
    // Guard: don't overwrite persisted data before loadGraph() has completed
    if (!_isLoaded) return;
    
    List<Map<String, dynamic>> nodesJson = [];
    List<Map<String, String>> edgesJson = [];

    for (var node in getAllNodes()) {
      nodesJson.add({
        'uuid': node.uuid,
        'name': node.name,
        'description': node.description,
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
    
    await StorageService().saveGraphData(id, data);
  }

  Future<void> loadGraph() async {
    Map<String, dynamic>? data = await StorageService().loadGraphData(id);
    if (data == null) {
      _isLoaded = true;
      return;
    }
    
    try {
      List<dynamic> nodesJson = data['nodes'];
      List<dynamic> edgesJson = data['edges'];
      
      Map<String, CategoryNode> directory = {};
      
      for (var json in nodesJson) {
        var node = CategoryNode(
          json['name'].toString(),
          uuid: json['uuid']?.toString(),
          description: json['description']?.toString(),
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
    } finally {
      _isLoaded = true;
    }
  }

  CategoryNode addNode(
    String name, {
    String? description,
    Set<CategoryNode>? parents,
    Set<CategoryNode>? children,
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
    updateDepths({node});
    saveGraph();
    return node;
  }

  void removeNodes(Set<CategoryNode> nodes) {
    if (nodes.isEmpty) return;
    
    final Set<CategoryNode> nodesToUpdate = {};
    
    for (var node in nodes) {
      _rootNodes.remove(node);
      
      final parents = Set<CategoryNode>.from(node.parents);
      final children = Set<CategoryNode>.from(node.children);
      
      for (var parent in parents) {
        parent.children.remove(node);
      }
      
      for (var child in children) {
        child.parents.remove(node);
        if (!nodes.contains(child)) {
          nodesToUpdate.add(child);
          if (child.parents.isEmpty) {
            _rootNodes.add(child);
          }
        }
      }
      
      for (var parent in parents) {
        if (nodes.contains(parent)) continue;
        for (var child in children) {
          if (nodes.contains(child)) continue;
          
          if (!parent.children.contains(child)) {
            parent.children.add(child);
            child.parents.add(parent);
            _rootNodes.remove(child);
            nodesToUpdate.add(child);
          }
        }
      }
      
      // Clear relationships on the deleted node
      node.parents.clear();
      node.children.clear();
    }
    
    updateDepths(nodesToUpdate.isEmpty ? _rootNodes : nodesToUpdate);
    saveGraph();
  }

  void addLink(CategoryNode parent, CategoryNode child) {
    if (!parent.children.contains(child)) { parent.children.add(child); }
    if (!child.parents.contains(parent)) { child.parents.add(parent); }
    child.parents.isEmpty ? _rootNodes.add(child) : _rootNodes.remove(child);
    updateDepths({child});
    saveGraph();
  }

  void removeLink(CategoryNode nodeA, CategoryNode nodeB) {
    CategoryNode? parent;
    CategoryNode? child;

    if (nodeA.children.contains(nodeB)) {
      parent = nodeA; child = nodeB;
    } else if (nodeB.children.contains(nodeA)) {
      parent = nodeB; child = nodeA;
    }

    if (parent != null && child != null) {
      parent.children.remove(child);
      child.parents.remove(parent);
      if (child.parents.isEmpty) { _rootNodes.add(child); }
      updateDepths({child});
      saveGraph();
    }
  }

  void updateNode(CategoryNode node, {String? name, String? description}) {
    if (name != null) { node.name = name; }
    if (description != null) { node.description = description; }
    notifyListeners();
    saveGraph();
  }

  void updateDepths(Set<CategoryNode> nodes) {
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

  Set<CategoryNode> getAllNodes() {
    Set<CategoryNode> allNodes = {};
    List<CategoryNode> queue = List.from(_rootNodes);
    
    int i = 0;
    while (i < queue.length) {
      CategoryNode node = queue[i++];
      if (allNodes.add(node)) {
        queue.addAll(node.children);
      }
    }
    return allNodes;
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
