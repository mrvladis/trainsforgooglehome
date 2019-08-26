Write-Output " [$((Get-variable EXECUTION_CONTEXT_FUNCTIONNAME -ErrorAction SilentlyContinue ).value)] : PowerShell function executed at:$(get-date)";
# Get an access token for the MSI
$requestBody = Get-Content $fnrequest -Raw | ConvertFrom-Json
$Simulate = $requestBody.Simulate
$UserPrincipalName = $requestBody.UserPrincipalName
$DirectoryID = $requestBody.DirectoryID
$Success = $true

Write-Output " [$((Get-variable EXECUTION_CONTEXT_FUNCTIONNAME -ErrorAction SilentlyContinue ).value)] : Endpoint: [$($env:MSI_ENDPOINT)]"
$MSIToken = Get-MRVAzureMSIToken -MSISecret "$env:MSI_SECRET" -MSIEndpoint "$env:MSI_ENDPOINT" -resourceURI 'https://vault.azure.net'
If ($MSIToken.result) {
    Write-Output " [$((Get-variable EXECUTION_CONTEXT_FUNCTIONNAME -ErrorAction SilentlyContinue ).value)] : Successfully acquired the MSI Token"
    $accessToken = $MSIToken.Token
} else {
    Write-Error "Failed to get a token"
    return $false
}

Write-Output " [$((Get-variable EXECUTION_CONTEXT_FUNCTIONNAME -ErrorAction SilentlyContinue ).value)] : PSedition [$($PSVersionTable.PsEdition)]"

$currentTime = get-date
Write-Output " [$((Get-variable EXECUTION_CONTEXT_FUNCTIONNAME -ErrorAction SilentlyContinue ).value)] : Function started at [$currentTime]"

$access_token = (Invoke-RestMethod -Uri $("https://" + $($ENV:KeyVaultName) + ".vault.azure.net/secrets/" + $($Env:Secret_access_token) + "?api-version=2016-10-01") -Method GET -Headers @{Authorization = "Bearer $($MSIToken.token)" }).value    
 
$time_end = Get-Date
Write-Output " [$((Get-variable EXECUTION_CONTEXT_FUNCTIONNAME -ErrorAction SilentlyContinue ).value)] :Function finished at [$time_end]"
Write-Output " [$((Get-variable EXECUTION_CONTEXT_FUNCTIONNAME -ErrorAction SilentlyContinue ).value)] :Function has been running for $(($time_end - $currentTime).Hours) Hours and $(($time_end - $currentTime).Minutes) Minutes"
$Reason = "Completed Successfully"
$result = @{Result = $Success; Reason = $Reason; ResourceID = $ResourceID; Error = $($Error[0]) }
Out-File -Encoding Ascii -FilePath $fnresult -inputObject $result