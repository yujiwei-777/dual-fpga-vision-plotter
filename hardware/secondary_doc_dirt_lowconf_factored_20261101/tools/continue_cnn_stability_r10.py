"""One-shot dependency coordinator for the existing R10 build (not a scheduler).

Wait for the already-started SYN runner, then run route -> gate -> readonly ->
bitgen through run_detached_cnn_stage_r10.py. This script never changes design inputs,
weakens a gate, generates/copies a bitstream itself, retries a failed stage, or
terminates TD. A persistent O_EXCL status file makes invocation single-use.

Invoke once, after review, from a hidden process with stdin=DEVNULL. Merely
compiling or importing this file starts nothing. Do not delete/reuse its durable
status to restart a partial sequence; preserve evidence and review it instead.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "cnn_stability_r10_grid_Runs_20261031"
BUILDER = ROOT / "tools/build_cnn_stability_r10.py"
RUNNER = ROOT / "tools/run_detached_cnn_stage_r10.py"
STATUS = RUNS / "CONSTRUCTION_SEQUENCE.json"
LOG = RUNS / "construction_sequence.log"
STAGES = ("syn", "route", "gate", "readonly", "bitgen")
POLL_SECONDS = 10
STARTUP_SECONDS = 60
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def normalized(value):
    return str(value).replace("/", "\\").casefold()


class SequenceError(RuntimeError):
    pass


def save_atomic(value):
    """Keep the permanent single-use path present throughout all status updates."""
    temp = STATUS.with_name(STATUS.name + f".{os.getpid()}.tmp")
    with temp.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, STATUS)


def log(stream, message):
    stream.write(f"{now()} {message}\n")
    stream.flush()
    os.fsync(stream.fileno())


def get_process(pid):
    """Read-only CIM PID/identity lookup. Never call Windows os.kill(pid, 0)."""
    if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 0:
        return {"state": "INVALID_PID", "pid": pid}
    script = (f"$ErrorActionPreference = 'Stop'; $p = Get-CimInstance Win32_Process -Filter 'ProcessId = {pid}'; "
              "if ($null -ne $p) { $p | Select-Object ProcessId,ParentProcessId,Name,CommandLine,CreationDate | "
              "ConvertTo-Json -Compress }")
    try:
        result = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                                stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                timeout=20, creationflags=NO_WINDOW)
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"state": "QUERY_FAILED", "pid": pid, "error": str(error)}
    if result.returncode:
        return {"state": "QUERY_FAILED", "pid": pid, "error": result.stderr.strip(),
                "exit_code": result.returncode}
    if not result.stdout.strip():
        return {"state": "NOT_FOUND", "pid": pid}
    try:
        row = json.loads(result.stdout)
    except ValueError as error:
        return {"state": "QUERY_FAILED", "pid": pid, "error": str(error)}
    return {"state": "FOUND", "pid": pid, "process": row}


def runner_identity(observation, stage):
    if observation.get("state") != "FOUND":
        return False
    row = observation.get("process", {})
    command = normalized(row.get("CommandLine") or "")
    # Existing SYN was launched with project-relative builder/run arguments;
    # all newly launched stages use full paths. Both must identify this run.
    action = re.search(r"--action(?:\s+|=)[\"']?" + re.escape(stage) + r"(?:[\"']?\s|[\"']?$)", command)
    return bool(row.get("Name", "").casefold() in {"python.exe", "pythonw.exe"}
                and RUNNER.name.casefold() in command
                and BUILDER.name.casefold() in command
                and RUNS.name.casefold() in command and action)


def stage_paths(stage):
    return RUNS / f"DETACHED_{stage.upper()}.json", RUNS / f"detached_{stage}.log"


def read_stage(stage):
    path, _ = stage_paths(stage)
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as error:
        # The existing runner writes JSON directly. A transient partial write
        # is retried only while that exact runner remains alive.
        return {"status": "UNREADABLE", "read_error": str(error)}
    if not isinstance(data, dict):
        return {"status": "UNREADABLE", "read_error": "Stage JSON is not an object"}
    return data


def verify_stage_record(data, stage, owned_pid=None):
    if data.get("action") != stage:
        raise SequenceError(f"{stage}: stage record action mismatch")
    if owned_pid is not None and data.get("pid") != owned_pid:
        raise SequenceError(f"{stage}: record PID differs from the runner launched by this coordinator")
    command = data.get("command")
    if not isinstance(command, list) or len(command) < 5:
        raise SequenceError(f"{stage}: missing builder command identity")
    if normalized(Path(command[1]).resolve()) != normalized(BUILDER.resolve()) or command[2] != stage:
        raise SequenceError(f"{stage}: builder identity/action mismatch")
    try:
        index = command.index("--runs")
        observed_run = Path(command[index + 1]).resolve()
    except (ValueError, IndexError, TypeError) as error:
        raise SequenceError(f"{stage}: invalid run identity in builder command") from error
    if normalized(observed_run) != normalized(RUNS.resolve()):
        raise SequenceError(f"{stage}: builder command identifies another run")
    if data.get("status") == "PASS" and data.get("exit_code") != 0:
        raise SequenceError(f"{stage}: PASS without exit code zero")


def wait_for_stage(stage, state, stream, child=None):
    started = time.monotonic()
    owned_pid = child.pid if child else None
    known_pid = owned_pid
    unreadable_count = 0
    while True:
        data = read_stage(stage)
        if data is not None and data.get("status") != "UNREADABLE":
            verify_stage_record(data, stage, owned_pid)
            known_pid = data.get("pid")
            state["stage_records"][stage] = data
            observed_status = data.get("status")
            if observed_status == "PASS":
                if child is not None:
                    try:
                        exit_code = child.wait(timeout=10)
                    except subprocess.TimeoutExpired as error:
                        raise SequenceError(f"{stage}: PASS record exists but owned runner has not exited") from error
                    if exit_code != 0:
                        raise SequenceError(f"{stage}: owned runner exited {exit_code} despite PASS record")
                state["completed_stages"].append(stage)
                state["last_observed_utc"] = now()
                save_atomic(state)
                log(stream, f"{stage}: PASS; runner pid={known_pid}")
                return
            if observed_status != "RUNNING":
                raise SequenceError(f"{stage}: runner terminal status {observed_status!r}; no retry")
            unreadable_count = 0
        else:
            unreadable_count += 1
            if data is not None:
                state["last_read_error"] = {"stage": stage, "utc": now(), **data}
            if child is None and known_pid is None:
                # SYN evidence should exist before coordination starts. Without
                # an authenticated PID a partial record cannot be safely watched.
                raise SequenceError(f"{stage}: missing/unreadable initial stage record")
            if time.monotonic() - started > STARTUP_SECONDS and data is None:
                raise SequenceError(f"{stage}: runner did not create a stage record within {STARTUP_SECONDS}s")
            if unreadable_count >= 3 and data is not None:
                raise SequenceError(f"{stage}: stage record remained unreadable across three observations")

        # A status write may race with process exit. Re-read terminal status
        # after liveness failure before declaring the dependency failed.
        process = get_process(known_pid)
        identity_matches = runner_identity(process, stage)
        state["last_process_observation"] = {"stage": stage, "utc": now(),
                                              "same_run_runner_identity": identity_matches, **process}
        state["last_observed_utc"] = now()
        save_atomic(state)
        if not identity_matches:
            final = read_stage(stage)
            if final is not None and final.get("status") not in {"RUNNING", "UNREADABLE"}:
                continue
            raise SequenceError(f"{stage}: runner dead, identity mismatch or liveness unavailable ({process['state']}); no next stage")
        if child is not None and child.poll() is not None:
            final = read_stage(stage)
            if final is not None and final.get("status") not in {"RUNNING", "UNREADABLE"}:
                continue
            raise SequenceError(f"{stage}: owned runner exited without terminal evidence; no retry")
        time.sleep(POLL_SECONDS)


def main():
    if len(sys.argv) != 1:
        raise SystemExit("This one-shot coordinator takes no arguments; review constants before invocation.")
    if os.name != "nt":
        raise SystemExit("This coordinator requires Windows CIM process identity checks.")
    if not RUNS.resolve().is_relative_to(ROOT.resolve()) or "work" in [part.casefold() for part in RUNS.resolve().parts]:
        raise SystemExit("An independent non-work R10 run is required.")
    if not all(path.is_file() for path in (BUILDER, RUNNER, RUNS / "BUILD_PLAN.json")):
        raise SystemExit("Expected R10 builder, runner and build plan are required.")
    if LOG.exists():
        raise SystemExit("Coordinator log already exists; preserve this single-use invocation.")
    state = {
        "schema_version": 1, "status": "RUNNING", "started_utc": now(),
        "pid": os.getpid(), "root": str(ROOT), "runs": str(RUNS),
        "builder": str(BUILDER), "builder_sha256": sha(BUILDER),
        "runner": str(RUNNER), "runner_sha256": sha(RUNNER),
        "build_plan_sha256": sha(RUNS / "BUILD_PLAN.json"),
        "stage_order": list(STAGES), "completed_stages": [], "stage_records": {},
        "current_stage": "syn", "poll_seconds": POLL_SECONDS,
        "hardware_status": "NOT_RUN", "log": str(LOG),
        "policy": "Single invocation; wait existing SYN; no retries, gate bypass, input edits, process killing or bitstream copying. Only builder bitgen delivers.",
    }
    try:
        descriptor = os.open(STATUS, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666)
    except FileExistsError as error:
        raise SystemExit("CONSTRUCTION_SEQUENCE.json already exists; refusing a second invocation.") from error
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(state, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    try:
        with LOG.open("x", encoding="utf-8") as stream:
            log(stream, f"One-shot R10 coordination started; pid={os.getpid()}; waiting existing SYN")
            try:
                # Never starts a second SYN: this is the dependency already
                # running before the coordinator was requested.
                wait_for_stage("syn", state, stream)
                for stage in STAGES[1:]:
                    state["current_stage"] = stage
                    state["last_observed_utc"] = now()
                    save_atomic(state)
                    status_path, stage_log = stage_paths(stage)
                    if status_path.exists() or stage_log.exists():
                        data = read_stage(stage)
                        if data is None or data.get("status") != "PASS":
                            raise SequenceError(f"{stage}: existing stage evidence is not PASS; never start or attach a duplicate")
                        verify_stage_record(data, stage)
                        state["stage_records"][stage] = data
                        state["completed_stages"].append(stage)
                        state.setdefault("reused_pass_stages", []).append(stage)
                        save_atomic(state)
                        log(stream, f"{stage}: accepted existing same-run PASS; not restarted")
                        continue
                    # Frozen inputs must still have the same coordinator-entry
                    # identity. The builder independently verifies its plan and
                    # all required production/regression/release gates as well.
                    if sha(BUILDER) != state["builder_sha256"] or sha(RUNNER) != state["runner_sha256"] or sha(RUNS / "BUILD_PLAN.json") != state["build_plan_sha256"]:
                        raise SequenceError("Builder, runner or build plan changed during the dependency sequence")
                    command = [sys.executable, str(RUNNER), "--builder", str(BUILDER),
                               "--runs", str(RUNS), "--action", stage]
                    log(stream, f"Starting {stage} through audited runner; no direct TD invocation")
                    child = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                                             stdout=stream, stderr=subprocess.STDOUT,
                                             creationflags=NO_WINDOW)
                    state.setdefault("started_runners", []).append({"stage": stage, "pid": child.pid,
                                                                    "started_utc": now(), "command": command})
                    save_atomic(state)
                    wait_for_stage(stage, state, stream, child)
                state.update(status="PASS", completed_utc=now(), current_stage=None,
                             result="All existing audited builder stages passed; only builder bitgen performed delivery.")
                save_atomic(state)
                log(stream, "PASS complete sequence; hardware validation remains NOT_RUN")
                return 0
            except BaseException as error:
                state.update(status="INTERRUPTED" if isinstance(error, (KeyboardInterrupt, SystemExit)) else "FAILED",
                             completed_utc=now(), error=repr(error),
                             recovery_note="No child/TD process was killed; inspect stage evidence. This coordinator will not retry or restart.")
                save_atomic(state)
                log(stream, f"{state['status']} {error!r}; no further stage started; no process terminated")
                return 1
    except BaseException as error:
        state.update(status="COORDINATOR_ERROR", completed_utc=now(), error=repr(error))
        save_atomic(state)
        raise


if __name__ == "__main__":
    raise SystemExit(main())
