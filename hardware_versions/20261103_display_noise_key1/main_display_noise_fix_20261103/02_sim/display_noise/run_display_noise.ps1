param([string]$Vsim='E:/model/win64/vsim.exe')
$ErrorActionPreference='Stop'
$simRoot=$PSScriptRoot
$variantRoot=(Resolve-Path "$simRoot/../..").Path
$licensePath='E:\model\win64\LICENSE.TXT'
if(-not(Test-Path -LiteralPath $licensePath -PathType Leaf)){throw 'Missing file license'}
$env:MGLS_LICENSE_FILE=$licensePath
$env:LM_LICENSE_FILE=$licensePath
$manifest=Get-Content "$simRoot/vectors_manifest.json" -Raw|ConvertFrom-Json
$rtlPath="$variantRoot/01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v"
$rtlHash=(Get-FileHash -LiteralPath $rtlPath -Algorithm SHA256).Hash
if($rtlHash -ne $manifest.rtl_sha256){throw 'Vectors do not match current RTL hash'}
if(Test-Path -LiteralPath "$simRoot/sim_work"){throw 'Fresh sim_work already exists; preserve evidence and use a fresh test directory'}
if(Test-Path -LiteralPath "$simRoot/compile.log"){throw 'compile.log already exists; preserve the previous run'}
Push-Location $simRoot
try{
    & 'E:/model/win64/vlib.exe' sim_work *> compile.log
    if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    if(-not(Test-Path -LiteralPath "$simRoot/modelsim.ini")){
        & 'E:/model/win64/vmap.exe' -c *>> compile.log
        if($LASTEXITCODE -ne 0){throw 'vmap local ini failed'}
    }
    & 'E:/model/win64/vmap.exe' -modelsimini "$simRoot/modelsim.ini" sim_work "$simRoot/sim_work" *>> compile.log
    if($LASTEXITCODE -ne 0){throw 'vmap sim_work failed'}
    & 'E:/model/win64/vlog.exe' -work sim_work -sv $rtlPath "$simRoot/tb_display_spatial.sv" *>> compile.log
    if($LASTEXITCODE -ne 0){throw 'vlog failed'}
    foreach($case in $manifest.cases){
        Push-Location "$simRoot/$($case.name)"
        try{
            & $Vsim -batch -modelsimini "$simRoot/modelsim.ini" sim_work.tb_display_spatial "-gWIDTH=$($case.width)" "-gHEIGHT=$($case.height)" "-gCOUNT=$($case.cycles)" -do 'run -all; quit -f' *> transcript.log
            if($LASTEXITCODE -ne 0){throw "vsim failed $($case.name)"}
            $log=Get-Content transcript.log -Raw
            if($log -notmatch 'PASS pixel oracle' -or $log -match '\*\* (Warning|Error|Fatal):' -or $log -notmatch 'Errors: 0, Warnings: 0'){throw "Bad simulation evidence $($case.name)"}
            Write-Host "$($case.name): PASS"
        }finally{Pop-Location}
    }
}finally{Pop-Location}
