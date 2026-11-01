"""Independent integer oracle for four spatially associated CNN targets.

This module knows no dataset labels. Confidence is the existing 0..100 margin
score, and zero confidence never confirms a class. Association uses geometry
alone; slot/confidence rank never identifies an object.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Box:
    x0: int
    y0: int
    x1: int
    y1: int
    class_id: int
    confidence: int
    reserved: int = 0
    area: int = 0

    @classmethod
    def unpack(cls, value: int) -> "Box":
        return cls(*(value >> bit & ((1 << width) - 1) for bit, width in
                     ((0, 16), (16, 16), (32, 16), (48, 16), (64, 16),
                      (80, 8), (88, 8), (96, 32))))

    def pack(self) -> int:
        return sum(value << bit for value, bit in zip(
            (self.x0, self.y0, self.x1, self.y1, self.class_id,
             self.confidence, self.reserved, self.area), (0, 16, 32, 48, 64, 80, 88, 96)))

    @property
    def geometry_valid(self) -> bool:
        return 0 <= self.x0 < self.x1 <= 1280 and 0 <= self.y0 < self.y1 <= 720

    @property
    def reliable(self) -> bool:
        return self.geometry_valid and 1 <= self.class_id <= 9 and self.confidence > 0


def unpack_boxes(value: int, count: int) -> list[Box]:
    return [Box.unpack(value >> (128 * i) & ((1 << 128) - 1)) for i in range(count)]


def pack_boxes(boxes: list[Box]) -> int:
    return sum(box.pack() << (128 * i) for i, box in enumerate(boxes))


def association_distance(a: Box, b: Box) -> int | None:
    """Integer double-center Manhattan distance, gated by overlap and size."""
    aw, ah, bw, bh = a.x1 - a.x0, a.y1 - a.y0, b.x1 - b.x0, b.y1 - b.y0
    if min(a.x1, b.x1) <= max(a.x0, b.x0) or min(a.y1, b.y1) <= max(a.y0, b.y0):
        return None
    if max(aw, bw) > min(aw, bw) * 2 or max(ah, bh) > min(ah, bh) * 2:
        return None
    dx2 = abs(a.x0 + a.x1 - b.x0 - b.x1)
    dy2 = abs(a.y0 + a.y1 - b.y0 - b.y1)
    return dx2 + dy2 if dx2 <= max(aw, bw) and dy2 <= max(ah, bh) else None


@dataclass
class Track:
    box: Box
    confirmed: int = 0
    pending: int = 0
    pending_hits: int = 0
    anomalies: int = 0
    missing: int = 0


class Stabilizer:
    def __init__(self, confirm_results: int = 3, hold_results: int = 2, lost_results: int = 3):
        self.confirm_results = confirm_results
        self.hold_results = hold_results
        self.lost_results = lost_results
        self.clear()

    def clear(self) -> None:
        self.tracks: list[Track | None] = [None] * 4
        self.primary: int | None = None

    def update(self, count: int, packed: int) -> tuple[int, int, int]:
        candidates = unpack_boxes(packed, count) if count <= 4 else []
        uncertain = count > 4 or any(not box.geometry_valid or not 1 <= box.class_id <= 9 for box in candidates)
        valid = [i for i, box in enumerate(candidates) if box.geometry_valid and 1 <= box.class_id <= 9]
        unmatched_tracks = {i for i, track in enumerate(self.tracks) if track is not None}
        unmatched_candidates = set(valid)
        assignment: dict[int, int] = {}
        # Globally closest admissible pair, then stable track/candidate index.
        while unmatched_tracks and unmatched_candidates:
            pairs = [(distance, ti, ci) for ti in unmatched_tracks for ci in unmatched_candidates
                     if (distance := association_distance(self.tracks[ti].box, candidates[ci])) is not None]
            if not pairs:
                break
            _, ti, ci = min(pairs)
            assignment[ti] = ci
            unmatched_tracks.remove(ti)
            unmatched_candidates.remove(ci)
        for ti in sorted(unmatched_tracks):
            track = self.tracks[ti]
            track.missing += 1
            track.pending = 0
            track.pending_hits = 0
            if track.missing >= self.lost_results:
                self.tracks[ti] = None
            else:
                uncertain = True
        # Area determines new-object admission only after every old match.
        for ci in sorted(unmatched_candidates, key=lambda i: (-candidates[i].area, i)):
            free = next((i for i, track in enumerate(self.tracks) if track is None), None)
            if free is None:
                uncertain = True
                break
            self.tracks[free] = Track(candidates[ci])
            assignment[free] = ci
        visible: dict[int, Box] = {}
        for ti, ci in sorted(assignment.items()):
            track, box = self.tracks[ti], candidates[ci]
            track.box = box
            track.missing = 0
            if track.confirmed == 0:
                track.anomalies = 0
                if box.reliable:
                    if track.pending == box.class_id:
                        track.pending_hits += 1
                    else:
                        track.pending, track.pending_hits = box.class_id, 1
                    if track.pending_hits >= self.confirm_results:
                        track.confirmed = box.class_id
                        track.pending_hits = track.pending = 0
                    else:
                        uncertain = True
                else:
                    track.pending = track.pending_hits = 0
                    uncertain = True
            elif box.reliable:
                if track.confirmed == box.class_id:
                    track.anomalies = track.pending_hits = track.pending = 0
                else:
                    track.anomalies += 1
                    if track.pending == box.class_id:
                        track.pending_hits += 1
                    else:
                        track.pending, track.pending_hits = box.class_id, 1
                    if track.pending_hits >= self.confirm_results:
                        track.confirmed = box.class_id
                        track.anomalies = track.pending_hits = track.pending = 0
                    elif track.anomalies > self.hold_results:
                        track.confirmed = track.pending = track.pending_hits = 0
                        track.anomalies = 0
                    if track.confirmed != box.class_id:
                        uncertain = True
            else:
                track.anomalies += 1
                track.pending = track.pending_hits = 0
                if track.anomalies > self.hold_results:
                    track.confirmed = 0
                    track.anomalies = 0
                uncertain = True
            out_class = track.confirmed
            out_conf = box.confidence if track.confirmed == box.class_id and box.reliable else 0
            if out_class:
                visible[ti] = Box(box.x0, box.y0, box.x1, box.y1, out_class,
                                  out_conf, 0, box.area)
        if self.primary not in visible:
            self.primary = min(visible, key=lambda ti: (-visible[ti].area, ti)) if visible else None
        order = ([self.primary] if self.primary is not None else []) + [ti for ti in sorted(visible) if ti != self.primary]
        output = [visible[ti] for ti in order]
        return len(output), pack_boxes(output), int(uncertain)
