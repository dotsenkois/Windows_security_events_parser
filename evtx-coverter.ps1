function parse-evemtmsg($pattern){
    $ht = @{}
    $gethered_string = (Select-String -Path .\tmp\message.txt -Pattern $pattern -Context 0,10).Context.PostContext

    foreach ($item in $gethered_string) {
        if ( $item -ne ""){
            if ($item[0] -notmatch '\w'){
                $splitted_string = $item -Split ':'
                $key = $splitted_string[0].Substring(1)
                $value = $splitted_string[1].Substring(1).replace("{","").replace("}","").replace("\t","")
                if ($value[0] -match '\t'){
                    if ($value[1] -match '\t'){
                        $ht.add($key,$value.Substring(2))
                    } else {
                        $ht.add($key,$value.Substring(1))
                    } 
                } else {
                    $ht.add($key,$value)
                }
                
            } 
        } else { 
            return $ht
            break
         } 

    }
}



$event_HT = @{}
$message_content = Get-Content -Path .\tmp\message.txt 
foreach ($message in $message_content ){
    if ( $message -ne ""){
        # Исключаем полнотекстовое описание события
        if ($message.Split(' ').length -lt 4) {
            # Поиск ключей первого уровня
            if ($message[0] -match '\w'){
                $s = $message.Split(':')
                if ($s[1]){
                    #Разбор плоских записей
                    $flat_key = $s[0]
                    $flat_value = $s[1].Substring(1)
                    if ($flat_value -ne ""){
                        if ($flat_value[0] -match "\w"){
                            $event_HT.add($flat_key, $flat_value)
                        } else {
                            if($flat_value[1] -match "\w"){
                                $event_HT.add($flat_key, $flat_value.Substring(1))
                            }
                        }
                    }
                } else {
                    # Пытаемся прочитать вложенные значения
                    $parsed = parse-evemtmsg $message 
                    $event_HT.add($s[0],$parsed )
                }
            }
        }
    }
    
}

$event_HT  | ConvertTo-Json  > .\tmp\1.json