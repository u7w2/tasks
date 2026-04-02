import 'package:flutter/material.dart';
import 'graph_provider.dart';

class UIStateProvider extends ChangeNotifier {
  bool _isEditMode = false;
  bool get isEditMode => _isEditMode;

  final Set<CategoryNode> _selectedNodes = {};
  Set<CategoryNode> get selectedNodes => _selectedNodes;

  CategoryNode? _editingNode;
  CategoryNode? get editingNode => _editingNode;

  void startEditing(CategoryNode node) {
    _editingNode = node;
    notifyListeners();
  }

  void stopEditing() {
    _editingNode = null;
    notifyListeners();
  }

  Map<String, int>? _snapshotDepths;
  final Map<String, GlobalKey> _nodeKeys = {};

  GlobalKey getNodeKey(String uuid) {
    _nodeKeys.putIfAbsent(uuid, () => GlobalKey());
    return _nodeKeys[uuid]!;
  }

  void setEditMode(bool value, GraphProvider graph) {
    if (_isEditMode == value) return;
    _isEditMode = value;
    if (_isEditMode) {
      // Freeze columns by taking a snapshot of all depths
      _snapshotDepths = {};
      for (var node in graph.getAllNodes()) {
        _snapshotDepths![node.uuid] = node.depth ?? 0;
      }
    } else {
      // Unfreeze
      _snapshotDepths = null;
      _selectedNodes.clear();
    }
    notifyListeners();
  }

  void toggleEditMode(GraphProvider graph) {
    setEditMode(!_isEditMode, graph);
  }

  int getDisplayDepth(CategoryNode node) {
    if (_isEditMode && _snapshotDepths != null) {
      return _snapshotDepths![node.uuid] ?? (node.depth ?? 0);
    }
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

  void longPressSelect(CategoryNode node) {
    _selectPathRecursive(node);
    notifyListeners();
  }

  void _selectPathRecursive(CategoryNode node) {
    if (_selectedNodes.contains(node)) return; 
    _selectedNodes.add(node);
    for (var parent in node.parents) {
      _selectPathRecursive(parent);
    }
    for (var child in node.children) {
      _selectPathRecursive(child);
    }
  }

  bool isSelected(CategoryNode node) {
    return _selectedNodes.contains(node);
  }
}
