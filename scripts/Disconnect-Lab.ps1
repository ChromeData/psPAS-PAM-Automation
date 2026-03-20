<#
.SYNOPSIS
  Close the psPAS session cleanly.
#>
[CmdletBinding()] param()
Import-Module psPAS
if (Get-PASSession) {
  Close-PASSession
  Write-Host "Session closed." -ForegroundColor Green
} else {
  Write-Host "No active session."
}
