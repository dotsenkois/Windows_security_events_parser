# общие настройки
$config = Get-Content -Path ./config.json -Raw | Convertfrom-Json
# получение событий из файла

function main {
    $All_evtx_files = Get-ChildItem -Path $config.input.evtx_folder -Filter "*.evt*"
    foreach ($evtx_file in $All_evtx_files){
        if ($config.input.events_id){
            $AllEvents = Get-WinEvent -Path $evtx_file.fullname -MaxEvents 10| Where-Object {$config.input.events_id -contains $_.id}
        } else {
            $AllEvents = Get-WinEvent -Path $evtx_file.fullname -MaxEvents 100
        }
        foreach ($event in $AllEvents){
            # $ScriptBlock = {
                $local:index = $($evtx_file.Name.Split(".")[0].replace("_","-"))-$($event.RecordId)
                Send-DocToElastic $(ConvertTo-Hashtable $event) "_doc" $local:index
            # }
            # Start-Job -ScriptBlock $ScriptBlock
        }
    }
}

# преобразование событий
function ConvertTo-Hashtable ($local:event) {
    $local:event_HT = $local:event | Select-Object -Property * -ExcludeProperty "Properties", "Message" ,"TimeCreated"
    $local:timezone = $config.filter.timezone
    $local:TimeCreated = $local:event.TimeCreated.toString("yyyy-MM-dd'T'HH:mm:ss.fff")
    if ($local:event.Message){
        $local:msg = Convert-Message $($local:event.Message -split [System.Environment]::NewLine | Where-Object {$_ -ne "" -and $_ -like "*:*"})
        $local:event_HT | Add-Member -MemberType NoteProperty -Name "Message" -Value $local:msg
    }
    $local:event_HT | Add-Member -MemberType NoteProperty -Name "TimeCreated" -Value "$local:TimeCreated$local:timezone"
    return $local:event_HT | ConvertTo-Json
}

function Convert-Message ($local:msg) {
    $local:convertedMessage = @{}
    $local:key_up = ""
    $local:tmpHT =@{}
    foreach ($local:string in $local:msg){
        $local:spltd_str = $local:string -split ":"
        if ($local:spltd_str[1] -eq "" -and $local:spltd_str[0][0] -match "\w"){
            if ($local:key_up -ne ""){
                $local:convertedMessage.Add($local:key_up,$local:tmpHT)
                $local:key_up = ""
                $local:tmpHT =@{}
            }
            $local:key_up = $local:spltd_str[0]
        } else {
            $local:tmpHT += ConvertFrom-StringData $($local:string.replace(":","=").replace("\","\\")) -Debug
        }
    }
    return $local:convertedMessage
}

# отправка в эластик
function Send-DocToElastic($local:json,$local:_doc, $local:index) {
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

$pair = "$($config.output.elasticsearh.user):$($config.output.elasticsearh.password)"
$encodedCred = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCred"
$local:headers = @{
    "Authorization" = $basicAuthValue
    "Content-type" = 'application/json'; 
    'charset'='utf-8'
}

$local:base_url = "$($config.output.elasticsearh.proto)://$($config.output.elasticsearh.host)"
# $cert = get-PfxCertificate -FilePath .\elk-config\http_ca.crt
# $local:json >> output.json
Invoke-WebRequest -Uri $local:base_url/ekts/$local:_doc/$local:index  -UseBasicParsing -Headers $local:headers -Method PUT -Body $local:json
}

main