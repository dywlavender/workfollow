#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
parse_nibarchive.py -- read-only static parser for compiled AppKit .nib files
stored in Apple's NIBArchive v1 format (TikTick 8.0.80 detail-view resources).

Why a custom parser: these .nib files are NOT plists; `plutil` and
`ibtool --objects` both refuse them (ibtool emits only
com.apple.ibtool.errors). The container is NIBArchive, documented by the
nibarchive project (MatrixEditor). Layout used here:

    struct Header {
        char     magic[10];        // "NIBArchive"
        int32    unknown1;         // == 1 (format version)
        int32    unknown2;         // == 10
        int32    object_count;
        int32    offset_objects;
        int32    key_count;
        int32    offset_keys;
        int32    value_count;
        int32    offset_values;
        int32    class_name_count;
        int32    offset_class_names;
    };                              // 50 bytes, little endian

    vint          : 7-bit little-endian groups; the FINAL byte has bit7 set
                    (note: inverse of LEB128 continuation semantics).
    Key           : vint length + utf8 bytes.
    Value         : vint key_index, uint8 type, payload
                    type 0..10 = int8,int16,int32,int64,true,false,float,
                    double,data(vint len + bytes),nil,object_ref(int32).
    Object        : vint class_name_index, vint value_index, vint value_count
    ClassName     : vint len, vint extras_count, bytes name, int32 extras[]

Object graph (decoded from NSIBObjectData + NSConnections):
  * IBClassReference / NSClassSwapper  -> IB's placeholder class mechanism
    (NSClassName = real class, NSOriginalClassName = AppKit superclass).
  * NSClassSwapper carries the geometry: NSFrame (subview) or NSFrameSize
    (root view / auto-layout view) stored as an *NSString* such as
    "{{17, 8}, {63, 24}}" or "{480, 40}".
  * NSTextFieldCell / NSButtonCell  -> NSContents (NSString, visible text),
    NSNormalImage / NSContents -> NSCustomResource -> NSResourceName (image).
  * NSNibOutletConnector (NSSource, NSDestination, NSLabel=outlet name)
  * NSNibControlConnector (NSSource, NSDestination, NSLabel=action selector)

Everything is read-only; the script never writes next to the app and never
launches TickTick.

Usage:
  python3 parse_nibarchive.py \
      --resources /Applications/TickTick.app/Contents/Resources \
      --out ../ticktick-detail-nib-inventory.json \
      [--localizable en.lproj/Localizable.strings zh-Hans.lproj/Localizable.strings]
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import struct
import sys
from collections import Counter, OrderedDict

MAGIC = b"NIBArchive"
VALUE_TYPES = {
    0: "INT8", 1: "INT16", 2: "INT32", 3: "INT64", 4: "BOOL_TRUE",
    5: "BOOL_FALSE", 6: "FLOAT", 7: "DOUBLE", 8: "DATA", 9: "NIL",
    10: "OBJECT_REF",
}

# The 29 detail/edit-bar nibs requested for this audit (exact file names).
TARGET_NIBS = [
    "TTSingleTaskDetailViewController.nib",
    "TTTaskDetailWindowController.nib",
    "TTDetailContainerViewController.nib",
    "TTTaskDetailHolderViewController.nib",
    "TTTaskDetailTopView.nib",
    "TTTaskDetailTitleCell.nib",
    "TTTaskDetailContentCell.nib",
    "TTTaskDetailDescriptionCell.nib",
    "TTTaskDetailBottomView.nib",
    "TTTaskDetailBottomActionView.nib",
    "TTTaskDetailSubtaskCell.nib",
    "TTTaskDetailCheckItemCell.nib",
    "TTTaskDetailParentTaskCell.nib",
    "TTTaskDetailTagCollectionCell.nib",
    "TTTaskDetailTagCollectionViewItem.nib",
    "TTTaskDetailSpaceCell.nib",
    "TTTaskDetailNotionBlockCell.nib",
    "TTTaskDetailNotionBlockShortTextView.nib",
    "TTTaskDetailNotionBlockLongTextView.nib",
    "TTTaskDetailNotionBlockOptionView.nib",
    "TTTaskDetailNotionBlockPeopleView.nib",
    "TTTaskDetailFocusSummaryCell.nib",
    "TTTaskDetailPresetTaskActionCell.nib",
    "TTTaskDetailActivitiesCell.nib",
    "TTTaskDetailCommentCell.nib",
    "TTTaskDetailCommentExpandCell.nib",
    "TTTaskDetailCommentHeaderView.nib",
    "TTTaskDetailAddCommentView.nib",
    "TTTaskDetailNoteInfoViewController.nib",
]

