"""Exercise the real KEY3 FPGA reset supervisor and reset_sync RTL.

Only this independent project's 02_sim/key3_board_reset_unit is written.
This verifies FPGA reset behavior; it does not model external GRBL stopping.
"""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "02_sim/key3_board_reset_unit"
SIM = Path("E:/model/win64")
LICENSE = SIM / "LICENSE.TXT"
TOP = ROOT / "01_rtl/secondary_top.v"
SYNC = ROOT / "main/user_source/hdl_source/reset_sync.v"

BENCH = r'''`timescale 1ns/1ps
module tb_key3_debounce_case #(
    parameter integer N=4
)(output reg done=0,output integer errors=0,output integer checks=0);
    reg clk=0,por_n=0,key_n=1;
    wire release_n;
    localparam integer SHORT=(N>1)?N-1:1;
    secondary_key3_board_reset #(.DEBOUNCE_CYCLES(N)) dut(
        .I_clk(clk),.I_por_n(por_n),.I_key_n(key_n),.O_release(release_n));
    initial while(!done) #10 clk=~clk;
    task tick;begin @(posedge clk);#1;end endtask
    task check(input bit good,input string message);begin
        checks=checks+1;
        if(!good)begin
            errors=errors+1;
            if(errors<=12)$display("FAIL KEY3 N=%0d t=%0t %s release=%b",N,$time,message,release_n);
        end
    end endtask
    task stay(input integer cycles,input bit value,input string message);begin
        repeat(cycles)begin tick;check(release_n===value,message);end
    end endtask
    task drive(input bit value);begin @(negedge clk);key_n=value;end endtask
    // The interface includes two synchronizer stages and one transition
    // capture cycle. A running-key transition is committed on edge N+3.
    task transition(input bit value,input string message);begin
        drive(value);
        stay(N+2,!value,{message," before debounce threshold"});
        tick;check(release_n===value,{message," at debounce threshold"});
    end endtask
    task por_released_boot;begin
        @(negedge clk);por_n=1;
        // With an initially released key there is no transition capture:
        // sample-valid takes two edges, followed by N stable edges.
        stay(N+1,0,"released cold boot remains reset before threshold");
        tick;check(release_n===1,"released cold boot exits at N+2");
    end endtask
    initial begin
        // Force an actual POR assertion event, including at time zero.
        por_n=1;#1;por_n=0;#1;
        check(release_n===0,"POR asserts without waiting for clock");
        stay(4,0,"POR held");
        por_released_boot;
        stay(5,1,"released boot stable");

        // Less than the configured debounce interval must not reset.
        drive(0);stay(SHORT,1,"short press rejected");
        drive(1);stay(N+5,1,"short press recovery does not reset");
        drive(0);stay(1,1,"one-cycle press bounce rejected");
        drive(1);stay(N+5,1,"press bounce does not accumulate");

        transition(0,"stable press");
        stay(N+8,0,"held KEY3 never restarts application");
        // A release bounce must not restart clocks or application state.
        drive(1);stay(SHORT,0,"short release rejected");
        drive(0);stay(N+5,0,"release bounce returns to held reset");
        drive(1);stay(1,0,"one-cycle release bounce rejected");
        drive(0);stay(N+5,0,"release bounce does not accumulate");
        transition(1,"stable release");
        stay(5,1,"stable release remains released");

        transition(0,"second independent press");
        stay(7,0,"second held press");
        transition(1,"second independent release");

        // Reassert POR between edges after the board has already run.
        @(negedge clk);#3;por_n=0;#1;
        check(release_n===0,"POR reassertion is asynchronous");
        stay(3,0,"reasserted POR held");
        por_released_boot;

        // Cold start with KEY3 held never produces a release pulse.
        @(negedge clk);key_n=0;#3;por_n=0;#1;
        check(release_n===0,"POR with KEY3 held asserts reset");
        stay(4,0,"held-key cold POR");
        @(negedge clk);por_n=1;
        stay(N+8,0,"held-key cold boot cannot release");
        transition(1,"held-key cold boot stable release");

        $display("KEY3_CASE_RESULT N=%0d checks=%0d errors=%0d",N,checks,errors);
        if(N==1000000)$display("KEY3_PRODUCTION_THRESHOLD cycles=%0d clk_ns=20 debounce_ns=20000000 transition_edges=1000003",N);
        done=1;
    end
endmodule

module tb_reset_sync_domains(output reg done=0,output integer errors=0,output integer checks=0);
    reg clk_a=0,clk_b=0,run_a=1,run_b=1,async_n=1;
    wire rst_a_n,rst_b_n;
    reset_sync a(.I_clk(clk_a),.I_async_rst_n(async_n),.O_rst_n(rst_a_n));
    reset_sync b(.I_clk(clk_b),.I_async_rst_n(async_n),.O_rst_n(rst_b_n));
    initial while(!done)begin #4;if(run_a)clk_a=~clk_a;else clk_a=0;end
    initial while(!done)begin #7;if(run_b)clk_b=~clk_b;else clk_b=0;end
    task check(input bit good,input string message);begin
        checks=checks+1;
        if(!good)begin errors=errors+1;$display("FAIL RESET_SYNC t=%0t %s A=%b B=%b",$time,message,rst_a_n,rst_b_n);end
    end endtask
    task release_a;begin
        @(posedge clk_a);#0.001;check(rst_a_n===0,"A remains reset after first release edge");
        @(posedge clk_a);#0.001;check(rst_a_n===1,"A releases at second local edge");
    end endtask
    task release_b;begin
        @(posedge clk_b);#0.001;check(rst_b_n===0,"B remains reset after first release edge");
        @(posedge clk_b);#0.001;check(rst_b_n===1,"B releases at second local edge");
    end endtask
    initial begin
        #1;async_n=0;#0.001;
        check(rst_a_n===0&&rst_b_n===0,"initial asynchronous assertion");
        #2;async_n=1;
        fork release_a;release_b;join
        @(negedge clk_a);run_a=0;
        @(negedge clk_b);run_b=0;
        #3;check(clk_a===0&&clk_b===0,"both consumer clocks stopped low");
        async_n=0;#0.001;
        check(rst_a_n===0&&rst_b_n===0,"stopped clocks still asynchronously reset both domains");
        #31;async_n=1;#31;
        check(rst_a_n===0&&rst_b_n===0,"no local clock means no asynchronous release");
        run_a=1;release_a;
        check(rst_b_n===0,"B stays reset while only A clocks");
        run_b=1;release_b;

        // An assertion between release edges cancels the partial release.
        @(negedge clk_a);run_a=0;
        @(negedge clk_b);run_b=0;
        #3;async_n=0;#0.001;
        check(rst_a_n===0&&rst_b_n===0,"second stopped-clock assertion");
        #3;async_n=1;run_a=1;
        @(posedge clk_a);#0.001;
        check(rst_a_n===0,"partial release only one edge");
        #1;async_n=0;#0.001;
        check(rst_a_n===0&&rst_b_n===0,"reassertion cancels partial release");
        #1;async_n=1;
        release_a;
        check(rst_b_n===0,"B still needs own two release edges");
        run_b=1;release_b;
        $display("RESET_SYNC_CASE_RESULT checks=%0d errors=%0d",checks,errors);
        done=1;
    end
endmodule

module tb_key3_reset_unit;
    wire [4:0] done;
    wire [31:0] errors[0:4],checks[0:4];
    tb_key3_debounce_case #(.N(1)) c1(done[0],errors[0],checks[0]);
    tb_key3_debounce_case #(.N(4)) c4(done[1],errors[1],checks[1]);
    tb_key3_debounce_case #(.N(17)) c17(done[2],errors[2],checks[2]);
    tb_key3_debounce_case #(.N(1000000)) production(done[3],errors[3],checks[3]);
    tb_reset_sync_domains domains(done[4],errors[4],checks[4]);
    initial begin
        wait(&done);#1;
        if((errors[0]+errors[1]+errors[2]+errors[3]+errors[4])==0)
            $display("KEY3_RESET_UNIT_PASS cases=5");
        else $display("KEY3_RESET_UNIT_FAIL errors=%0d",errors[0]+errors[1]+errors[2]+errors[3]+errors[4]);
        $finish;
    end
    initial begin #2000000000;$display("KEY3_RESET_UNIT_FAIL watchdog");$finish;end
endmodule
'''


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    assert "work" not in [part.lower() for part in ROOT.parts]
    assert LICENSE.is_file(), "File-based ModelSim license does not exist"
    for name in ("vlib.exe", "vlog.exe", "vsim.exe"):
        assert (SIM / name).is_file(), name
    inputs = [Path(__file__).resolve(), TOP, SYNC]
    hashes = {str(path): sha(path) for path in inputs}
    OUT.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("run_%Y%m%dT%H%M%S_%fZ")
    run = OUT / stamp
    run.mkdir(exist_ok=False)
    captured = run / "inputs"
    captured.mkdir()
    frozen_top, frozen_sync = captured / TOP.name, captured / SYNC.name
    frozen_runner = captured / Path(__file__).name
    shutil.copyfile(TOP, frozen_top)
    shutil.copyfile(SYNC, frozen_sync)
    shutil.copyfile(Path(__file__), frozen_runner)
    assert sha(frozen_top) == hashes[str(TOP)]
    assert sha(frozen_sync) == hashes[str(SYNC)]
    bench = run / "tb_key3_reset_unit.sv"
    bench.write_text(BENCH, encoding="utf-8")
    env = os.environ.copy()
    env["MGLS_LICENSE_FILE"] = "E:/model/win64/LICENSE.TXT"
    env["LM_LICENSE_FILE"] = "E:/model/win64/LICENSE.TXT"
    commands = [
        ("vlib.log", [str(SIM / "vlib.exe"), str(run / "simlib")]),
        ("vlog.log", [str(SIM / "vlog.exe"), "-sv", "-lint", "-work", str(run / "simlib"),
                      str(frozen_top), str(frozen_sync), str(bench)]),
        ("vsim.log", [str(SIM / "vsim.exe"), "-c", "-lib", "simlib",
                      "tb_key3_reset_unit", "-do", "run -all; quit -f"]),
    ]
    errors, warnings, command_results = [], [], []
    begin = time.monotonic()
    for name, command in commands:
        started = time.monotonic()
        try:
            with (run / name).open("w", encoding="utf-8") as log:
                result = subprocess.run(command, cwd=run, env=env, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=180)
            command_results.append({"command": command, "log": name,
                                    "returncode": result.returncode,
                                    "wall_seconds": round(time.monotonic()-started, 3)})
            if result.returncode:
                errors.append(name + " returned " + str(result.returncode))
                break
        except subprocess.TimeoutExpired:
            errors.append(name + " timed out after 180 seconds")
            command_results.append({"command": command, "log": name, "timeout_seconds": 180})
            break
    transcript = (run / "vsim.log").read_text(errors="replace") if (run / "vsim.log").exists() else ""
    cases = [{"debounce_cycles": int(n), "checks": int(count), "errors": int(failed)}
             for n, count, failed in re.findall(r"KEY3_CASE_RESULT N=(\d+) checks=(\d+) errors=(\d+)", transcript)]
    domains = re.findall(r"RESET_SYNC_CASE_RESULT checks=(\d+) errors=(\d+)", transcript)
    if sorted(item["debounce_cycles"] for item in cases) != [1, 4, 17, 1000000]:
        errors.append("Missing debounce parameter cases")
    if len(domains) != 1 or any(int(item) != 0 for _, item in domains):
        errors.append("Reset-sync domains failed or did not complete")
    if any(item["errors"] for item in cases) or "KEY3_RESET_UNIT_PASS cases=5" not in transcript:
        errors.append("RTL assertions did not all pass")
    if re.search(r"\bFAIL\b|\*\* (?:Error|Fatal):", transcript):
        errors.append("Failure marker in simulator transcript")
    # Preserve and disclose native-tool shutdown diagnostics separately from
    # completed RTL assertions. Never treat a nonzero tool exit as a pass.
    if "KEY3_RESET_UNIT_PASS cases=5" in transcript and "# End time:" in transcript:
        shutdown = transcript.rsplit("# End time:", 1)[1]
        if any(marker in shutdown for marker in ("incorrect read of header", "Unexpected EOF on RPC", "Bad pointer access")):
            warnings.append("ModelSim completed with return code 0 but emitted native vish/RPC shutdown diagnostics; full transcript is retained.")
    after = {str(path): sha(path) for path in inputs}
    if hashes != after:
        errors.append("Live inputs changed during simulation; rerun before freezing evidence")
    artifacts = [bench, frozen_top, frozen_sync, frozen_runner]
    artifacts += [run / name for name, _ in commands if (run / name).is_file()]
    evidence = {str(path.relative_to(OUT)): sha(path) for path in artifacts}
    result = {
        "status": "PASS" if not errors else "FAIL", "errors": errors, "warnings": warnings,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "run_directory": str(run), "input_hashes": hashes, "input_hashes_after": after,
        "evidence_hashes": evidence, "command_results": command_results,
        "parameter_cases": cases,
        "reset_sync_case": {"checks": int(domains[0][0]), "errors": int(domains[0][1])} if domains else None,
        "total_checks": sum(item["checks"] for item in cases) + sum(int(count) for count, _ in domains),
        "production_clock_hz": 50000000, "production_debounce_cycles": 1000000,
        "production_debounce_ns": 20000000, "wall_seconds": round(time.monotonic()-begin, 3),
        "scope": "Real FPGA reset RTL only. External GRBL/ESP32 is not reset or modeled.",
        "hardware_status": "NOT_RUN",
    }
    payload = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    (run / "RESULTS.json").write_text(payload, encoding="utf-8")
    (OUT / "RESULTS.json").write_text(payload, encoding="utf-8")
    print(json.dumps({"status": result["status"], "errors": errors, "warnings": warnings, "results": str(OUT / "RESULTS.json"),
                      "results_sha256": sha(OUT / "RESULTS.json"), "parameter_cases": cases,
                      "reset_sync_case": result["reset_sync_case"], "wall_seconds": result["wall_seconds"]}, indent=2))
    raise SystemExit(0 if not errors else 1)


if __name__ == "__main__":
    main()
