param([string]$Vsim='E:/model/win64/vsim.exe')
$ErrorActionPreference='Stop'
$simRoot=$PSScriptRoot
$licensePath='E:\model\win64\LICENSE.TXT'
if(-not(Test-Path -LiteralPath $licensePath -PathType Leaf)){throw 'Missing file license'}
$env:MGLS_LICENSE_FILE=$licensePath
$env:LM_LICENSE_FILE=$licensePath
$manifest=Get-Content -LiteralPath "$simRoot/vectors_manifest.json" -Raw|ConvertFrom-Json
$candidatePath="$simRoot/a4_display_spatial_nocarry.v"
$frozenPath="$simRoot/a4_display_spatial_frozen.v"
if((Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash -ne 'CD72245FA5CF73F16F35C2F655E5F13DD5F4949D14D258A7B99F9179AA219696'){throw 'Unexpected candidate hash'}
if(Test-Path -LiteralPath "$simRoot/nocarry_lib"){throw 'Library already exists; preserve evidence and use a fresh test directory'}
if(Test-Path -LiteralPath "$simRoot/compile.log"){throw 'compile.log already exists; preserve evidence'}
Push-Location $simRoot
try{
    & 'E:/model/win64/vlib.exe' nocarry_lib *> compile.log
    if($LASTEXITCODE -ne 0){throw 'vlib failed'}
    & 'E:/model/win64/vmap.exe' -c *>> compile.log
    if($LASTEXITCODE -ne 0){throw 'vmap local ini failed'}
    & 'E:/model/win64/vmap.exe' -modelsimini "$simRoot/modelsim.ini" nocarry_lib "$simRoot/nocarry_lib" *>> compile.log
    if($LASTEXITCODE -ne 0){throw 'vmap failed'}
    & 'E:/model/win64/vlog.exe' -modelsimini "$simRoot/modelsim.ini" -work nocarry_lib -sv $candidatePath $frozenPath "$simRoot/tb_display_spatial.sv" *>> compile.log
    if($LASTEXITCODE -ne 0){throw 'vlog failed'}
    $compileLog=Get-Content -LiteralPath "$simRoot/compile.log" -Raw
    if($compileLog -match '\*\* (Warning|Error|Fatal)' -or $compileLog -notmatch 'Errors: 0, Warnings: 0'){throw 'Unclean compilation'}
    foreach($case in $manifest.cases){
        $caseRoot="$simRoot/$($case.name)"
        $stim=($caseRoot+'/stim.mem').Replace('\','/')
        $gold=($caseRoot+'/expected.mem').Replace('\','/')
        $source=($caseRoot+'/source.mem').Replace('\','/')
        & $Vsim -batch -modelsimini "$simRoot/modelsim.ini" nocarry_lib.tb_display_spatial "-gWIDTH=$($case.width)" "-gHEIGHT=$($case.height)" "-gCOUNT=$($case.cycles)" "+STIM=$stim" "+GOLD=$gold" "+SOURCE=$source" -do 'run -all; quit -f' *> "$caseRoot/transcript.log"
        if($LASTEXITCODE -ne 0){throw "vsim failed $($case.name)"}
        $log=Get-Content -LiteralPath "$caseRoot/transcript.log" -Raw
        if($log -notmatch 'frozen_all_cycles_including_invalid_data_equal' -or $log -match '\*\* (Warning|Error|Fatal)' -or $log -notmatch 'Errors: 0, Warnings: 0'){throw "Bad simulation evidence $($case.name)"}
        Write-Host "$($case.name): PASS"
    }
}finally{Pop-Location}