# Nibs that are plain AppKit views/constraints rather than TickTick classes.
LAYOUT_CLASSES = {"NSLayoutConstraint", "NSLayoutGuide"}
CELL_SUFFIXES = ("Cell",)


# --------------------------------------------------------------------------
# low level
# --------------------------------------------------------------------------
def read_vint(buf: bytes, off: int) -> tuple[int, int]:
    """NIBArchive varint: final byte carries bit7."""
    value = 0
    shift = 0
    while True:
        if off >= len(buf):
            raise ValueError("vint runs past end of file")
        b = buf[off]
        off += 1
        value |= (b & 0x7F) << shift
        if b & 0x80:
            return value, off
        shift += 7


def _f32(raw: bytes) -> float:
    return round(struct.unpack("<f", raw)[0], 4)


class Nib:
    def __init__(self, path: str):
        self.path = path
        self.name = os.path.basename(path)
        self.raw = open(path, "rb").read()
        self.size = len(self.raw)
        self._parse()

    # -- container ---------------------------------------------------------
    def _parse(self):
        raw = self.raw
        if raw[:10] != MAGIC:
            raise ValueError("not a NIBArchive file: %r" % raw[:10])
        (self.u1, self.u2, self.object_count, self.offset_objects,
         self.key_count, self.offset_keys, self.value_count,
         self.offset_values, self.class_count, self.offset_classes) = \
            struct.unpack("<10i", raw[10:50])
        self.header = OrderedDict(
            magic=MAGIC.decode("ascii"), unknown1=self.u1, unknown2=self.u2,
            object_count=self.object_count, offset_objects=self.offset_objects,
            key_count=self.key_count, offset_keys=self.offset_keys,
            value_count=self.value_count, offset_values=self.offset_values,
            class_name_count=self.class_count,
            offset_class_names=self.offset_classes,
            file_size=self.size,
        )
        # keys
        self.keys, off = [], self.offset_keys
        for _ in range(self.key_count):
            n, off = read_vint(raw, off)
            self.keys.append(raw[off:off + n].decode("utf-8", "replace"))
            off += n
        # values
        self.values, off = [], self.offset_values
        for _ in range(self.value_count):
            k, off = read_vint(raw, off)
            t = raw[off]
            off += 1
            tn = VALUE_TYPES.get(t, "T%d" % t)
            if tn == "INT8":
                v = struct.unpack_from("<b", raw, off)[0]; off += 1
            elif tn == "INT16":
                v = struct.unpack_from("<h", raw, off)[0]; off += 2
            elif tn == "INT32":
                v = struct.unpack_from("<i", raw, off)[0]; off += 4
            elif tn == "INT64":
                v = struct.unpack_from("<q", raw, off)[0]; off += 8
            elif tn == "BOOL_TRUE":
                v = True
            elif tn == "BOOL_FALSE":
                v = False
            elif tn == "NIL":
                v = None
            elif tn == "FLOAT":
                v = _f32(raw[off:off + 4]); off += 4
            elif tn == "DOUBLE":
                v = struct.unpack_from("<d", raw, off)[0]; off += 8
            elif tn == "DATA":
                n, off = read_vint(raw, off)
                v = raw[off:off + n]; off += n
            elif tn == "OBJECT_REF":
                v = struct.unpack_from("<i", raw, off)[0]; off += 4
            else:
                raise ValueError("unknown value type %r at %d" % (t, off))
            self.values.append(
                dict(key=self.keys[k] if k < len(self.keys) else "?%d" % k,
                     type=tn, value=v))
        self.values_end = off
        # objects
        self.objects, off = [], self.offset_objects
        for _ in range(self.object_count):
            cname, off = read_vint(raw, off)
            voff, off = read_vint(raw, off)
            cnt, off = read_vint(raw, off)
            self.objects.append(dict(class_index=cname, voff=voff, vcount=cnt))
        self.objects_end = off
        # class names
        self.classes, off = [], self.offset_classes
        for _ in range(self.class_count):
            ln, off = read_vint(raw, off)
            ex, off = read_vint(raw, off)
            nm = raw[off:off + ln].split(b"\x00")[0].decode("utf-8", "replace")
            off += ln
            extras = list(struct.unpack_from("<%di" % ex, raw, off)) if ex else []
            off += 4 * ex
            self.classes.append(dict(name=nm, extras=extras))
        self.classes_end = off

    # -- object helpers ----------------------------------------------------
    def obj_class(self, i: int) -> str:
        return self.classes[self.objects[i]["class_index"]]["name"]

    def obj_values(self, i: int) -> "OrderedDict[str, tuple]":
        """key -> (type, value); last wins for repeated keys (rare)."""
        out = OrderedDict()
        o = self.objects[i]
        for j in range(o["voff"], o["voff"] + o["vcount"]):
            v = self.values[j]
            out[v["key"]] = (v["type"], v["value"])
        return out

    def val(self, i: int, key: str, default=None):
        return self.obj_values(i).get(key, (None, default))[1]

    def string_of(self, i: int):
        """Resolve an NSString object reference to text."""
        if i is None or i < 0 or i >= len(self.objects):
            return None
        if self.obj_class(i) != "NSString":
            return None
        for k, (t, v) in self.obj_values(i).items():
            if k == "NS.bytes" and isinstance(v, bytes):
                return v.decode("utf-8", "replace")
        return None

    def num_of(self, i: int):
        if i is None or not (0 <= i < len(self.objects)):
            return None
        d = self.obj_values(i)
        if "NS.intval" in d:
            return d["NS.intval"][1]
        return None

    def ref(self, i: int, key: str):
        v = self.val(i, key)
        return v if isinstance(v, int) and 0 <= v < len(self.objects) else None

    def class_of_ref(self, i: int) -> str:
        if i is None:
            return None
        c = self.obj_class(i)
        if c == "NSClassSwapper":
            return self.string_of(self.ref(i, "NSClassName")) or c
        return c

    def size_value(self, i: int):
        """Resolve an IB size: either a bare NSString or an NSValue that
        stores the string under NS.sizeval (that is how IBDesignSize is
        encoded in these archives)."""
        if i is None or not (0 <= i < len(self.objects)):
            return None
        if self.obj_class(i) == "NSValue":
            return self.string_of(self.ref(i, "NS.sizeval"))
        return self.string_of(i)

    def image_of_resource(self, i: int):
        if i is None or self.obj_class(i) != "NSCustomResource":
            return None
        name = self.string_of(self.ref(i, "NSResourceName"))
        size = self.size_value(self.ref(i, "IBDesignSize"))
        return {"name": name, "design_size": size}

    def cell_info(self, i: int):
        """Describe a cell object used inside a control."""
        c = self.obj_class(i)
        d = self.obj_values(i)
        text = None
        if c in ("NSTextFieldCell", "NSButtonCell", "NSTableHeaderCell",
                 "NSSegmentedCell", "NSMenuItemCell"):
            text = self.string_of(d.get("NSContents", (None, None))[1])
        img = None
        for k in ("NSNormalImage", "NSContents", "NSAlternateImage", "NSImage"):
            if k in d and self.obj_class(d[k][1]) == "NSCustomResource":
                img = self.image_of_resource(d[k][1])
                if img:
                    break
        return dict(cls=c, text=text, image=img,
                    control_view=d.get("NSControlView", (None, None))[1])

    # -- geometry ----------------------------------------------------------
    FRAME_RE = re.compile(r"\{\{(-?[\d.]+),\s*(-?[\d.]+)\},\s*\{(-?[\d.]+),\s*(-?[\d.]+)\}\}")
    SIZE_RE = re.compile(r"^\{(-?[\d.]+),\s*(-?[\d.]+)\}$")

    @classmethod
    def parse_frame(cls, s):
        if not s:
            return None
        m = cls.FRAME_RE.match(s.strip())
        if m:
            x, y, w, h = (float(g) for g in m.groups())
            return dict(raw=s, x=x, y=y, w=w, h=h, kind="rect")
        m = cls.SIZE_RE.match(s.strip())
        if m:
            w, h = (float(g) for g in m.groups())
            return dict(raw=s, w=w, h=h, kind="size")
        return None

    def geometry_objects(self):
        """All objects that carry a frame: class swappers + window views +
        plain AppKit views that are not class swappers."""
        out = []
        for i in range(len(self.objects)):
            d = self.obj_values(i)
            if self.obj_class(i) == "NSClassSwapper":
                out.append(i)
            elif "NSFrame" in d or "NSFrameSize" in d:
                out.append(i)
            elif self.obj_class(i) == "NSWindowTemplate":
                out.append(i)
        return out

    def view_record(self, i: int):
        d = self.obj_values(i)
        c = self.obj_class(i)
        if c == "NSClassSwapper":
            real = self.string_of(d.get("NSClassName", (None, None))[1])
            orig = self.string_of(d.get("NSOriginalClassName", (None, None))[1])
        elif c == "NSCustomView":
            # older IB marker: NSClassName holds the custom subclass (if any),
            # otherwise the object really is a plain NSView.
            real = self.string_of(d.get("NSClassName", (None, None))[1]) or "NSView"
            orig = "NSView"
        else:
            real, orig = c, c
        frame = None
        fkey = None
        for k in ("NSFrame", "NSFrameSize"):
            if k in d:
                fs = self.string_of(d[k][1])
                frame = self.parse_frame(fs)
                fkey = k
                if frame:
                    break
        sup = d.get("NSSuperview", (None, None))[1]
        sup = sup if isinstance(sup, int) and 0 <= sup < len(self.objects) else None
        cell = d.get("NSCell", (None, None))[1]
        cell = cell if isinstance(cell, int) and 0 <= cell < len(self.objects) else None
        return dict(object=i, cls=real, original_class=orig,
                    frame=frame, frame_key=fkey, superview=sup, cell=cell)

    # -- connections -------------------------------------------------------
    def connectors(self):
        """Return (outlets, actions, notes).

        `NSNibConnector` (the abstract base class) also appears in a few
        archives as an *encoding-order note* whose NSLabel is a compiler
        diagnostic string ("Encoding NSStackView requires being decoded
        before other connections ... priority of 999990.").  It is neither
        an outlet nor an action and must not be counted as one.
        """
        outlets, actions, notes = [], [], []
        for i in range(len(self.objects)):
            c = self.obj_class(i)
            if "Connector" not in c:
                continue
            d = self.obj_values(i)
            src = d.get("NSSource", (None, None))[1]
            dst = d.get("NSDestination", (None, None))[1]
            label = self.string_of(d.get("NSLabel", (None, None))[1])
            item = dict(object=i, cls=c, source=src, destination=dst,
                        label=label,
                        source_class=self.class_of_ref(src),
                        destination_class=self.class_of_ref(dst))
            if c == "NSNibOutletConnector":
                outlets.append(item)
            elif c == "NSNibControlConnector":
                actions.append(item)
            else:
                notes.append(item)
        return outlets, actions, notes


