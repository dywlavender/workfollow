import '../../../models/task.dart';

/// One flattened row of the task list's parent/child tree.
///
/// The projection turns grouped root tasks into the exact row order the list
/// renders — a parent followed by its visible children — so the UI never
/// walks `parentTaskId` itself. Depth is 0 for roots and 1 for children
/// (single-level nesting for now; the shape allows deeper trees later).
class TaskTreeNode {
  const TaskTreeNode({
    required this.task,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
  });

  final TaskItem task;
  final int depth;
  final bool hasChildren;
  final bool expanded;
}

/// Flattens [roots] into tree rows. Children are read through [childrenOf]
/// (the hierarchy's single authority), visibility through [isExpanded] —
/// a collapsed parent still owns its children in data, it just stops
/// emitting their rows.
List<TaskTreeNode> taskTreeNodes({
  required Iterable<TaskItem> roots,
  required List<TaskItem> Function(String parentId) childrenOf,
  required bool Function(String taskId) hasChildren,
  required bool Function(String taskId) isExpanded,
  int maxDepth = 1,
}) {
  final nodes = <TaskTreeNode>[];
  void walk(TaskItem task, int depth) {
    final parentHasChildren = hasChildren(task.id);
    final expanded =
        depth < maxDepth && parentHasChildren && isExpanded(task.id);
    nodes.add(TaskTreeNode(
        task: task,
        depth: depth,
        hasChildren: parentHasChildren,
        expanded: expanded));
    if (expanded) {
      for (final child in childrenOf(task.id)) {
        walk(child, depth + 1);
      }
    }
  }

  for (final root in roots) {
    walk(root, 0);
  }
  return nodes;
}
