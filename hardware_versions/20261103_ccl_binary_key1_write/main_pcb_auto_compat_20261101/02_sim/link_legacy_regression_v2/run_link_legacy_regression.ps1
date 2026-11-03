$ErrorActionPreference = 'Stop'
$simRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $simRoot)
$workspaceRoot = Split-Path -Parent $projectRoot
$rtlRoot = Join-Path $projectRoot '01_rtl\imgq_gain_m\shared\rtl'
$licensePath = 'E:\model\win64\LICENSE.TXT'
if (-not (Test-Path -LiteralPath $licensePath -PathType Leaf)) { throw 'ModelSim file license missing' }
$env:MGLS_LICENSE_FILE = $licensePath
$env:LM_LICENSE_FILE = $licensePath
$sourceFiles = @(
    (Join-Path $rtlRoot 'hxa_packet_codec.v'),
    (Join-Path $rtlRoot 'hxa_main_link.v')
)
# Reuse the reviewed Type15 TB without regenerating it.
if ($LASTEXITCODE) { throw 'Document Type15 test preparation failed' }
$testFiles = @('tb_hxa_main_stability.sv', 'tb_hxa_main_startup_regression.sv', 'tb_hxa_main_document_type15.sv') | ForEach-Object { Join-Path $simRoot $_ }
$baselineTests = @(
    (Join-Path $workspaceRoot 'main_link_stability_20261020\02_sim\tb_hxa_main_stability.sv'),
    (Join-Path $workspaceRoot 'main_link_stability_20261020\02_sim\startup_regression\tb_hxa_main_startup_regression.sv')
)
$expectedLinkHash = '60362844CDEDF666F75C2B5019405C2844D6EEEA1A0F8C4F03F220DC7C1FB740'
if ((Get-FileHash -LiteralPath $sourceFiles[1] -Algorithm SHA256).Hash -ne $expectedLinkHash) { throw 'Frozen production link hash changed' }
$hashesBefore = @($sourceFiles + $testFiles + $baselineTests | ForEach-Object { Get-FileHash -LiteralPath $_ -Algorithm SHA256 })
$library = Join-Path $simRoot 'msim_link_legacy'
Push-Location $simRoot
try {
    if (-not (Test-Path -LiteralPath $library)) {
        & 'E:\model\win64\vlib.exe' $library
        if ($LASTEXITCODE) { throw 'vlib failed' }
    }
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & 'E:\model\win64\vmap.exe' -c
        if ($LASTEXITCODE) { throw 'vmap ini creation failed' }
    }
    & 'E:\model\win64\vmap.exe' link_legacy $library
    if ($LASTEXITCODE) { throw 'vmap failed' }
    & 'E:\model\win64\vlog.exe' -sv -work $library -l 'link_legacy_compile.log' @sourceFiles @testFiles
    if ($LASTEXITCODE) { throw 'vlog failed' }
    $cases = @(
        @{Name='ordinary_stability'; Top='tb_hxa_main_stability'; Args=@(); Pass='PASS tb_hxa_main_stability'},
        @{Name='startup_fault_0'; Top='tb_hxa_main_startup_regression'; Args=@('-gFAULT_KIND=0'); Pass='PASS tb_hxa_main_startup_regression FAULT_KIND=0'},
        @{Name='startup_fault_1'; Top='tb_hxa_main_startup_regression'; Args=@('-gFAULT_KIND=1'); Pass='PASS tb_hxa_main_startup_regression FAULT_KIND=1'},
        @{Name='startup_fault_2'; Top='tb_hxa_main_startup_regression'; Args=@('-gFAULT_KIND=2'); Pass='PASS tb_hxa_main_startup_regression FAULT_KIND=2'},
        @{Name='document_type15'; Top='tb_hxa_main_document_type15'; Args=@(); Pass='PASS tb_hxa_main_document_type15'}
    )
    $results = @()
    foreach ($case in $cases) {
        $logPath = Join-Path $simRoot ($case.Name + '.log')
        & 'E:\model\win64\vsim.exe' -batch ('link_legacy.' + $case.Top) @($case.Args) -l $logPath -do 'run -all; quit -f'
        $exitCode = $LASTEXITCODE
        $logText = Get-Content -LiteralPath $logPath -Raw
        $passed = $exitCode -eq 0 -and $logText.Contains($case.Pass) -and $logText -notmatch '(?im)^\s*(#\s*)?\*\*\s+(Error|Fatal):'
        $results += [pscustomobject]@{case=$case.Name; passed=$passed; exit_code=$exitCode; log=$logPath}
        $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath 'link_legacy_results.json' -Encoding utf8
        if (-not $passed) { throw ('Link regression failed: ' + $case.Name) }
    }
    $hashesAfter = @($sourceFiles + $testFiles + $baselineTests | ForEach-Object { Get-FileHash -LiteralPath $_ -Algorithm SHA256 })
    for ($index = 0; $index -lt $hashesBefore.Count; $index++) {
        if ($hashesBefore[$index].Hash -ne $hashesAfter[$index].Hash) { throw ('Input changed during simulation: ' + $hashesBefore[$index].Path) }
    }
    @{
        scope='Real active hxa_main_link and hxa_packet_codec; deterministic snapshot/MAC/peer models at external module boundary; default PCB_CONTINUOUS=0 and PCB_KEY_ONESHOT=0.'
        production_source_unchanged=$true
        inputs=$hashesAfter | Select-Object Path,Hash
        tests=$results
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath 'link_legacy_input_manifest.json' -Encoding utf8
    Write-Output 'LINK_LEGACY_REGRESSION_VERIFIED cases=5'
} finally { Pop-Location }