# --------------------------------------------------------------------------
# extraction
# --------------------------------------------------------------------------
def extract(nib: Nib) -> dict:
    geoms = nib.geometry_objects()
    geom_set = set(geoms)
    views = {i: nib.view_record(i) for i in geoms
             if nib.obj_class(i) != "NSWindowTemplate"}
    outlets, actions, connector_notes = nib.connectors()

    # file's owner (NSRoot -> NSCustomObject -> NSClassName)
    files_owner = None
    root_ref = nib.val(1, "NSRoot") if len(nib.objects) > 1 else None
    if isinstance(root_ref, int) and 0 <= root_ref < len(nib.objects):
        files_owner = nib.string_of(nib.ref(root_ref, "NSClassName"))

    # window template?
    window = None
    for i in geoms:
        if nib.obj_class(i) == "NSWindowTemplate":
            d = nib.obj_values(i)
            rect_s = nib.string_of(d.get("NSWindowRect", (None, None))[1])
            content = d.get("NSWindowView", (None, None))[1]
            window = dict(
                object=i,
                window_class=nib.string_of(d.get("NSWindowClass", (None, None))[1])
                or "NSWindow",
                title=nib.string_of(d.get("NSWindowTitle", (None, None))[1]),
                rect=rect_s,
                style_mask=d.get("NSWindowStyleMask", (None, None))[1],
                content_view=content,
                content_view_size=(views.get(content, {}).get("frame") or {}).get("raw")
                if content in views else None,
            )

    # root view: frame-bearing view whose superview is not another view
    candidates = [i for i, v in views.items()
                  if v["superview"] is None or v["superview"] not in geom_set]
    def area(i):
        f = views[i]["frame"] or {}
        return (f.get("w") or 0) * (f.get("h") or 0)
    candidates.sort(key=area, reverse=True)
    root = None
    if candidates:
        r = views[candidates[0]]
        root = dict(r)
        root["is_root"] = True
        root["design_size"] = (r["frame"] or {}).get("raw")
        root["design_size_wh"] = ([r["frame"]["w"], r["frame"]["h"]]
                                  if r["frame"] else None)
        root["class"] = r["cls"]
    if window:
        root = dict(
            object=window["object"], cls=window["window_class"],
            original_class="NSWindowTemplate",
            design_size=window["content_view_size"] or window["rect"],
            design_size_wh=None, window_rect=window["rect"],
            title=window["title"], content_view=window["content_view"],
            content_view_class=(views[window["content_view"]]["cls"]
                                if window["content_view"] in views else None),
            is_root=True, frame=None, frame_key="NSWindowRect",
        )
        f = Nib.parse_frame(window["content_view_size"] or "")
        if f:
            root["design_size_wh"] = [f["w"], f["h"]]

    # per-object outlets / actions
    outlet_by_dest, action_by_src = {}, {}
    for o in outlets:
        outlet_by_dest.setdefault(o["destination"], []).append(o["label"])
    for a in actions:
        action_by_src.setdefault(a["source"], []).append(a["label"])

    # cells keyed by owning control view
    cells = []
    for i in range(len(nib.objects)):
        c = nib.obj_class(i)
        if c.endswith("Cell") or c in ("NSImageCell", "NSTextFieldCell"):
            info = nib.cell_info(i)
            info["object"] = i
            info["frame"] = None
            cells.append(info)
    cell_by_view = {}
    for c in cells:
        if isinstance(c["control_view"], int) and c["control_view"] in views:
            cell_by_view.setdefault(c["control_view"], []).append(c)

    # frames in object order
    frames = []
    for i in sorted(views):
        v = views[i]
        row = dict(object=i, cls=v["cls"], original_class=v["original_class"],
                   frame_key=v["frame_key"],
                   frame=(v["frame"] or {}).get("raw"),
                   superview=v["superview"])
        if v["frame"]:
            row.update({k: v["frame"][k] for k in ("x", "y", "w", "h")
                        if k in v["frame"]})
        frames.append(row)

    # texts / images (in object order)
    texts, images = [], []
    for c in cells:
        t = c["text"]
        if t and t.strip():
            texts.append(dict(text=t, from_object=c["object"],
                              cell_class=c["cls"],
                              owner=nib.class_of_ref(c["control_view"])))
        if c["image"] and c["image"]["name"]:
            images.append(dict(name=c["image"]["name"],
                               design_size=c["image"]["design_size"],
                               from_object=c["object"], cell_class=c["cls"],
                               owner=nib.class_of_ref(c["control_view"]),
                               source_key="cell image"))
    if window and window["title"]:
        texts.append(dict(text=window["title"], from_object=window["object"],
                          cell_class="NSWindowTemplate", owner="NSWindow"))
    # de-dup preserving order
    def dedup(rows, key):
        seen, out = set(), []
        for r in rows:
            k = r[key]
            if k not in seen:
                seen.add(k)
                out.append(r)
        return out
    texts_u, images_u = dedup(texts, "text"), dedup(images, "name")

    # classes
    def is_app_class(s):
        return bool(s) and (s.startswith("_TtC8TickTick") or s.startswith("TT")
                            or s.startswith("JWC"))

    used = set()
    used |= {v["cls"] for v in views.values()}
    used |= {v["original_class"] for v in views.values()}
    used |= {c["cls"] for c in cells}
    used |= {o["destination_class"] for o in outlets}
    used |= {o["source_class"] for o in actions}
    used.add(files_owner)                      # File's Owner class (NSCustomObject)
    if window:
        used.add(window["window_class"])       # NSWindowTemplate.NSWindowClass
    used.discard(None)

    custom = sorted(s for s in used if s.startswith("_TtC8TickTick"))
    app_objc = sorted(s for s in used
                      if is_app_class(s) and not s.startswith("_TtC8TickTick"))
    system = sorted(s for s in used
                    if not is_app_class(s) and s not in
                    ("NSCustomView", "NSCustomObject", "IBClassReference"))

    # controls (table B rows)
    controls = []
    for i in sorted(views):
        if nib.obj_class(i) == "NSWindowTemplate":
            continue
        v = views[i]
        out_names = outlet_by_dest.get(i, [])
        acts = action_by_src.get(i, [])
        cs = cell_by_view.get(i, [])
        text = next((c["text"] for c in cs if c["text"] and c["text"].strip()), None)
        img = next((c["image"] for c in cs if c["image"] and c["image"]["name"]), None)
        if not (out_names or acts or text or img):
            continue
        controls.append(dict(
            nib=nib.name, object=i, cls=v["cls"],
            original_class=v["original_class"],
            frame=(v["frame"] or {}).get("raw"),
            outlet=", ".join(out_names) if out_names else None,
            text=text, image=(img or {}).get("name"),
            image_design_size=(img or {}).get("design_size"),
            action=", ".join(acts) if acts else None,
            cell_class=", ".join(sorted({c["cls"] for c in cs})) or None,
        ))
    # outlet-only rows (layout constraints / plain views) are still useful
    for i in sorted({o["destination"] for o in outlets}):
        if i is None or i in views:
            continue
        o = next(x for x in outlets if x["destination"] == i)
        controls.append(dict(
            nib=nib.name, object=i, cls=nib.class_of_ref(i),
            original_class=nib.obj_class(i), frame=None,
            outlet=o["label"], text=None, image=None,
            image_design_size=None, action=None, cell_class=None))
    for a in actions:
        if a["source"] is None or a["source"] in views:
            continue
        controls.append(dict(
            nib=nib.name, object=a["source"], cls=nib.class_of_ref(a["source"]),
            original_class=nib.obj_class(a["source"]), frame=None,
            outlet=None, text=None, image=None, image_design_size=None,
            action=a["label"], cell_class=None))

    # counts
    distinct_actions = []
    for a in actions:
        if a["label"] and a["label"] not in distinct_actions:
            distinct_actions.append(a["label"])

    return dict(
        file=nib.name, path=nib.path, size_bytes=nib.size,
        header=nib.header,
        classes_table=[c["name"] for c in nib.classes],
        files_owner_class=files_owner,
        root=root,
        window=window,
        custom_classes=custom,
        app_objc_classes=app_objc,
        system_classes=system,
        outlets=[dict(name=o["label"],
                      destination_object=o["destination"],
                      destination_class=o["destination_class"],
                      destination_kind=("layout_constraint"
                                        if o["destination_class"] in LAYOUT_CLASSES
                                        else "view_or_controller"),
                      destination_frame=(views.get(o["destination"], {})
                                         .get("frame") or {}).get("raw"))
                 for o in outlets],
        actions=[dict(selector=a["label"], source_object=a["source"],
                      source_class=a["source_class"],
                      source_frame=(views.get(a["source"], {})
                                    .get("frame") or {}).get("raw"))
                 for a in actions],
        connector_notes=[dict(cls=n["cls"], label=n["label"],
                              source_class=n["source_class"])
                         for n in connector_notes],
        counts=dict(objects=len(nib.objects),
                    connections=len(outlets) + len(actions),
                    outlets=len(outlets), actions=len(actions),
                    distinct_actions=len(distinct_actions),
                    views=len(views), cells=len(cells)),
        distinct_actions=distinct_actions,
        texts=[t["text"] for t in texts_u],
        text_details=texts_u,
        images=[i["name"] for i in images_u],
        image_details=images_u,
        frames=frames,
        controls=controls,
        cells=[dict(object=c["object"], cls=c["cls"], text=c["text"],
                    image=(c["image"] or {}).get("name"),
                    image_design_size=(c["image"] or {}).get("design_size"),
                    control_view=c["control_view"]) for c in cells],
        object_class_histogram=dict(sorted(
            Counter(nib.obj_class(i) for i in range(len(nib.objects))).items(),
            key=lambda kv: (-kv[1], kv[0]))),
    )


