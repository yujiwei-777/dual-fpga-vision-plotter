param([ValidateSet('scope','gate','readonly','context','review','bitgen','post')][string]$Stage='scope')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$run=Join-Path $root '01_rtl/imgq_gain_m/main/td_project_pcb_auto_v2'
$audit=Join-Path $root '02_sim/pcb_compat_readonly'
$context=Join-Path $root '02_sim/pcb_compat_standard_context'
$name='camera_to_dsi_display_720p60_cnn_multibox'
$python='C:/Users/38401/AppData/Local/Programs/Python/Python311/python.exe'
$td='E:/td/bin/td_commands_prompt.exe'
$generic=Join-Path $PSScriptRoot 'td_release_audit.py'
function Python-Step([string[]]$Arguments){ & $python @Arguments; if($LASTEXITCODE){throw ('Audit rejected: '+($Arguments -join ' '))} }
function TD-Step([string]$Script,[string]$Directory,[string]$Log){
  if(Test-Path -LiteralPath $Log){throw ('Refusing to overwrite prior evidence '+$Log)}
  Push-Location $Directory
  try { & $td $Script.Replace('\','/') 2>&1 | Tee-Object -FilePath $Log; if($LASTEXITCODE){throw 'TD rejected command'} } finally {Pop-Location}
}
if($Stage -eq 'scope'){ Python-Step @((Join-Path $PSScriptRoot 'audit_pcb_compat_scope.py')) }
if($Stage -eq 'gate'){
  Python-Step @($generic,'gate','--root',$root,'--run',$run,'--syn-run',$run,'--name',$name,'--snapshot',(Join-Path $run 'source_snapshot.json'),'--config',(Join-Path $PSScriptRoot 'release_audit_config.json'),'--log',(Join-Path $run 'synth.log'),'--log',(Join-Path $run 'place.log'),'--log',(Join-Path $run 'route.log'))
}
if($Stage -eq 'readonly'){
  Python-Step @((Join-Path $PSScriptRoot 'prepare_pcb_compat_audit.py'),'readonly')
  TD-Step (Join-Path $audit 'readonly_reimport.tcl') $audit (Join-Path $audit 'console_readonly.log')
  Python-Step @($generic,'verify-readonly','--root',$root,'--run',$run,'--name',$name,'--audit-dir',$audit,'--log',(Join-Path $audit 'console_readonly.log'))
}
if($Stage -eq 'context'){
  Python-Step @((Join-Path $PSScriptRoot 'prepare_pcb_compat_audit.py'),'context')
  TD-Step (Join-Path $context 'standard_context.tcl') $context (Join-Path $context 'console_standard_context.log')
}
if($Stage -eq 'review'){ Python-Step @((Join-Path $PSScriptRoot 'review_pcb_compat_release.py')) }
if($Stage -eq 'bitgen'){
  Python-Step @((Join-Path $PSScriptRoot 'review_pcb_compat_release.py'))
  Python-Step @((Join-Path $PSScriptRoot 'prepare_pcb_compat_audit.py'),'bitgen')
  TD-Step (Join-Path $context 'bitgen.tcl') $context (Join-Path $context 'console_bitgen.log')
}
if($Stage -eq 'post'){ Python-Step @((Join-Path $PSScriptRoot 'review_pcb_compat_release.py'),'--after-bitgen') }
Write-Output ('PCB_COMPAT_'+$Stage.ToUpper()+'_COMPLETE')
