import 'dart:async';
import 'package:flutter/material.dart';
import 'graph_provider.dart';

class UIStateProvider extends ChangeNotifier {
  final Set<CategoryNode> _selectedNodes = {};
  Set<CategoryNode> get selectedNodes => _selectedNodes;

  CategoryNode? _editingNode;
  CategoryNode? get editingNode => _editingNode;

  final Set<String> _errorNodes = {};
  bool isErrorNode(CategoryNode node) => _errorNodes.contains(node.uuid);

  void flashError(List<CategoryNode> nodes) {
    for (var node in nodes) {
      _errorNodes.add(node.uuid);
    }
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 1500), () {
      for (var node in nodes) {
        _errorNodes.remove(node.uuid);
      }
      notifyListeners();
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

  int getDisplayDepth(CategoryNode node) {
    return node.depth ?? 0;
  }

  void toggleSelection(CategoryNode node) {
    if (_selectedNodes.contains(node)) {
      _selectedNodes.remove(node);
    } else {
      _selectedNodes.add(node);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedNodes.clear();
    notifyListeners();
  }

  void ensureSelected(CategoryNode node) {
    if (!_selectedNodes.contains(node)) {
      _selectedNodes.add(node);
      notifyListeners();
    }
  }

  void doubleTapSelect(CategoryNode node) {
    if (!_selectedNodes.contains(node)) {
      _selectedNodes.add(node);
    }
    _addAncestors(node);
    _addDescendants(node);
    notifyListeners();
  }

  void tripleTapSelect(CategoryNode node) {
    Set<CategoryNode> visited = {};
    _floodFillRecursive(node, visited);
    notifyListeners();
  }

  void _floodFillRecursive(CategoryNode node, Set<CategoryNode> visited) {
    if (visited.contains(node)) return; 
    visited.add(node);
    _selectedNodes.add(node);
    for (var parent in node.parents) {
      _floodFillRecursive(parent, visited);
    }
    for (var child in node.children) {
      _floodFillRecursive(child, visited);
    }
  }

  void _addAncestors(CategoryNode node) {
    for (var parent in node.parents) {
      if (!_selectedNodes.contains(parent)) {
        _selectedNodes.add(parent);
        _addAncestors(parent);
      }
    }
  }

  void _addDescendants(CategoryNode node) {
    for (var child in node.children) {
      if (!_selectedNodes.contains(child)) {
        _selectedNodes.add(child);
        _addDescendants(child);
      }
    }
  }

  bool isSelected(CategoryNode node) {
    return _selectedNodes.contains(node);
  }
}
