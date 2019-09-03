using namespace System.Net
#Verbose key for Debugging
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$VerbosePreference = "Continue"
Function Get-MRVAzureMSIToken {
    param(
        [Parameter(Mandatory = $false)]
        [String]
        $apiVersion = "2017-09-01",
        [Parameter(Mandatory = $false)]
        [String]
        $resourceURI = "https://management.azure.com/",
        [Parameter(Mandatory = $false)]
        [String]
        $MSISecret,
        [Parameter(Mandatory = $false)]
        [String]
        $MSIEndpoint,
        [Parameter(Mandatory = $false)]
        [switch]
        $VMMSI
    )
    $result = @{Result = $false; Token = $null; Reason = 'Failed to get token' }
    If ($VMMSI) {
        Write-Output "Runining in Context of the VM"
        If (($MSIEndpoint -eq $null) -or ($MSIEndpoint -eq "")) {
            Write-Output "No MSI endpoint provided. Assuming default one for the VM"
            $MSIEndpoint = 'http://localhost:50342/oauth2/token'
        }
    }
    If (($MSIEndpoint -eq $null) -or ($MSIEndpoint -eq "")) {
        Write-Output "No MSI Endpont provided, checking in Environment Variables"
        $MSIEndpoint = $env:MSI_ENDPOINT
        if (($MSIEndpoint) -eq $null -or ($MSIEndpoint -eq "")) {
            Write-Error "Can't find MSI endpoint in System Variables"
            return $result
        }
    }
    If (($MSISecret -eq $null) -or ($MSISecret -eq "")) {
        Write-Output "No MSI Endpont provided, checking in Environment Variables"
        $MSISecret = $env:MSI_SECRET
        if (($MSIEndpoint) -eq $null -or ($MSIEndpoint -eq "")) {
            Write-Error "Can't find MSI endpoint in System Variables"
            return $result
        }
    }
    Write-Output "Endpoint: [$MSIEndpoint]"
    If ($VMMSI) {
        $response = Invoke-WebRequest -Uri $MSIEndpoint -Method GET -Body @{resource = $resourceURI } -Headers @{Metadata = "true" }
        $content = $response.Content | ConvertFrom-Json
        $accessToken = $content.access_token
    } else {
        $tokenAuthURI = $MSIEndpoint + "?resource=$resourceURI&api-version=$apiVersion"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret" = "$env:MSI_SECRET" } -Uri $tokenAuthURI
        $accessToken = $tokenResponse.access_token
    }


    if (($accessToken -eq $null) -or ($accessToken -eq "")) {
        Write-Error "Failed to get Token. It is empty [$accessToken]"
        return $result
    } else {
        $result = @{Result = $true; Token = $accessToken; Reason = 'Success' }
        return $result
    }
}
function Execute-SOAPRequest { 
    param(
        [Xml]    $SOAPRequest,
        [String] $URL
    ) 
    Write-Output "Sending SOAP Request To Server: $URL"
    $soapWebRequest = [System.Net.WebRequest]::Create($URL)
    # $soapWebRequest.Headers.Add("SOAPAction", "`"`"")
    $soapWebRequest.ContentType = "text/xml;charset=utf-8"
    $soapWebRequest.Accept = "text/xml"
    $soapWebRequest.Method = "POST"

    Write-Output "Initiating Send."
    $requestStream = $soapWebRequest.GetRequestStream()
    $SOAPRequest.Save($requestStream)
    $requestStream.Close()

    Write-Output "Send Complete, Waiting For Response."
    $resp = $soapWebRequest.GetResponse()
    $responseStream = $resp.GetResponseStream()
    $soapReader = [System.IO.StreamReader]($responseStream)
    $ReturnXml = [Xml] $soapReader.ReadToEnd()
    $responseStream.Close()
    
    Write-Output "Response Received."
    return $ReturnXml
}

