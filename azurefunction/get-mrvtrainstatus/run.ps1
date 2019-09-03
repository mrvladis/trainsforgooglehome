using namespace System.Net
#Verbose key for Debugging
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$VerbosePreference = "Continue"
function Execute-SOAPRequest
(
    [Xml]    $SOAPRequest,
    [String] $URL
) {
    Write-Verbose "Sending SOAP Request To Server: $URL"
    $soapWebRequest = [System.Net.WebRequest]::Create($URL)
    # $soapWebRequest.Headers.Add("SOAPAction", "`"`"")
    $soapWebRequest.ContentType = "text/xml;charset=utf-8"
    $soapWebRequest.Accept = "text/xml"
    $soapWebRequest.Method = "POST"

    Write-Verbose "Initiating Send."
    $requestStream = $soapWebRequest.GetRequestStream()
    $SOAPRequest.Save($requestStream)
    $requestStream.Close()

    Write-Verbose "Send Complete, Waiting For Response."
    $resp = $soapWebRequest.GetResponse()
    $responseStream = $resp.GetResponseStream()
    $soapReader = [System.IO.StreamReader]($responseStream)
    $ReturnXml = [Xml] $soapReader.ReadToEnd()
    $responseStream.Close()
    
    Write-Verbose "Response Received."
    return $ReturnXml
}

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
# Interact with query parameters or the body of the request.

$transport = $Request.Body.queryResult.parameters.transport
Write-Output "Transport [$transport]"
$period = $Request.Body.queryResult.parameters.period
Write-Output "Period [$period]"
$time = $Request.Body.queryResult.parameters.time
Write-Output "Time [$time]"
$date = $Request.Body.queryResult.parameters.date
Write-Output "Date [$date]"

Write-Output "--------------------------------------------------------------"
Write-Verbose "------Full Request---------"
Write-Verbose $Request
# -------------------------------- Variables ---------------------------------
Write-Verbose "------Setting Variables---------"
$GoogleHomeMessage = ''
$ldbwsendpoint = 'https://lite.realtime.nationalrail.co.uk/OpenLDBWS/ldb11.asmx'

Write-Verbose "------Trying to access token for the SOAP Call from KeyVault [$($ENV:KeyVaultName)] Using Secret [($env:MSI_SECRET)]---------"
$Token = (Invoke-RestMethod -Uri $("https://" + $($ENV:KeyVaultName) + ".vault.azure.net/secrets/" + $($Env:VariableToken) + "?api-version=2016-10-01") -Method GET -Headers @{Authorization = "Bearer $($env:MSI_SECRET)" }).value    

Write-Verbose "------Loading Sample XML File---------"
[xml]$xmlsampleldbws = Get-Content -Path $(join-path "get-mrvtrainstatus" "sampleldbws.xml")
$xmlsampleldbws.Envelope.Header.AccessToken.TokenValue = $token

If ($VerbosePreference -like "Continue") {
    Write-Verbose "----- Saving SOAP request XML File for debugging purposes---------"
    $xmlsampleldbws.Save("ldbws.xml");
}
Write-Verbose "------Executing SAOP request with formed XML File---------"
$trainInfoResponse = Execute-SOAPRequest -URL $ldbwsendpoint  -SOAPRequest $xmlsampleldbws

$CurrentStationName = $trainInfoResponse.Envelope.Body.GetArrBoardWithDetailsResponse.GetStationBoardResult.locationName

$WarningMessage = $trainInfoResponse.Envelope.Body.GetArrBoardWithDetailsResponse.GetStationBoardResult.nrccMessages.message
If (($WarningMessage -ne $null) -and ($WarningMessage -ne '')) {
    $WarningMessage = $WarningMessage.Substring(0, $WarningMessage.IndexOf('<'))
    $GoogleHomeMessage = "It seems like not everything is well with the trains currently. `n"
    $GoogleHomeMessage += "The following warning is advertised for the $CurrentStationName station:  `n"
    $GoogleHomeMessage += $WarningMessage + "`n"
}
$CurrentServices = $trainInfoResponse.Envelope.Body.GetArrBoardWithDetailsResponse.GetStationBoardResult.trainServices.service
if (($CurrentServices -ne $null) -and ($CurrentServices -ne '')) {
    $GoogleHomeMessage += "There are currently $($CurrentServices.Count) services scheduled for $CurrentStationName : "
    foreach ($service in $CurrentServices) { 
        $GoogleHomeMessage += "$($service.sta) $($service.operator) $($service.destination.location.locationName) service running $($service.eta) formed of  $($service.length) carriages.  `n"
    }
}

$Myresponse = [PSCustomObject]@{
    fulfillmentText = $GoogleHomeMessage
}
$status = [HttpStatusCode]::OK

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $status
        Body       = $Myresponse
    })