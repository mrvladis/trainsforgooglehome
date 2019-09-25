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
        Write-Output "No MSI Endpoint provided, checking in Environment Variables"
        $MSIEndpoint = $env:MSI_ENDPOINT
        if (($MSIEndpoint) -eq $null -or ($MSIEndpoint -eq "")) {
            Write-Error "Can't find MSI endpoint in System Variables"
            return $result
        }
    }
    If (($MSISecret -eq $null) -or ($MSISecret -eq "")) {
        Write-Output "No MSI Secret provided, checking in Environment Variables"
        $MSISecret = $env:MSI_SECRET
        if (($MSIEndpoint) -eq $null -or ($MSIEndpoint -eq "")) {
            Write-Error "Can't find MSI Secret in System Variables"
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
# Extract parameters from the body of the request.
$transport = $Request.Body.queryResult.parameters.transport
Write-Output "Transport [$transport]"
$period = $Request.Body.queryResult.parameters.period
Write-Output "Period [$period]"
$direction = $Request.Body.queryResult.parameters.direction
Write-Output "Direction [$direction]"
$station = $Request.Body.queryResult.parameters.station
Write-Output "Station [$station]"
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
$FilterByCurrentStation = $false
$destinationPreposition = $($ENV:destinationPreposition)
$currentPreposition = $($ENV:currentPreposition)
$DefaultTimeFrame = $($ENV:DefaultTimeFrame)
$ldbwsEndpoint = $($ENV:ldbwsendpoint)
Write-Output "------Trying to access token for the SOAP Call from KeyVault [$($ENV:KeyVaultName)] Using Secret [$($env:MSI_SECRET)]---------"
$Token = (Invoke-RestMethod -Uri $("https://" + $($ENV:KeyVaultName) + ".vault.azure.net/secrets/" + $($Env:TokenName) + "?api-version=2016-10-01") -Method GET -Headers @{Authorization = "Bearer $accessToken" }).value

Write-Output "------Loading Station Codes File---------"
$StationCodes = Import-Csv -Path $(join-path "get-mrvtrainstatus" "station_codes.csv")
Write-Output "------Loading Sample XML File---------"
[xml]$xmlsampleldbws = Get-Content -Path $(join-path "get-mrvtrainstatus" "sampleldbws.xml")

<# 
$direction = @("from", "to")
$station = @("Moorgate", "Oakleigh Park")
    #>


If (($direction.Count -ge 2) -and ($station.Count -ge 2)) {
    $destination = $station[$direction.IndexOf($destinationPreposition)]
    $currentStation = $station[$direction.IndexOf($currentPreposition)]
    Write-Output "Destination Station identified as [$destination]"
    Write-Output "Current Station identified as [$currentStation]"
# } elseif (($direction.Count -eq 1 -and ($station.Count -eq 1))) {
#     if ($direction[0] -like $destinationPreposition ) {
#         Write-Output "Request only has a destination station. Falling back to predefined source station"
#         $destination = $station[0]
#     }  
# }

if (($destination -ne '') -and ($destination -ne $null)) { 
    $DestinationCode = ($StationCodes | ? "Station Name" -like $destination)."CRS Code"
    if (($DestinationCode -ne '') -and ($DestinationCode -ne $null)) {
        Write-Output "Destination Station code identified as [$DestinationCode]"
        $FilterByDestination = $true
    }
}

if ($FilterByDestination) {
    Write-Output "Preparing SOAP payload to use Destination Station code [$DestinationCode]"
    $xmlsampleldbws.Envelope.Body.GetDepBoardWithDetailsRequest.filterCrs = $DestinationCode
} else {
    Write-Output "Removing Destination Station Properties from SOAP payload"
    $NodeFilterCrs = $xmlsampleldbws.Envelope.Body.GetDepBoardWithDetailsRequest.Item("ldb:filterCrs")
    $xmlsampleldbws.Envelope.Body.GetDepBoardWithDetailsRequest.RemoveChild($NodeFilterCrs)
    $NodeFilterCrs = $xmlsampleldbws.Envelope.Body.GetDepBoardWithDetailsRequest.Item("ldb:filterType")
    $xmlsampleldbws.Envelope.Body.GetDepBoardWithDetailsRequest.RemoveChild($NodeFilterCrs)
}

if (($currentStation -ne '') -and ($currentStation -ne $null)) { 
    $currentStationCode = ($StationCodes | ? "Station Name" -like $currentStation)."CRS Code"
    if (($currentStationCode -ne '') -and ($currentStationCode -ne $null)) {
        Write-Output "Current Station code identified as [$currentStationCode]"
        $FilterBycurrentStation = $true
    }
}

if ($FilterBycurrentStation) {
    Write-Output "Preparing SOAP payload to use Current Station code [$currentStationCode]"
    $xmlsampleldbws.Envelope.Body.GetDepBoardWithDetailsRequest.crs = $currentStationCode
}
Write-Output "------Preparing XML Request---------"
$xmlsampleldbws.Envelope.Header.AccessToken.TokenValue = $token
$xmlsampleldbws.Envelope.Body.GetDepBoardWithDetailsRequest.timeWindow = $DefaultTimeFrame

If ($VerbosePreference -like "Continue") {
    Write-Output "----- Saving SOAP request XML File for debugging purposes---------"
    # $xmlsampleldbws.Save("ldbws.xml")
}
Write-Output "------Executing SAOP request with formed XML File---------"
$trainInfoResponse = Execute-SOAPRequest -URL $ldbwsendpoint  -SOAPRequest $xmlsampleldbws

# [xml]$trainInfoResponse = Get-Content -Path $(join-path "get-mrvtrainstatus" "sampleResponseldbws.xml")
If ($VerbosePreference -like "Continue") {
    Write-Output "----- Saving SOAP response XML File for debugging purposes---------"
    # $trainInfoResponse | Out-File -Append $(join-path "get-mrvtrainstatus" "trainInfoResponse.xml")
    # Write-Output $trainInfoResponse
}
$CurrentStationName = $trainInfoResponse.Envelope.Body.GetDepBoardWithDetailsResponse.GetStationBoardResult.locationName
$WarningMessage = $trainInfoResponse.Envelope.Body.GetDepBoardWithDetailsResponse.GetStationBoardResult.nrccMessages.message
If (($WarningMessage -ne $null) -and ($WarningMessage -ne '')) {
    if ($WarningMessage.'#cdata-section') {
        $WarningMessage = $WarningMessage.'#cdata-section'
    } else {
        Write-Output "Using just message"
    }
    $WarningMessage = $WarningMessage.Substring(0, $WarningMessage.IndexOf('<'))
    $GoogleHomeMessage = "It seems like not everything is well with the trains currently. `n"
    $GoogleHomeMessage += "The following warning is advertised for the $CurrentStationName station:  `n"
    $GoogleHomeMessage += $WarningMessage + "`n"
    Write-Output "Warning Message [$WarningMessage]"
    Write-Output "Warning Message Type [$($WarningMessage.gettype())]"
    Write-Output "Warning Message Type [$($WarningMessage.lenght)]"
}
$CurrentServices = $trainInfoResponse.Envelope.Body.GetDepBoardWithDetailsResponse.GetStationBoardResult.trainServices.service
if (($CurrentServices -ne $null) -and ($CurrentServices -ne '')) {
    $GoogleHomeMessage += "There are currently $($CurrentServices.Count) services scheduled from $CurrentStationName within the next $DefaultTimeFrame minutes: "
    foreach ($service in $CurrentServices) { 
        if (($service.etd) -like 'Cancelled') {
            $message = "$($service.std) $($service.operator) $($service.destination.location.locationName) service has been $($service.etd).  `n"
        } else {
            $message = "$($service.std) $($service.operator) $($service.destination.location.locationName) service running $($service.etd) formed of  $($service.length) carriages.  `n"
        }
        $GoogleHomeMessage += $message
        Write-Output $message
    }
} else {
    $message = "There are currently no direct services scheduled within the next $DefaultTimeFrame minutes from $currentStation to $destination  `n"
    $GoogleHomeMessage += $message
    Write-Output $message
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