# --------------------------------------------------------------------------
# localization
# --------------------------------------------------------------------------
# Curated detail / edit-bar key list (the app has 3457 keys per language, so
# a narrow selection is used instead of dumping everything that mentions
# "date" or "more").
LOCALIZABLE_CURATED = [
    "Add Subtask", "Add subtask", "Subtask", "Expand/Collapse all subtasks",
    "Comments", "Write a comment", "comments_show", "comments_hide",
    "edit_comment", "Can Comment",
    "Merge", "Merge Tags", "New merged task",
    "Notes", "Note", "add_note", "add_note_to__press_enter_to_save",
    "placeholder_add_note", "note_detail", "Show Notes", "Hide Notes",
    "More", "Task Activities", "Activities", "Delete", "Delete Forever",
    "Duplicate", "Expand", "Priority", "Assignee", "Set Date", "Repeat",
    "Tag", "Attachment", "Pin", "Focus",
    "task_detail_layout", "task_detail_layout_side_peek",
    "task_detail_layout_popup", "task_detail_layout_desc",
    "open_in_notion", "click_to_add_template_desktop",
    "empty_task_template_desc", "Content or details of the task",
    "Can't drag subtasks to other priority.",
]
LOCALIZABLE_TERMS = re.compile(
    r"(?i)(subtask|sub-task|check ?item|comment|merge|markdown|\bmd_?edit\b|"
    r"task_detail|note_detail|open_in_notion|activit)")


