import 'dart:convert';

import 'task.dart';

/// Quill is the editable source. A ProseMirror projection travels with it so
/// existing workspace exports remain readable by the Web editor.
List<Map<String, dynamic>> noteDocumentDelta(NoteItem note) {
  final document = note.contentJson;
  final stored = document?['quillDelta'];
  if (stored is List)
    return stored
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  if (document == null || document.isEmpty)
    return proseMirrorToDelta(
        noteContentJsonFromPlainText(note.plainText ?? note.preview));
  return proseMirrorToDelta(document);
}

List<Map<String, dynamic>> proseMirrorToDelta(Map<String, dynamic> document) {
  final ops = <Map<String, dynamic>>[];
  void insert(Object value, [Map<String, dynamic> attrs = const {}]) {
    if (value == '') return;
    ops.add({'insert': value, if (attrs.isNotEmpty) 'attributes': attrs});
  }

  Map<String, dynamic> marks(Object? value) {
    final result = <String, dynamic>{};
    if (value is! List) return result;
    for (final mark in value.whereType<Map>()) {
      final type = mark['type'], attrs = mark['attrs'];
      switch (type) {
        case 'bold':
          result['bold'] = true;
        case 'italic':
          result['italic'] = true;
        case 'underline':
          result['underline'] = true;
        case 'strike':
          result['strike'] = true;
        case 'code':
          result['code'] = true;
        case 'link':
          if (attrs is Map && attrs['href'] != null)
            result['link'] = attrs['href'];
        case 'subscript':
          result['script'] = 'sub';
        case 'superscript':
          result['script'] = 'super';
        case 'textStyle':
          if (attrs is Map && attrs['color'] != null)
            result['color'] = attrs['color'];
        case 'highlight':
          result['background'] =
              attrs is Map ? attrs['color'] ?? '#fff3a3' : '#fff3a3';
      }
    }
    return result;
  }

  void inline(Object? raw) {
    if (raw is! Map) return;
    if (raw['type'] == 'text') {
      insert(raw['text'] ?? '', marks(raw['marks']));
      return;
    }
    if (raw['type'] == 'hardBreak') {
      insert('\n');
      return;
    }
    if (raw['type'] == 'image') {
      insert({'image': (raw['attrs'] as Map?)?['src'] ?? ''});
      return;
    }
    final children = raw['content'];
    if (children is List) {
      for (final child in children) {
        inline(child);
      }
    }
  }

  void block(Object? raw, [Map<String, dynamic> inherited = const {}]) {
    if (raw is! Map) return;
    final node = Map<String, dynamic>.from(raw);
    final type = node['type'];
    final children =
        node['content'] is List ? node['content'] as List : const [];
    final attrs = node['attrs'] is Map
        ? Map<String, dynamic>.from(node['attrs'])
        : <String, dynamic>{};
    switch (type) {
      case 'doc':
        for (final child in children) {
          block(child);
        }
      case 'paragraph':
      case 'heading':
        for (final child in children) {
          inline(child);
        }
        insert('\n', {
          ...inherited,
          if (type == 'heading') 'header': attrs['level'] ?? 1,
          if (attrs['textAlign'] != null && attrs['textAlign'] != 'left')
            'align': attrs['textAlign']
        });
      case 'bulletList':
      case 'orderedList':
      case 'taskList':
        for (final child in children) {
          if (child is! Map) continue;
          final itemAttrs = child['attrs'];
          final itemChildren =
              child['content'] is List ? child['content'] as List : const [];
          final style = type == 'orderedList'
              ? 'ordered'
              : type == 'taskList'
                  ? (itemAttrs is Map && itemAttrs['checked'] == true
                      ? 'checked'
                      : 'unchecked')
                  : 'bullet';
          for (final content in itemChildren) {
            if (content is Map &&
                const ['bulletList', 'orderedList', 'taskList']
                    .contains(content['type'])) {
              block(content,
                  {'indent': ((inherited['indent'] as int?) ?? 0) + 1});
            } else {
              block(content, {...inherited, 'list': style});
            }
          }
        }
      case 'blockquote':
        for (final child in children) {
          block(child, {...inherited, 'blockquote': true});
        }
      case 'codeBlock':
        final text = children
            .map((child) => child is Map ? child['text'] ?? '' : '')
            .join();
        for (final line in text.split('\n')) {
          insert(line);
          insert('\n', {'code-block': true});
        }
      case 'image':
        insert({'image': attrs['src'] ?? ''});
        insert('\n');
      default:
        // Tables and other imported blocks stay intact as embedded nodes.
        insert({'workfollow-block': jsonEncode(node)});
        insert('\n');
    }
  }

  block(document);
  if (ops.isEmpty ||
      !(ops.last['insert'] is String &&
          (ops.last['insert'] as String).endsWith('\n'))) insert('\n');
  return ops;
}