<# Write-Output "Loading Modules"
Measure-Command { `
        Write-Output "Loading MRVModule"
    Import-Module "mrv_module" -Global;
} | Select-Object Minutes, Seconds, Milliseconds
Write-Output "All Modules loaded."
 #>
Write-Output "Endpoint: [$($env:MSI_ENDPOINT)]"
$MSIToken = Get-MRVAzureMSIToken -MSISecret "$env:MSI_SECRET" -MSIEndpoint "$env:MSI_ENDPOINT" -resourceURI 'https://vault.azure.net'
If ($MSIToken.result) {
    Write-Output "Successfully acquired the MSI Token"
    $accessToken = $MSIToken.Token
} else {
    Write-Error "Failed to get a token"
    return $false
}
# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
# Interact with query parameters or the body of the request.

$transport = $Request.Body.queryResult.parameters.transport
Write-Output "Transport [$transport]"
$period = $Request.Body.queryResult.parameters.period
Write-Output "Period [$period]"
$destination = $Request.Body.queryResult.parameters.destination
Write-Output "Period [$destination]"
$currentStation = $Request.Body.queryResult.parameters.currentStation
Write-Output "Period [$currentStation]"
$time = $Request.Body.queryResult.parameters.time
Write-Output "Time [$time]"
$date = $Request.Body.queryResult.parameters.date
Write-Output "Date [$date]"

Write-Output "--------------------------------------------------------------"
Write-Output "------Full Request---------"
Write-Output $Request
# -------------------------------- Variables ---------------------------------
Write-Output "------Setting Variables---------"
$GoogleHomeMessage = ''
$FilterByDestination = $false
$FilterByCurrent = $false

$DefaultTimeFrame = 15
$destinationPrepositions = @('to ', 'destination ')
$currentPrepositions = @('from ', 'destination ')
$ldbwsendpoint = 'https://lite.realtime.nationalrail.co.uk/OpenLDBWS/ldb11.asmx'

Write-Output "------Trying to access token for the SOAP Call from KeyVault [$($ENV:KeyVaultName)] Using Secret [($env:MSI_SECRET)]---------"
$Token = (Invoke-RestMethod -Uri $("https://" + $($ENV:KeyVaultName) + ".vault.azure.net/secrets/" + $($Env:VariableToken) + "?api-version=2016-10-01") -Method GET -Headers @{Authorization = "Bearer $accessToken" }).value    

Write-Output "------Loading Station Codes File---------"
$StationCodes = Import-Csv -Path $(join-path "get-mrvtrainstatus" "station_codes.csv")
Write-Output "------Loading Sample XML File---------"
[xml]$xmlsampleldbws = Get-Content -Path $(join-path "get-mrvtrainstatus" "sampleldbws.xml")

if (($destination -ne '') -and ($destination -ne $null)) { 
    foreach ($Preposition in $destinationPrepositions) {
        $destination = $destination.Replace($Preposition, '')
    }
    $DestinationCode = ($StationCodes | ? "Station Name" -like $destination)."CRS Code"
    if ($DestinationCode -ne '') {
        $FilterByDestination = $true
    }
}

if ($FilterByDestination) {
    $xmlsampleldbws.Envelope.Body.GetArrBoardWithDetailsRequest.filterCrs = $DestinationCode
} else {
    $NodeFilterCrs = $xmlsampleldbws.Envelope.Body.GetArrBoardWithDetailsRequest.Item("ldb:filterCrs")
    $xmlsampleldbws.Envelope.Body.GetArrBoardWithDetailsRequest.RemoveChild($NodeFilterCrs)
    $NodeFilterCrs = $xmlsampleldbws.Envelope.Body.GetArrBoardWithDetailsRequest.Item("ldb:filterType")
    $xmlsampleldbws.Envelope.Body.GetArrBoardWithDetailsRequest.RemoveChild($NodeFilterCrs)
}

Write-Output "------Preparing XML Request---------"
$xmlsampleldbws.Envelope.Header.AccessToken.TokenValue = $token
$xmlsampleldbws.Envelope.Body.GetArrBoardWithDetailsRequest.timeWindow = $DefaultTimeFrame

If ($VerbosePreference -like "Continue") {
    Write-Output "----- Saving SOAP request XML File for debugging purposes---------"
    $xmlsampleldbws.Save("ldbws.xml")
}
Write-Output "------Executing SAOP request with formed XML File---------"
$trainInfoResponse = Execute-SOAPRequest -URL $ldbwsendpoint  -SOAPRequest $xmlsampleldbws
If ($VerbosePreference -like "Continue") {
    Write-Output "----- Saving SOAP response XML File for debugging purposes---------"
    $trainInfoResponse | Out-File -Append $(join-path "get-mrvtrainstatus" "trainInfoResponse.xml")
    Write-Output $trainInfoResponse
}
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
    
    
    $GoogleHomeMessage += "There are currently $($CurrentServices.Count) services scheduled from $CurrentStationName within the next $DefaultTimeFrame minutes : "
    
    foreach ($service in $CurrentServices) { 
        if (($service.eta) -like 'Cancelled') {
            $message = "$($service.sta) $($service.operator) $($service.destination.location.locationName) service has been $($service.eta).  `n"
        } else {
            $message = "$($service.sta) $($service.operator) $($service.destination.location.locationName) service running $($service.eta) formed of  $($service.length) carriages.  `n"
        }
        $GoogleHomeMessage += $message
        Write-Output $message
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