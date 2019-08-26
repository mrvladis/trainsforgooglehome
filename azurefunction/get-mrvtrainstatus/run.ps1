using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)


function Execute-SOAPRequest 
( 
    [Xml]    $SOAPRequest, 
    [String] $URL 
) { 
    write-host "Sending SOAP Request To Server: $URL" 
    $soapWebRequest = [System.Net.WebRequest]::Create($URL) 
    $soapWebRequest.Headers.Add("SOAPAction", "`"`"")


    $soapWebRequest.ContentType = "text/xml;charset=`"utf-8`"" 
    $soapWebRequest.Accept = "text/xml" 
    $soapWebRequest.Method = "POST" 
        
    write-host "Initiating Send." 
    $requestStream = $soapWebRequest.GetRequestStream() 
    $SOAPRequest.Save($requestStream) 
    $requestStream.Close() 
        
    write-host "Send Complete, Waiting For Response." 
    $resp = $soapWebRequest.GetResponse() 
    $responseStream = $resp.GetResponseStream() 
    $soapReader = [System.IO.StreamReader]($responseStream) 
    $ReturnXml = [Xml] $soapReader.ReadToEnd() 
    $responseStream.Close() 
        
    write-host "Response Received."


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
Write-Output "------Full Request---------"
Write-Output $Request

$ldbwsendpoint = 'https://lite.realtime.nationalrail.co.uk/OpenLDBWS/ldb9.asmx'
[xml]$xmlsampleldbws = Get-Content -Path "sampleldbws.xml"
$xmlsampleldbws.Envelope.Header.AccessToken.TokenValue = $token
Execute-SOAPRequest -URL $ldbwsendpoint  -SOAPRequest $xmlsampleldbws



$name = $Request.Query.Name
if (-not $name) {
    $name = $Request.Body.Name
}

if ($name) {
    $status = [HttpStatusCode]::OK
    $body = "Hello $name"
} else {
    $status = [HttpStatusCode]::BadRequest
    $body = "Please pass a name on the query string or in the request body."
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $status
        Body       = $body
    })