Map<String, dynamic> noteContentFromDelta(List<dynamic> delta) {
  final blocks = <Map<String, dynamic>>[];
  var inline = <Map<String, dynamic>>[];
  Map<String, dynamic>? list;
  String? listType;

  List<Map<String, dynamic>> marks(Map attrs) => [
        for (final name in ['bold', 'italic', 'underline', 'strike', 'code'])
          if (attrs[name] == true) {'type': name},
        if (attrs['link'] != null)
          {
            'type': 'link',
            'attrs': {'href': attrs['link']}
          },
        if (attrs['script'] == 'sub') {'type': 'subscript'},
        if (attrs['script'] == 'super') {'type': 'superscript'},
        if (attrs['color'] != null)
          {
            'type': 'textStyle',
            'attrs': {'color': attrs['color']}
          },
        if (attrs['background'] != null)
          {
            'type': 'highlight',
            'attrs': {'color': attrs['background']}
          },
      ];
  void finish(Map attrs) {
    final block = <String, dynamic>{
      'type': attrs['header'] != null
          ? 'heading'
          : attrs['code-block'] == true
              ? 'codeBlock'
              : 'paragraph',
      if (attrs['header'] != null || attrs['align'] != null)
        'attrs': {
          if (attrs['header'] != null) 'level': attrs['header'],
          if (attrs['align'] != null) 'textAlign': attrs['align']
        },
      'content': inline
    };
    final style = attrs['list'];
    if (style != null) {
      final type = style == 'ordered'
          ? 'orderedList'
          : style == 'checked' || style == 'unchecked'
              ? 'taskList'
              : 'bulletList';
      if (list == null || listType != type) {
        list = {'type': type, 'content': <Map<String, dynamic>>[]};
        listType = type;
        blocks.add(list!);
      }
      (list!['content'] as List).add({
        'type': type == 'taskList' ? 'taskItem' : 'listItem',
        if (type == 'taskList') 'attrs': {'checked': style == 'checked'},
        'content': [block]
      });
    } else {
      list = null;
      listType = null;
      blocks.add(attrs['blockquote'] == true
          ? {
              'type': 'blockquote',
              'content': [block]
            }
          : block);
    }
    inline = [];
  }

  for (final item in delta.whereType<Map>()) {
    final inserted = item['insert'],
        attrs =
            item['attributes'] is Map ? item['attributes'] as Map : const {};
    if (inserted is String) {
      final parts = inserted.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          final styles = marks(attrs);
          inline.add({
            'type': 'text',
            'text': parts[i],
            if (styles.isNotEmpty) 'marks': styles
          });
        }
        if (i < parts.length - 1) finish(attrs);
      }
    } else if (inserted is Map) {
      if (inserted['workfollow-block'] is String) {
        final node = jsonDecode(inserted['workfollow-block'] as String);
        if (node is Map) blocks.add(Map<String, dynamic>.from(node));
      } else if (inserted['image'] != null) {
        inline.add({
          'type': 'image',
          'attrs': {'src': inserted['image']}
        });
      }
    }
  }
  if (inline.isNotEmpty) finish(const {});
  return {'type': 'doc', 'content': blocks, 'quillDelta': delta};
}
