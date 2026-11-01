param([ValidateSet('synth','place','route','gate','readonly')][string]$Stage='synth')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$run=Join-Path $root '01_rtl/imgq_gain_m/main/td_project_compact_v2'
$audit=Join-Path $root '02_sim/compact_readonly_v2'
$name='camera_to_dsi_display_720p60_cnn_multibox'
$python='C:/Users/38401/AppData/Local/Programs/Python/Python311/python.exe'
$td='E:/td/bin/td_commands_prompt.exe'
$auditTool=Join-Path $PSScriptRoot 'td_release_audit.py'
$config=Join-Path $PSScriptRoot 'release_audit_config.json'
if($Stage -eq 'synth'){
    if(Test-Path -LiteralPath (Join-Path $run '.read_design.begin.f')){throw 'Existing build evidence found. Use a fresh independent run rather than overwriting it.'}
    & $python (Join-Path $PSScriptRoot 'prepare_compact_build.py')
    if($LASTEXITCODE){throw 'Build preparation failed'}
    & $python (Join-Path $PSScriptRoot 'audit_osd_scope.py')
    if($LASTEXITCODE){throw 'Non-OSD source isolation audit failed'}
    & $python $auditTool snapshot --root $root --run $run --name $name --config $config --extra (Join-Path $root '01_rtl/imgq_gain_m/main/user_source/hdl_source/osd_compact_glyphs.vh') --extra (Join-Path $run 'osd_compact_glyphs.vh')
    if($LASTEXITCODE){throw 'Prebuild source snapshot rejected'}
}
if($Stage -eq 'place' -or $Stage -eq 'route'){
    if(-not(Test-Path -LiteralPath (Join-Path $run '.opt_gate.end.f'))){throw 'Fresh synthesis is not complete'}
    if($Stage -eq 'route'){
        if(-not(Test-Path -LiteralPath (Join-Path $run '.opt_place.end.f'))){throw 'Fresh placement is not complete'}
        & $python (Join-Path $PSScriptRoot 'check_placement_resources.py')
        if($LASTEXITCODE){throw 'Actual placement resource gate rejected'}
    }
    & $python (Join-Path $PSScriptRoot 'verify_compact_frozen.py')
    if($LASTEXITCODE){throw 'Frozen input drift before route'}
}
if($Stage -eq 'synth' -or $Stage -eq 'place' -or $Stage -eq 'route'){
    $script=Join-Path $run ('run_compact_'+$Stage+'.tcl')
    Push-Location $run
    try {
        & $td $script.Replace('\','/') 2>&1 | Tee-Object -FilePath (Join-Path $run ('console_compact_'+$Stage+'.log'))
        if($LASTEXITCODE){throw ('TD '+$Stage+' failed')}
    } finally {Pop-Location}
    if($Stage -eq 'place'){
        & $python (Join-Path $PSScriptRoot 'check_placement_resources.py')
        if($LASTEXITCODE){throw 'Actual placement resource gate rejected. No route or bitgen.'}
    }
}
if($Stage -eq 'gate'){
    & $python $auditTool gate --root $root --run $run --syn-run $run --name $name --snapshot (Join-Path $run 'source_snapshot.json') --config $config --log (Join-Path $run 'console_compact_synth.log') --log (Join-Path $run 'console_compact_route.log')
    if($LASTEXITCODE){throw 'Timing/resource/source release gate rejected. No bitgen.'}
}
if($Stage -eq 'readonly'){
    & $python (Join-Path $PSScriptRoot 'verify_compact_frozen.py')
    if($LASTEXITCODE){throw 'Frozen source drift before read-only import'}
    & $python $auditTool reimport-template --root $root --run $run --name $name --audit-dir $audit
    if($LASTEXITCODE){throw 'Read-only template preparation failed'}
    & $python (Join-Path $PSScriptRoot 'prepare_compact_readonly.py')
    if($LASTEXITCODE){throw 'Supplementary read-only preparation failed'}
    Push-Location $audit
    try {
        & $td ((Join-Path $audit 'readonly_reimport.tcl').Replace('\','/')) 2>&1 | Tee-Object -FilePath (Join-Path $audit 'console_readonly.log')
        if($LASTEXITCODE){throw 'Read-only TD import failed'}
    } finally {Pop-Location}
    & $python $auditTool verify-readonly --root $root --run $run --name $name --audit-dir $audit --log (Join-Path $audit 'console_readonly.log')
    if($LASTEXITCODE){throw 'Read-only unchanged-input/timing check failed'}
    & $python (Join-Path $PSScriptRoot 'verify_compact_physical.py')
    if($LASTEXITCODE){throw 'Supplementary physical/CDC/FIFO/DDR/DRC audit failed'}
}
Write-Output ('COMPACT_'+$Stage.ToUpper()+'_COMPLETE_NO_AUTOMATIC_BITGEN')
