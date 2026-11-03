$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$env:MGLS_LICENSE_FILE = 'E:/model/win64/LICENSE.TXT'
$env:LM_LICENSE_FILE = 'E:/model/win64/LICENSE.TXT'
if (!(Test-Path -LiteralPath $env:MGLS_LICENSE_FILE)) { throw 'Missing file-based ModelSim license' }
if (!(Test-Path -LiteralPath 'sim_work')) { & 'E:/model/win64/vlib.exe' sim_work }
& 'E:/model/win64/vlog.exe' -work sim_work -sv '../../01_rtl/imgq_gain_m/shared/rtl/hxa_packet_codec.v' '../../01_rtl/imgq_gain_m/shared/rtl/hxa_main_link.v' tb_link_pcb_wait.sv 2>&1 | Tee-Object -FilePath compile.log
if ($LASTEXITCODE -ne 0) { throw 'Protocol test compile failed' }
& 'E:/model/win64/vsim.exe' -batch -lib sim_work tb_link_pcb_wait -l transcript_batch_final.log -do 'onerror {quit -code 2 -f}; run -all; quit -code 0 -f'
if ($LASTEXITCODE -ne 0) { throw "ModelSim exit code $LASTEXITCODE; inspect complete log before claiming pass" }
$taskLog = Get-Content -Raw -LiteralPath 'transcript_batch_final.log'
if ($taskLog -notmatch 'PASS ALL packet-level PCB compatibility' -or $taskLog -match '\*\* (Error|Fatal):') { throw 'Missing protocol test pass marker or simulator error' }
Write-Output 'PACKET_PCB_WAIT_REGRESSION_PASS'
