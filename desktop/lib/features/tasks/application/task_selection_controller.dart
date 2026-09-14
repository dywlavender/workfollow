/// Selection state is intentionally independent of Flutter widgets. The
/// workspace facade can still expose its legacy getters while all keyboard,
/// range and multi-select behavior goes through this object.
class TaskSelectionController {
  String? selectedTaskId;
  String? anchorTaskId;
  final Set<String> multiSelectedTaskIds = <String>{};

  bool isSelected(String id) => selectedTaskId == id;
  bool isMultiSelected(String id) => multiSelectedTaskIds.contains(id);

  void select(String? id) {
    selectedTaskId = id;
    if (id != null) anchorTaskId = id;
  }

  void clear() {
    selectedTaskId = null;
    anchorTaskId = null;
  }

  void clearMulti() {
    multiSelectedTaskIds.clear();
    anchorTaskId = null;
  }

  void toggleMulti(String id) {
    if (!multiSelectedTaskIds.add(id)) multiSelectedTaskIds.remove(id);
    anchorTaskId = id;
  }

  void extendTo(String id, List<String> projectionOrder) {
    final anchor = anchorTaskId;
    final anchorIndex = anchor == null ? -1 : projectionOrder.indexOf(anchor);
    final targetIndex = projectionOrder.indexOf(id);
    if (anchorIndex < 0 || targetIndex < 0) {
      multiSelectedTaskIds.add(id);
      return;
    }
    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    for (var index = start; index <= end; index++) {
      multiSelectedTaskIds.add(projectionOrder[index]);
    }
  }

  String? adjacent(String id, int delta, List<String> projectionOrder) {
    if (delta == 0) return selectedTaskId;
    final index = projectionOrder.indexOf(id);
    if (index < 0) return null;
    final target = index + delta;
    if (target < 0 || target >= projectionOrder.length) return null;
    clearMulti();
    select(projectionOrder[target]);
    return selectedTaskId;
  }
}
