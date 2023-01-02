# 
$controllers = @(   "<FQDN or ip>"
                )

$LogList = @("Security")

$cred_file_path = ".\cred.xml"

$events_array =@(4624,4625,4634,4688,4648,4678)


function New-Credentials {
    if (Test-Path -Path $cred_file_path -PathType Any){
        $ConnectorCredentials = Import-Clixml -Path $cred_file_path
    }
    else {
        $ConnectorCredentials = get-Credential
        $ConnectorCredentials | Export-Clixml -Path $cred_file_path
    }
}

function Get-eventsFromDC {
    #
    $HT =@{}
    $ConnectorCredentials = Import-Clixml -Path $cred_file_path
    ForEach ($controller in $controllers){
        ForEach ($Log in $LogList){
            $collectedEvents = Get-WinEvent -LogName $Log -ComputerName $controller -Credential $ConnectorCredentials -MaxEvents 50
            foreach ($collectedEvent in $collectedEvents){
                $collectedEvent.Message > .\tmp\message.txt
                ./evtx-coverter.ps1
                $contenet = Get-Content -Path .\tmp\1.json | ConvertFrom-Json
                $json = $collectedEvent | Select-Object -Property * -ExcludeProperty "Properties", "Message"  | ConvertTo-Json
                $HT =   $json |ConvertFrom-Json
                $HT.TimeCreated = $HT.TimeCreated.toString("yyyy-MM-dd-hh-mm-ss")
                $HT | Add-Member -MemberType NoteProperty -Name "Message" -Value $contenet 
                $converted = $HT | ConvertTo-Json 
                Send-docToElastic $converted "_doc" "$controller-$($collectedEvent.RecordId)"
            } 
        }
    }
}

function Send-docToElastic($json,$_doc, $index) {
    $code = @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy{
        public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
Add-Type -TypeDefinition $code -Language CSharp
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$user = "<usr>"
$pass = "<passwd>"
$pair = "$($user):$($pass)"
$encodedCred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCred"
$headers = @{
    "Authorization" = $basicAuthValue
    "Content-type" = 'application/json'; 
    'charset'='utf-8'
}

$base_url = "<https://elasticURL:port>"
$cert = get-PfxCertificate -FilePath .\elk-config\http_ca.crt
Invoke-WebRequest -Uri $base_url/ekts/$_doc/$index  -UseBasicParsing -Headers $headers -Method PUT -Body $json
}

while ($true){
    New-Credentials
    Get-eventsFromDC
    Start-Sleep -Seconds 0
}

