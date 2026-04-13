import 'dart:async';
import 'package:flutter/material.dart';
import 'graph_provider.dart';

class UIStateProvider extends ChangeNotifier {
  CategoryNode? _editingNode;
  CategoryNode? get editingNode => _editingNode;

  final Set<String> _errorNodes = {};
  bool isErrorNode(CategoryNode node) => _errorNodes.contains(node.uuid);

  void flashError(List<CategoryNode> nodes) {
    for (var node in nodes) { _errorNodes.add(node.uuid); }
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 1500), () {
      for (var node in nodes) { _errorNodes.remove(node.uuid); }
      if (hasListeners) notifyListeners();
    });
  }

  void startEditing(CategoryNode node) {
    _editingNode = node;
    notifyListeners();
  }

  void stopEditing() {
    _editingNode = null;
    notifyListeners();
  }

  final Map<String, GlobalKey> _nodeKeys = {};

  GlobalKey getNodeKey(String uuid) {
    _nodeKeys.putIfAbsent(uuid, () => GlobalKey());
    return _nodeKeys[uuid]!;
  }

  bool _isDragging = false;
  bool get isDragging => _isDragging;

  CategoryNode? _hoverTarget;
  CategoryNode? get hoverTarget => _hoverTarget;

  void setHoverTarget(CategoryNode? target) {
    if (_hoverTarget != target) {
      _hoverTarget = target;
      notifyListeners();
    }
  }

  void clearHoverTarget() {
    if (_hoverTarget != null) {
      _hoverTarget = null;
      notifyListeners();
    }
  }

  final Set<CategoryNode> _invalidDragTargets = {};
  Set<CategoryNode> get invalidDragTargets => _invalidDragTargets;

  void startDragging(List<CategoryNode> draggedNodes, GraphProvider graph) {
    _isDragging = true;
    _invalidDragTargets.clear();
    
    for (var candidate in graph.getAllNodes()) {
      bool invalid = false;
      for (var dragged in draggedNodes) {
        bool hasDirectLink = candidate.children.contains(dragged) || dragged.children.contains(candidate);
        if (!hasDirectLink && graph.wouldCreateCycle(candidate, dragged)) {
          invalid = true;
          break;
        }
      }
      if (invalid) {
        _invalidDragTargets.add(candidate);
      }
    }
    notifyListeners();
  }

  void stopDragging() {
    _isDragging = false;
    _invalidDragTargets.clear();
    notifyListeners();
  }

  String _searchQuery = "";
  String get searchQuery => _searchQuery;

  void searchNodes(String query, GraphProvider graph) {
    _searchQuery = query;
    graph.clearSelection();
    if (query.isNotEmpty) {
      try {
        final regex = RegExp(query, caseSensitive: false);
        Set<CategoryNode> matches = {};
        for (var node in graph.getAllNodes()) {
          if (regex.hasMatch(node.name)) {
            matches.add(node);
          }
        }
        graph.selectNodes(matches);
      } catch (e) {
        // Ignore invalid regex until user completes typing
      }
    }
    notifyListeners();
  }

  void clearSearch(GraphProvider graph) {
    _searchQuery = "";
    graph.clearSelection();
    notifyListeners();
  }
}
