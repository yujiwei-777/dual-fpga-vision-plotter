$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$env:MGLS_LICENSE_FILE = 'E:/model/win64/LICENSE.TXT'
$env:LM_LICENSE_FILE = 'E:/model/win64/LICENSE.TXT'
if (!(Test-Path -LiteralPath $env:MGLS_LICENSE_FILE)) { throw 'Missing file license' }
python prepare.py
if ($LASTEXITCODE -ne 0) { throw 'Actual top extraction failed' }
if (!(Test-Path -LiteralPath 'sim_work')) { & 'E:/model/win64/vlib.exe' sim_work }
$rtl = '../../01_rtl/imgq_gain_m/main/user_source/hdl_source'
& 'E:/model/win64/vlog.exe' -work sim_work -sv "$rtl/reset_sync.v" "$rtl/hx_result_select.v" "$rtl/doc_copy_status_cdc.v" "$rtl/key4_hold_debounce.v" tb_pcb_actual_box.sv 2>&1 | Tee-Object compile.log
if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
& 'E:/model/win64/vsim.exe' -c -lib sim_work tb_pcb_actual_box -l transcript.log -do 'onerror {quit -code 2 -f}; run -all; quit -code 0 -f'
if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
$log = Get-Content -Raw transcript.log
if ($log -notmatch 'PASS PCB actual-box integration' -or $log -match '\*\* (Error|Fatal):') { throw 'Missing pass or simulation failure' }
Write-Output 'PCB_ACTUAL_BOX_REGRESSION_PASS'
& 'E:/model/win64/vlog.exe' -work sim_work -sv tb_key4_pcb_oneshot.sv tb_coords_equiv.sv 2>&1 | Tee-Object extra_compile.log
if ($LASTEXITCODE -ne 0) { throw 'Extra test compile failed' }
foreach ($test in @(@('tb_key4_pcb_oneshot','key4_oneshot.log','TB_KEY4_PCB_ONESHOT_PASS'),@('tb_coords_equiv','coordinate_equivalence.log','PASS six-coordinate mux equivalence checks=400012'))) {
    & 'E:/model/win64/vsim.exe' -c -lib sim_work $test[0] -l $test[1] -do 'run -all; quit -code 0 -f'
    if ($LASTEXITCODE -ne 0) { throw "Failed $($test[0])" }
    $testLog = Get-Content -Raw $test[1]
    if ($testLog -notmatch [regex]::Escape($test[2]) -or $testLog -match '\*\* (Error|Fatal):') { throw "Missing pass in $($test[1])" }
}
