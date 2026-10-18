#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
validate_against_evidence.py -- cross-check the parsed detail nibs against
  (a) the known TTTaskDetailTopView / TTTaskDetailBottomActionView contract,
  (b) docs/audits/ticktick-rea-2026-10-13/rea-selected-evidence.json
      (every nib that appears in both places).

Read-only.  Writes ticktick-detail-nib-validation.json next to the inventory.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_nibarchive import Nib, extract  # noqa: E402

TOPVIEW_EXPECTED = dict(outlets=18, actions=6)

BOTTOM_ACTION_OUTLETS = [
    "commentButton", "commentButtonLeading", "deleteButton",
    "deleteButtonLeading", "deleteForeverButton", "deleteForeverButtonLeading",
    "mdEditButton", "mdEditButtonLeading", "mergeButton", "mergeButtonLeading",
    "moreButton", "moreButtonLeading", "projectButton", "tagButton",
    "tagButtonLeading",
]
BOTTOM_ACTION_ACTIONS = [
    "tagButtonClicked:", "moreButtonClicked:", "mergeButtonClicked:",
    "deleteTaskButtonClicked:", "mdEditButtonClicked:",
    "moveToProjectButtonClicked:", "commentButtonClicked:",
    "deleteForeverButtonClicked:",
]


def load_inventory(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def compare_evidence(inventory, evidence_path, resources):
    ev = json.load(open(evidence_path, encoding="utf-8"))
    ours = {n["file"]: n for n in inventory["nibs"]}
    rows = []
    for entry in ev.get("ui_archives", []):
        f = os.path.basename(entry["original_file"])
        row = dict(file=f, in_detail_scope=f in ours,
                   evidence_objects=entry.get("objects"),
                   evidence_connections=entry.get("connections"),
                   evidence_outlets=len(entry.get("outlets", [])),
                   evidence_actions=len(entry.get("actions", [])),
                   evidence_action_set=sorted(entry.get("actions", [])))
        if f in ours:
            n = ours[f]
            row.update(parsed_objects=n["counts"]["objects"],
                       parsed_outlets=n["counts"]["outlets"],
                       parsed_actions=n["counts"]["actions"],
                       parsed_distinct_actions=n["counts"]["distinct_actions"],
                       outlets_match=sorted(set(entry.get("outlets", []))) ==
                                     sorted({o["name"] for o in n["outlets"]}),
                       actions_match=sorted(entry.get("actions", [])) ==
                                     sorted(n["distinct_actions"]))
        elif os.path.exists(os.path.join(resources, f)):
            # nib exists but was not part of the detail scope: parse it to
            # widen the parser-accuracy sample (read-only).
            try:
                n = extract(Nib(os.path.join(resources, f)))
                row.update(parsed_objects=n["counts"]["objects"],
                           parsed_outlets=n["counts"]["outlets"],
                           parsed_actions=n["counts"]["actions"],
                           parsed_distinct_actions=n["counts"]["distinct_actions"],
                           outlets_match=sorted(set(entry.get("outlets", []))) ==
                                         sorted({o["name"] for o in n["outlets"]}),
                           actions_match=sorted(entry.get("actions", [])) ==
                                         sorted(n["distinct_actions"]))
            except Exception as exc:  # noqa: BLE001
                row["error"] = str(exc)
        else:
            row["error"] = "nib not installed"
        rows.append(row)
    comparable = [r for r in rows if "outlets_match" in r]
    return dict(
        evidence_file=evidence_path,
        entries=len(rows),
        comparable=len(comparable),
        outlets_all_match=all(r["outlets_match"] for r in comparable),
        actions_all_match=all(r["actions_match"] for r in comparable),
        outlet_mismatches=[r["file"] for r in comparable if not r["outlets_match"]],
        action_mismatches=[r["file"] for r in comparable if not r["actions_match"]],
        outlet_metric_note=(
            "evidence['outlets'] is a de-duplicated *name* list, not one row "
            "per NSNibOutletConnector (TTFocusDetailRecordsViewController has "
            "22 connectors but 14 distinct names; it matches once de-duped). "
            "Per-nib connector counts are kept in parsed_outlets."),
        object_metric_note=(
            "evidence['objects'] has no documented counting rule; it does not "
            "equal archive object_count (Python parser) nor "
            "views+cells+connectors+constraints, so only outlet/action/"
            "connection counts are treated as contractual."),
        rows=rows,
    )


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--inventory", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "ticktick-detail-nib-inventory.json"))
    ap.add_argument("--evidence", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
        "ticktick-rea-2026-10-13", "rea-selected-evidence.json"))
    ap.add_argument("--resources",
                    default="/Applications/TickTick.app/Contents/Resources")
    ap.add_argument("--out", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "ticktick-detail-nib-validation.json"))
    args = ap.parse_args(argv)

    inv = load_inventory(args.inventory)
    nibs = {n["file"]: n for n in inv["nibs"]}

    # ---- (a) hard contract ------------------------------------------------
    top = nibs["TTTaskDetailTopView.nib"]
    top_outlets = [o["name"] for o in top["outlets"]]
    top_actions = top["distinct_actions"]
    bottom = nibs["TTTaskDetailBottomActionView.nib"]
    b_outlets = [o["name"] for o in bottom["outlets"]]
    b_actions = [a["selector"] for a in bottom["actions"]]
    b_distinct = bottom["distinct_actions"]

    contract = dict(
        topview=dict(
            expected_outlets=TOPVIEW_EXPECTED["outlets"],
            actual_outlets=len(top_outlets),
            expected_actions=TOPVIEW_EXPECTED["actions"],
            actual_outlet_connectors=len(top_outlets),
            actual_control_connectors=len(top["actions"]),
            actual_distinct_actions=len(top_actions),
            duplicate_action_connectors=[
                dict(selector=s, count=c)
                for s, c in Counter(a["selector"] for a in top["actions"]).items()
                if c > 1],
            outlets=top_outlets,
            distinct_actions=top_actions,
            ok=len(top_outlets) == 18 and len(top_actions) == 6,
        ),
        bottom_action_view=dict(
            expected_outlets=BOTTOM_ACTION_OUTLETS,
            missing_outlets=[o for o in BOTTOM_ACTION_OUTLETS if o not in b_outlets],
            extra_outlets=[o for o in b_outlets if o not in BOTTOM_ACTION_OUTLETS],
            expected_actions=BOTTOM_ACTION_ACTIONS,
            missing_actions=[a for a in BOTTOM_ACTION_ACTIONS if a not in b_actions],
            extra_actions=[a for a in b_actions if a not in BOTTOM_ACTION_ACTIONS],
            duplicates=[],
            ok=(not [o for o in BOTTOM_ACTION_OUTLETS if o not in b_outlets]
                and not [a for a in BOTTOM_ACTION_ACTIONS if a not in b_actions]),
        ),
    )

    # ---- (b) evidence cross-check ----------------------------------------
    try:
        cross = compare_evidence(inv, args.evidence, args.resources)
    except FileNotFoundError as exc:
        cross = dict(error=str(exc))

    # ---- (c) image asset existence in Assets.car --------------------------
    assets = dict(car=None, checked=0, missing=[])
    car = os.path.join(args.resources, "Assets.car")
    if os.path.exists(car):
        try:
            out = subprocess.run(["/usr/bin/assetutil", "--info", car],
                                 capture_output=True, text=True, timeout=120)
            data = json.loads(out.stdout)
            names = set()
            for e in data:
                for k in ("Name", "AssetName", "RenditionName"):
                    if isinstance(e.get(k), str):
                        names.add(e[k])
            all_images = sorted({im for n in inv["nibs"] for im in n["images"]})
            assets = dict(car=car, checked=len(all_images),
                          resolved=len([i for i in all_images if i in names]),
                          missing=[i for i in all_images if i not in names])
        except Exception as exc:  # noqa: BLE001
            assets = dict(car=car, error=str(exc))

    # ---- (d) TopView object-count reconciliation --------------------------
    hist = top.get("object_class_histogram", {})
    total = sum(hist.values())
    views = sum(1 for f in top["frames"] if f.get("frame"))
    ui_subset = (top["counts"]["views"] + top["counts"]["cells"] +
                 top["counts"]["connections"] +
                 hist.get("NSLayoutConstraint", 0))
    doc = dict(
        contract=contract,
        evidence_cross_check=cross,
        image_assets=assets,
        object_count_reconciliation=dict(
            archive_object_count=total,
            histogram=hist,
            ui_views_swappers=top["counts"]["views"],
            cells=top["counts"]["cells"],
            connectors=top["counts"]["connections"],
            layout_constraints=hist.get("NSLayoutConstraint", 0),
            ui_subset_sum=ui_subset,
            note=("TopView: archive has %d objects; the 2026-10-13 evidence "
                  "entry reports objects=95, which equals views(%d)+cells(%d)+"
                  "connectors(%d)+constraints(%d). The same rule does not hold "
                  "for other evidence entries (e.g. TTCalendarArrangeCell 31 "
                  "vs 36), so it is a coincidence-grade fit, not a proven "
                  "metric." % (total, top["counts"]["views"], top["counts"]["cells"],
                               top["counts"]["connections"],
                               hist.get("NSLayoutConstraint", 0))),
        ),
    )
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print(json.dumps(dict(
        topview=dict(ok=contract["topview"]["ok"],
                     outlets=len(top_outlets), actions=len(top_actions)),
        bottom=dict(ok=contract["bottom_action_view"]["ok"],
                    missing_outlets=contract["bottom_action_view"]["missing_outlets"],
                    missing_actions=contract["bottom_action_view"]["missing_actions"]),
        evidence=dict(comparable=cross.get("comparable"),
                      outlets_all_match=cross.get("outlets_all_match"),
                      actions_all_match=cross.get("actions_all_match"),
                      outlet_mismatches=cross.get("outlet_mismatches"),
                      action_mismatches=cross.get("action_mismatches")),
    ), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
