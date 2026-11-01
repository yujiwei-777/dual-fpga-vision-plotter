$ErrorActionPreference='Stop'
$simRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$rtl=Join-Path (Split-Path -Parent (Split-Path -Parent $simRoot)) '01_rtl/imgq_gain_m/main/user_source/hdl_source'
$license='E:/model/win64/LICENSE.TXT'
if(!(Test-Path -LiteralPath $license -PathType Leaf)){throw 'missing file license'}
$env:MGLS_LICENSE_FILE=$license
$env:LM_LICENSE_FILE=$license
Push-Location $simRoot
try {
    & python ./prepare_mixer.py
    if($LASTEXITCODE){throw 'harness generation failed'}
    if(!(Test-Path -LiteralPath 'msim')){& E:/model/win64/vlib.exe msim;if($LASTEXITCODE){throw 'vlib failed'}}
    if(!(Test-Path -LiteralPath 'modelsim.ini')){& E:/model/win64/vmap.exe -c;if($LASTEXITCODE){throw 'vmap failed'}}
    & E:/model/win64/vmap.exe mixreg msim
    $files=Get-Content -LiteralPath compile_sources.txt
    & E:/model/win64/vlog.exe -sv -work msim -l compile.log "+incdir+$rtl" "+incdir+$simRoot" @files
    if($LASTEXITCODE){throw 'compile failed'}
    & E:/model/win64/vsim.exe -batch -voptargs=+acc mixreg.tb_mixer_regression -l simulation.log -do 'run -all; quit -f'
    if($LASTEXITCODE){throw 'simulation failed'}
    $log=Get-Content -LiteralPath simulation.log -Raw
    if($log -match '(?im)^\s*(#\s*)?\*\*\s+(Error|Fatal):' -or $log -notmatch 'TB_MIXER_REGRESSION_PASS'){throw 'no clean PASS'}
} finally {Pop-Location}