def read_strings(path: str) -> "OrderedDict[str, str]":
    raw = open(path, "rb").read()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        text = raw.decode("utf-16")
    else:
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("utf-16")
    out = OrderedDict()
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def extract_localization(resources: str, langs) -> dict:
    result = OrderedDict()
    for lang in langs:
        path = os.path.join(resources, lang, "Localizable.strings")
        if not os.path.exists(path):
            continue
        kv = read_strings(path)
        hits = OrderedDict()
        for k in LOCALIZABLE_CURATED:
            if k in kv:
                hits[k] = kv[k]
        for k, v in kv.items():
            if k in hits:
                continue
            if LOCALIZABLE_TERMS.search(k):
                hits[k] = v
        result[lang] = dict(path=path, total_keys=len(kv),
                            matched=len(hits), entries=hits)
    # bilingual pairs for the curated + term keys
    en = result.get("en.lproj", {}).get("entries", {})
    zh = result.get("zh-Hans.lproj", {}).get("entries", {})
    keys = list(en.keys()) + [k for k in zh if k not in en]
    result["pairs"] = [dict(key=k, en=en.get(k), zh=zh.get(k)) for k in keys]
    return result


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--resources",
                    default="/Applications/TickTick.app/Contents/Resources")
    ap.add_argument("--app", default="/Applications/TickTick.app")
    ap.add_argument("--out", default="-")
    ap.add_argument("--localizable", nargs="*",
                    default=["en.lproj", "zh-Hans.lproj"])
    ap.add_argument("--pretty", action="store_true", default=True)
    args = ap.parse_args(argv)

    nibs, errors = [], []
    for name in TARGET_NIBS:
        p = os.path.join(args.resources, name)
        if not os.path.exists(p):
            errors.append(dict(file=name, error="missing"))
            continue
        try:
            nibs.append(extract(Nib(p)))
        except Exception as exc:  # noqa: BLE001 - report, never crash silently
            errors.append(dict(file=name, error="%s: %s" % (type(exc).__name__, exc)))

    # aggregate
    all_custom = OrderedDict()
    all_images = OrderedDict()
    all_texts = OrderedDict()
    for n in nibs:
        for c in n["custom_classes"]:
            all_custom.setdefault(c, []).append(n["file"])
        for im in n["images"]:
            all_images.setdefault(im, []).append(n["file"])
        for t in n["texts"]:
            all_texts.setdefault(t, []).append(n["file"])
    version = None
    plist = os.path.join(args.app, "Contents", "Info.plist")
    if os.path.exists(plist):
        try:
            import plistlib
            with open(plist, "rb") as fh:
                version = plistlib.load(fh).get("CFBundleShortVersionString")
        except Exception:
            version = None

    doc = OrderedDict()
    doc["meta"] = OrderedDict(
        generated_at_utc=_dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds"),
        generator="docs/audits/ticktick-rea-2026-10-17/scripts/parse_nibarchive.py",
        app_path=args.app, app_version=version,
        resources_dir=args.resources,
        format="NIBArchive v1 (Apple compiled nib)",
        method="binary structural parse: header -> keys/values/classes/objects "
               "-> NSIBObjectData graph -> NSNibOutletConnector / "
               "NSNibControlConnector -> NSClassSwapper frames / cell contents",
        nib_requested=len(TARGET_NIBS), nib_parsed=len(nibs),
        parse_errors=errors,
        limitations=[
            "Outlet -> target class is read from the destination object's "
            "NSClassName; for layout constraints the destination is an "
            "NSLayoutConstraint (no owning view is recorded in the archive).",
            "NSFrame / NSFrameSize strings are IB design-time geometry; they "
            "are not live Auto Layout results.",
            "Cell objects have no frame of their own; their owning control "
            "view frame is reported instead.",
            "No NSPlaceholderString key exists in these archives, so text "
            "field placeholders are not recoverable (they are set in code).",
            "NSLayoutConstraint relations (NSFirstItem/NSSecondItem/"
            "NSFirstAttribute/NSRelation) were parsed only as outlet targets; "
            "constraint constants were not resolved into spacing values.",
        ],
    )
    doc["nibs"] = nibs
    doc["parse_errors"] = errors
    doc["totals"] = OrderedDict(
        nibs=len(nibs),
        nibs_with_root=sum(1 for n in nibs if n["root"]),
        objects=sum(n["counts"]["objects"] for n in nibs),
        connections=sum(n["counts"]["connections"] for n in nibs),
        outlets=sum(n["counts"]["outlets"] for n in nibs),
        actions=sum(n["counts"]["actions"] for n in nibs),
        distinct_custom_classes=len(all_custom),
        images=len(all_images),
        distinct_texts=len(all_texts),
        controls=sum(len(n["controls"]) for n in nibs),
    )
    doc["custom_classes"] = [dict(cls=k, nibs=v) for k, v in all_custom.items()]
    doc["image_index"] = [dict(name=k, nibs=v) for k, v in all_images.items()]
    doc["text_index"] = [dict(text=k, nibs=v) for k, v in all_texts.items()]
    doc["controls"] = [c for n in nibs for c in n["controls"]]
    doc["localization"] = extract_localization(args.resources, args.localizable)

    text = json.dumps(doc, ensure_ascii=False, indent=2)
    if args.out == "-":
        sys.stdout.write(text + "\n")
    else:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        sys.stderr.write("wrote %s (%d bytes, %d nibs)\n"
                         % (args.out, len(text), len(nibs)))


if __name__ == "__main__":
    main()
