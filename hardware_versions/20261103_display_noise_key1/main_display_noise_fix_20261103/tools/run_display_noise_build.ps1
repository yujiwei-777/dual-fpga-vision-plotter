param([ValidateSet('scope','freeze','synth','place','route','gate','readonly','context','review','bitgen','post')][string]$Stage='scope')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$run=Join-Path $root '01_rtl/imgq_gain_m/main/td_project_display_noise_v8'
$audit=Join-Path $root '02_sim/display_noise_readonly'
$context=Join-Path $root '02_sim/display_noise_standard_context'
$name='camera_to_dsi_display_720p60_cnn_multibox'
$python='C:/Users/38401/AppData/Local/Programs/Python/Python311/python.exe'
$td='E:/td/bin/td_commands_prompt.exe'
$generic=Join-Path $PSScriptRoot 'td_release_audit.py'
$config=Join-Path $PSScriptRoot 'release_audit_config.json'
function Python-Step([string[]]$Arguments){ & $python @Arguments; if($LASTEXITCODE){throw ('Audit rejected: '+($Arguments -join ' '))} }
function TD-Step([string]$Script,[string]$Directory,[string]$Log){
    if(Test-Path -LiteralPath $Log){throw ('Refusing to overwrite prior evidence '+$Log)}
    Push-Location $Directory
    try {
        # Windows PowerShell Tee-Object defaults to UTF-16. Keep auditable
        # logs explicitly UTF-8 so all strict TD evidence readers agree.
        & $td $Script.Replace('\','/') 2>&1 | ForEach-Object {
            $line=[string]$_
            Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
            Write-Output $line
        }
        if($LASTEXITCODE){throw 'TD rejected command'}
    } finally {Pop-Location}
}
if($Stage -eq 'scope' -or $Stage -eq 'freeze'){ Python-Step @((Join-Path $PSScriptRoot 'audit_display_noise_scope.py')) }
if($Stage -eq 'freeze'){
    if((Test-Path -LiteralPath (Join-Path $run 'source_snapshot.json')) -or (Test-Path -LiteralPath (Join-Path $run '.read_design.begin.f'))){throw 'Run already frozen or synthesis started; preserve evidence and use a new run'}
    Python-Step @($generic,'snapshot','--root',$root,'--run',$run,'--name',$name,'--config',$config,'--extra',(Join-Path $PSScriptRoot 'inactive_project_files.json'),'--extra',(Join-Path $run 'osd_compact_glyphs.vh'),'--extra',(Join-Path $run 'run_display_noise_synth.tcl'),'--extra',(Join-Path $run 'run_display_noise_place.tcl'),'--extra',(Join-Path $run 'run_display_noise_route.tcl'))
}
if($Stage -eq 'synth' -or $Stage -eq 'place' -or $Stage -eq 'route'){
    Python-Step @((Join-Path $PSScriptRoot 'verify_display_noise_frozen.py'))
    if($Stage -eq 'synth' -and (Test-Path -LiteralPath (Join-Path $run '.read_design.begin.f'))){throw 'Prior synthesis exists; refusing overwrite'}
    if($Stage -eq 'place' -and -not (Test-Path -LiteralPath (Join-Path $run '.opt_gate.end.f'))){throw 'Fresh synthesis is required before place'}
    if($Stage -eq 'route'){ Python-Step @((Join-Path $PSScriptRoot 'check_display_noise_placement.py')) }
    $marker=@{'synth'='.opt_gate.end.f';'place'='.opt_place.end.f';'route'='.opt_route.end.f'}[$Stage]
    TD-Step (Join-Path $run ('run_display_noise_'+$Stage+'.tcl')) $run (Join-Path $run ($Stage+'.log'))
    if(-not (Test-Path -LiteralPath (Join-Path $run $marker))){throw 'TD process ended without required successful step marker'}
    if((Get-ChildItem -LiteralPath $run -Filter '*.error.f' -Force).Count -gt 0){throw 'TD error marker found'}
    if($Stage -eq 'synth'){Python-Step @((Join-Path $PSScriptRoot 'verify_display_noise_build_strategy.py'),'--require-log','--require-snapshot')}
    if($Stage -eq 'place'){Python-Step @((Join-Path $PSScriptRoot 'check_display_noise_placement.py'))}
}
if($Stage -eq 'gate'){
    Python-Step @($generic,'gate','--root',$root,'--run',$run,'--syn-run',$run,'--name',$name,'--snapshot',(Join-Path $run 'source_snapshot.json'),'--config',$config,'--extra',(Join-Path $PSScriptRoot 'inactive_project_files.json'),'--extra',(Join-Path $run 'osd_compact_glyphs.vh'),'--extra',(Join-Path $run 'run_display_noise_synth.tcl'),'--extra',(Join-Path $run 'run_display_noise_place.tcl'),'--extra',(Join-Path $run 'run_display_noise_route.tcl'),'--log',(Join-Path $run 'synth.log'),'--log',(Join-Path $run 'place.log'),'--log',(Join-Path $run 'route.log'))
}
if($Stage -eq 'readonly'){
    Python-Step @((Join-Path $PSScriptRoot 'prepare_display_noise_audit.py'),'readonly')
    TD-Step (Join-Path $audit 'readonly_reimport.tcl') $audit (Join-Path $audit 'console_readonly.log')
    Python-Step @($generic,'verify-readonly','--root',$root,'--run',$run,'--name',$name,'--audit-dir',$audit,'--log',(Join-Path $audit 'console_readonly.log'))
}
if($Stage -eq 'context'){
    Python-Step @((Join-Path $PSScriptRoot 'prepare_display_noise_audit.py'),'context')
    TD-Step (Join-Path $context 'standard_context.tcl') $context (Join-Path $context 'console_standard_context.log')
}
if($Stage -eq 'review'){Python-Step @((Join-Path $PSScriptRoot 'review_display_noise_release.py'))}
if($Stage -eq 'bitgen'){
    Python-Step @((Join-Path $PSScriptRoot 'review_display_noise_release.py'))
    Python-Step @((Join-Path $PSScriptRoot 'prepare_display_noise_audit.py'),'bitgen')
    TD-Step (Join-Path $context 'bitgen.tcl') $context (Join-Path $context 'console_bitgen.log')
}
if($Stage -eq 'post'){Python-Step @((Join-Path $PSScriptRoot 'review_display_noise_release.py'),'--after-bitgen')}
Write-Output ('DISPLAY_NOISE_'+$Stage.ToUpper()+'_COMPLETE')
