"""Extract named examples from completed, session-continuous frozen traces."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from cnn_stability_reference import unpack_boxes

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"02_sim/cnn_stability"
WANTED=(10213,10225,10243,20255,20267,20279)


def main():
    summary=json.loads((OUT/"RESULTS.json").read_text(encoding="utf-8"))
    assert summary["status"]=="PASS"
    events=[json.loads(line) for line in (OUT/"reference_trace.jsonl").read_text(encoding="utf-8").splitlines()]
    actual={int(parts[0]):parts for line in (OUT/"rtl_trace.txt").read_text().splitlines() if (parts:=line.split("|"))}
    selected=[]
    for frame in WANTED:
        event=next(e for e in events if e.get("frame_id")==frame)
        parts=actual[event["id"]]
        assert int(parts[1])==event["output_count"] and int(parts[2],16)==int(event["output"],16) and int(parts[3])==event["uncertain"]
        def boxes(packed,count):
            return [{"class_id":b.class_id,"confidence":b.confidence,"box":[b.x0,b.y0,b.x1,b.y1]}
                    for b in unpack_boxes(int(packed,16),count)]
        selected.append({"frame_id":frame,"capture_session":event["capture_session"],"source_index":event["source_index"],
                         "raw_candidates":boxes(event["input"],event["count"]),
                         "stabilized":boxes(event["output"],event["output_count"]),"uncertain":event["uncertain"]})
    report={"status":"PASS_FROZEN_EXAMPLE_EXTRACTION","hardware_status":"NOT_RUN","examples":selected,
            "method":"Extracted after the full session-continuous replay. No reset or reclassification performed for these examples.",
            "evidence_sha256":{name:hashlib.sha256((OUT/name).read_bytes()).hexdigest().upper()
                               for name in ("RESULTS.json","reference_trace.jsonl","rtl_trace.txt")}}
    (OUT/"CONCRETE_EXAMPLES.json").write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    lines=["# 连续会话中的具体对照", "",
           "以下六帧从已完成并与 RTL 一致的完整会话回放中提取，没有按真实类别清历史，也没有为示例重新开始确认。类别标签仅用于说明。", "",
           "| 帧号 | 当前原始候选：类别/分值 | 稳定后输出：类别/分值 | uncertain |", "|---|---|---|---|"]
    for e in selected:
        fmt=lambda bs:"；".join(f"C{b['class_id']} / {b['confidence']}" for b in bs) or "无输出"
        lines.append(f"| {e['frame_id']} | {fmt(e['raw_candidates'])} | {fmt(e['stabilized'])} | {e['uncertain']} |")
    lines.extend(["", "红圆柱（C2）：10213 为 C2/57；10225 的原始 argmax 短暂变为 C3，但分值为 0，因此输出保留已确认的 C2、分值仍为 0，标记不确定；10243 的 C2/65 到来后正常恢复。没有把低分 C3 升格为有效识别。", "",
                  "蓝三棱柱（C7）：20255 输出已有确认的 C7/11，并抑制未确认的背景 C9/0；20267 的主候选短暂为 C8/0，稳定输出保留 C7/0；20279 主候选仍低分，继续保留 C7/0。其他背景候选未达到连续确认，不会抢占已可见的主目标。", "",
                  "`uncertain` 是整组结果的状态，可能来自其他未确认或暂时丢失的目标；因此它与主目标分值为 0 并不等价。保留旧类别的两个示例分值保持为 0，不能当作新的可靠分类。", "",
                  "首次确认、连续三次低分后无输出、缺失三次清历史等行为由定向测试单独证明。这六帧只展示特定瞬态，不证明独立精度，也不代表实板结果。实板状态：NOT_RUN。", ""])
    (OUT/"CONCRETE_EXAMPLES.md").write_text("\n".join(lines),encoding="utf-8")
    print("PASS six examples extracted without modifying frozen regression inputs")


if __name__=="__main__":main()
