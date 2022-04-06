param(
	[Parameter(Mandatory=$true)]$xmlPath,
    [Parameter(Mandatory=$true)]$destinationFile,
    [Parameter()]$ignoreTypes=@(),
    [Parameter()]$assemblyPath=$null
);

Function GetDelegateParameters{
    Param($typeName)
    try{
        $ass = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom("$pwd$assemblyPath")
        $type = $ass.GetType($typeName);
        $method = $type.GetMethod("Invoke");
        if ($method -ne $null){
            $pars = @();
            $method.GetParameters() | ForEach {
                $pars+=[pscustomobject]@{
                    "Name"=$_.Name;
                    "Type"=$_.ParameterType.FullName;
                }
            }
            return $pars;
        }
        return $null;
    }catch{
        return $null;
    }
}

Function AppendCode{
    Param($code)
    if ($code -ne $null){
        [string]::Format("```````r`n{0}`r`n```````r`n",@($code.Trim())) | Out-File -FilePath $destinationFile -Append;    
    }
}

Function AppendRemarks{
    Param($remarks)
    if ($remarks -ne $null){
        [string]::Format("##### Remarks`r`n`r`n{0}`r`n",@($remarks)) | Out-File -FilePath $destinationFile -Append;    
    }
}

Function AppendSummary{
    Param($summary)
    if ($summary -ne $null){
        [string]::Format("##### Summary`r`n`r`n{0}`r`n",@($summary)) | Out-File -FilePath $destinationFile -Append;    
    }
}

Function AppendExample{
    Param($example)
    if ($example -ne $null){
        "##### Example`r`n" | Out-File -FilePath $destinationFile -Append;
        $example.ChildNodes | ForEach{
            $node = $_;
            switch ($node.Name){
                "#cdata-section" { $node.Value.Trim() | Out-File -FilePath $destinationFile -Append; }
                "code" { AppendCode -code $node."#text"; }
            }
        }
    }
}

Function AppendParameters{
	Param ($object,$typeNames,$baseLink)
    if ($object.Parameters.length -gt 0){
        $hasCode=$false;
        "##### Parameters`r`n`r`n| Name | Type | Description |`r`n| ---- | ---- | ----------- |" | Out-File -FilePath $destinationFile -Append;    
        $object.Parameters | ForEach {
            $name = $_.Name;
            if ($_.Code -ne $null){
                $hasCode=$true;
                $name = [string]::Format("[{0}](#{1}-{0} '{0}')",@($_.Name,$baseLink));
            }
            if ($_.Type -ne $null){
                $link = $("http://msdn.microsoft.com/query/dev14.query?appId=Dev14IDEF1&l=EN-US&k=k:"+$_.Type);
                if ($typeNames.Contains($_.Type)){
                    $link=$("#"+$_.Type.Replace('.','-').Replace("[]","")+"-");
                }
                [string]::Format("| {0} | [T:{2}]({1} 'T:{2}') | {3} |",@($name,$link,$_.Type,$_.Description)) | Out-File -FilePath $destinationFile -Append;    
            }else{
                [string]::Format("| {0} | ---- | {1} |",@($name,$_.Description)) | Out-File -FilePath $destinationFile -Append;
            }
        }
        "`r`n" | Out-File -FilePath $destinationFile -Append;
        if ($hasCode){
            "###### Parameter Code`r`n`r`n" | Out-File -FilePath $destinationFile -Append;    
             $object.Parameters | ForEach {
                if ($_.Code -ne $null){
                    [string]::Format("<a name=""{1}-{0}""></a>",@($_.Name,$baseLink)) | Out-File -FilePath $destinationFile -Append;
                    [string]::Format("###### {0}",@($_.Name)) | Out-File -FilePath $destinationFile -Append;    
                    AppendCode -code $_.Code;
                }
            }
        }
    }
}

$objects = @();
$typeNames = @();

Select-Xml -Path $xmlPath -XPath "/doc/members/member[starts-with(@name,'T:')]" | ForEach {
    $elem = $_;
    $tmp = $($elem.Node.name -split ":");
    if (!$ignoreTypes.Contains($tmp[1])){
        $typeNames+=$tmp[1];
        $typeNames+=$($tmp[1]+"[]");
        $type = @{
            "FullName"=$tmp[1];
            "Name"=$tmp[1].SubString($tmp[1].LastIndexOf(".")+1);
            "Namespace"=$tmp[1].SubString(0,$tmp[1].LastIndexOf("."));
            "Properties"=@();
            "Methods"=@();
            "Constructors"=@();
            "Summary"=$null;
            "Remarks"=$null;
            "Link"=$tmp[1].Replace('.','-')+"-";
            "Parameters"=@();
            "Example"=$null;
            "Constants"=@();
        };
        $summary = $elem.Node.SelectNodes("./summary/text()");
        if ($summary -ne $null){
            $type["Summary"]=$summary.Value.Trim();
        }
        $remarks = $elem.Node.SelectNodes("./remarks/text()");
        if ($remarks -ne $null){
            $type["Remarks"]=$remarks.Value.Trim();
        }
        if ([bool]($elem.Node.PSobject.Properties.name -match "example")){
            $type["Example"]=$elem.Node.example;
        }
        if ([bool]($elem.Node.PSobject.Properties.name -match "param")){
            $pars = GetDelegateParameters -typeName $type["FullName"];
            $elem.Node.param | ForEach {
                $par = @{
                    "Name"=$_.name;
                    "Type"=$null;
                    "Description"=$null;
                    "Code"=$null;
                };
                if ([bool]($_.PSobject.Properties.name -match "#text")){
                    $par["Description"]=$_.'#text'.Trim();
                }
                if ([bool]($_.PSobject.Properties.name -match "code")){
                    $par["Example"]=$elem.Node.example;
                }
                if ($pars -ne $null){
                    $pars | ForEach {
                        if ($_.Name -eq $par["Name"]){
                            $par["Type"]=$_.Type;
                        }
                    }
                }
                $type["Parameters"]+=[pscustomobject]$par;
            }
        }
        $lidx=0;
        Select-Xml -Path $xmlPath -XPath $("/doc/members/member[starts-with(@name,'P:"+$type["FullName"]+"')]") | ForEach {
            $elem = $_;
            $prop = @{
                "Name"=$elem.Node.name.Substring($("P:"+$type["FullName"]).Length+1);
                "Summary"=$null;
                "Remarks"=$null;
                "Parameters"=$null;
                "Link"=$($type["Link"]+$lidx.toString());
            };
            $lidx++;
            $summary = $elem.Node.SelectNodes("./summary/text()");
            if ($summary -ne $null){
                $prop["Summary"]=$summary.Value.Trim();
            }
            $remarks = $elem.Node.SelectNodes("./remarks/text()");
            if ($remarks -ne $null){
                $prop["Remarks"]=$remarks.Value.Trim();
            }
            if ($elem.Node.name.IndexOf("(") -ne -1){
                $prop["Name"]=$prop["Name"].SubString(0,$prop["Name"].IndexOf('('));
                $pars = $elem.Node.name.Substring($("P:"+$type["FullName"]+$prop["Name"]).Length).TrimStart('(').TrimEnd(')').Split(',');
                $idx=0;
                $prop["Parameters"]=@();
                if ($pars.Length -eq 1){
                    $prop["Parameters"]+=[pscustomobject]@{
                        "Name"=$elem.Node.param.name;
                        "Type"=$pars[0];
                        "Description"=$elem.Node.param.InnerText;
                    };
                }else{
                    while ($idx -lt $pars.Length){
                        $prop["Parameters"]+=[pscustomobject]@{
                            "Name"=$elem.Node.param[$idx].name;
                            "Type"=$pars[$idx];
                            "Description"=$elem.Node.param[$idx].InnerText;
                        };
                        $idx++;
                    }
                }
            }
            $type["Properties"]+=[pscustomobject]$prop;
        }
        Select-Xml -Path $xmlPath -XPath $("/doc/members/member[starts-with(@name,'F:"+$type["FullName"]+"')]") | ForEach {
            $elem = $_;
            $const = @{
                "Name"=$elem.Node.name.Substring($("F:"+$type["FullName"]).Length+1);
                "Summary"=$null;
                "Link"=$($type["Link"]+$lidx.toString());
            };
            $lidx++;
            $summary = $elem.Node.SelectNodes("./summary/text()");
            if ($summary -ne $null){
                $const["Summary"]=$summary.Value.Trim();
            }
            $type["Constants"]+=[pscustomobject]$const;
        }
        Select-Xml -Path $xmlPath -XPath $("/doc/members/member[starts-with(@name,'M:"+$type["FullName"]+".#ctor')]") | ForEach {
            $elem = $_;
            $constructor = @{
                "Name"="#ctor()";
                "Parameters"=@();
                "Summary"=$null;
                "Remarks"=$null;
                "Link"=$($type["Link"]+$lidx.toString());
            };
            $lidx++;
            $summary = $elem.Node.SelectNodes("./summary/text()");
            if ($summary -ne $null){
                $constructor["Summary"]=$summary.Value.Trim();
            }
            $remarks = $elem.Node.SelectNodes("./remarks/text()");
            if ($remarks -ne $null){
                $constructor["Remarks"]=$remarks.Value.Trim();
            }
            if ($elem.Node.name.IndexOf("(") -ne -1){
                $pars = $elem.Node.name.Substring($("M:"+$type["FullName"]+".#ctor").Length).TrimStart('(').TrimEnd(')').Split(',');
                $constructor["Name"]="#ctor(";
                $idx=0;
                if ($pars.Length -eq 1){
                    $par = @{
                        "Name"=$elem.Node.param.name;
                        "Type"=$pars[0];
                        "Description"=$null;
                        "Code"=$null;
                    };
                    if ([bool]($elem.Node.param.PSobject.Properties.name -match "#text")){
                        $par["Description"]=$elem.Node.param.'#text'.Trim();
                    }
                    if ([bool]($elem.Node.param.PSobject.Properties.name -match "code")){
                        if ([bool]($elem.Node.param.code.PSobject.Properties.name -match "InnerText")){
                            $par["Code"] = $elem.Node.param.code.InnerText.Trim();
                        }else{
                            $par["Code"] = $elem.Node.param.code.Trim();
                        }
                    }
                    $constructor["Parameters"]+=[pscustomobject]$par;
                    $constructor["Name"]+=$par.Name+")";
                }else{
                    while ($idx -lt $pars.Length){
                        $par = @{
                            "Name"=$elem.Node.param[$idx].name;
                            "Type"=$pars[$idx];
                            "Description"=$null;
                            "Code"=$null;
                        };
                        if ([bool]($elem.Node.param[$idx].PSobject.Properties.name -match "#text")){
                            $par["Description"]=$elem.Node.param[$idx].'#text'.Trim();
                        }
                        if ([bool]($elem.Node.param[$idx].PSobject.Properties.name -match "code")){
                            if ([bool]($elem.Node.param[$idx].code.PSobject.Properties.name -match "InnerText")){
                                $par["Code"] = $elem.Node.param[$idx].code.InnerText.Trim();
                            }else{
                                $par["Code"] = $elem.Node.param[$idx].code.Trim();
                            }
                        }
                        $constructor["Parameters"]+=[pscustomobject]$par;
                        $constructor["Name"]+=$par.Name+",";
                        $idx++;
                    }
                    $constructor["Name"]=$constructor["Name"].SubString(0,$constructor["Name"].Length-1)+")";
                }
            }
            $type["Constructors"]+=[pscustomobject]$constructor;
        }
        Select-Xml -Path $xmlPath -XPath $("/doc/members/member[starts-with(@name,'M:"+$type["FullName"]+"')][not(starts-with(@name,'M:"+$type["FullName"]+".#ctor'))]") | ForEach {
            $elem = $_;
            $method = @{
                "Name"=$elem.Node.name.Substring($("M:"+$type["FullName"]).Length+1);
                "Parameters"=@();
                "Summary"=$null;
                "Remarks"=$null;
                "Returns"=$null;
                "Link"=$($type["Link"]+$lidx.toString());
            };
            $lidx++;
            $summary = $elem.Node.SelectNodes("./summary/text()");
            if ($summary -ne $null){
                $method["Summary"]=$summary.Value.Trim();
            }
            $remarks = $elem.Node.SelectNodes("./remarks/text()");
            if ($remarks -ne $null){
                $method["Remarks"]=$remarks.Value.Trim();
            }
            $returns = $elem.Node.SelectNodes("./returns/text()");
            if ($returns -ne $null){
                $method["Returns"]=$returns.Value.Trim();
            }
            if ($elem.Node.name.IndexOf("(") -ne -1){
                $pars = $elem.Node.name.Substring($elem.Node.name.IndexOf("(")).TrimStart('(').TrimEnd(')').Split(',');
                $method["Name"] = $method["Name"].SubString(0,$method["Name"].IndexOf("(")+1);
                $idx=0;
                if ($pars.Length -eq 1){
                    $par = @{
                        "Name"=$elem.Node.param.name;
                        "Type"=$pars[0];
                        "Description"=$null;
                        "Code"=$null;
                    };
                    if ([bool]($elem.Node.param.PSobject.Properties.name -match "#text")){
                        $par["Description"]=$elem.Node.param.'#text'.Trim();
                    }
                    if ([bool]($elem.Node.param.PSobject.Properties.name -match "code")){
                        if ([bool]($elem.Node.param.code.PSobject.Properties.name -match "InnerText")){
                            $par["Code"] = $elem.Node.param.code.InnerText.Trim();
                        }else{
                            $par["Code"] = $elem.Node.param.code.Trim();
                        }
                    }
                    $method["Parameters"]+=[pscustomobject]$par;
                    $method["Name"]+=$par.Name+")";
                    $idx++;
                }else{
                    while ($idx -lt $pars.Length){
                        $par = @{
                            "Name"=$elem.Node.param[$idx].name;
                            "Type"=$pars[$idx];
                            "Description"=$null;
                            "Code"=$null;
                        };
                        if ([bool]($elem.Node.param[$idx].PSobject.Properties.name -match "#text")){
                            $par["Description"]=$elem.Node.param[$idx].'#text'.Trim();
                        }
                        if ([bool]($elem.Node.param[$idx].PSobject.Properties.name -match "code")){
                            if ([bool]($elem.Node.param[$idx].code.PSobject.Properties.name -match "InnerText")){
                                $par["Code"] = $elem.Node.param[$idx].code.InnerText.Trim();
                            }else{
                                $par["Code"] = $elem.Node.param[$idx].code.Trim();
                            }
                        }
                        $method["Parameters"]+=[pscustomobject]$par;
                        $method["Name"]+=$par.Name+",";
                        $idx++;
                    }
                    $method["Name"]=$method["Name"].SubString(0,$method["Name"].Length-1)+")";
                }
            }
            $type["Methods"]+=[pscustomobject]$method;
        }
        $objects+=[pscustomobject]$type;
    }
}

"## Contents" | Out-File -FilePath $destinationFile;

$objects | ForEach {
    $type = $_;
    [string]::Format("- [{0}](#{1} '{2}')",@($type.Name,$type.Link,$type.FullName)) | Out-File -FilePath $destinationFile -Append;
    $type.Constructors | ForEach {
        [string]::Format("  - [{0}](#{1} '{2}.{0}')",@($_.Name,$_.Link,$type.FullName)) | Out-File -FilePath $destinationFile -Append;
    }
    $type.Properties | ForEach {
        [string]::Format("  - [{0}](#{1} '{2}.{0}')",@($_.Name,$_.Link,$type.FullName)) | Out-File -FilePath $destinationFile -Append;
    }
    $type.Constants | ForEach {
        [string]::Format("  - [{0}](#{1} '{2}.{0}')",@($_.Name,$_.Link,$type.FullName)) | Out-File -FilePath $destinationFile -Append;
    }
    $type.Methods | ForEach {
        [string]::Format("  - [{0}](#{1} '{2}.{0}')",@($_.Name,$_.Link,$type.FullName)) | Out-File -FilePath $destinationFile -Append;
    }
}

"" | Out-File -FilePath $destinationFile -Append;

$objects | ForEach {
    $type = $_;
    [string]::Format("<a name=""{0}""></a>",@($type.Link)) | Out-File -FilePath $destinationFile -Append;
    [string]::Format("## {0} ``type```r`n",@($type.Name)) | Out-File -FilePath $destinationFile -Append;
    [string]::Format("##### Namespace`r`n`r`n{0}`r`n",@($type.Namespace)) | Out-File -FilePath $destinationFile -Append;
    AppendSummary -summary $type.Summary;
    AppendRemarks -remarks $type.Remarks;
    AppendParameters -object $type -typeNames $typeNames -baseLink $type.Link;
    AppendExample -example $type.Example;
    $type.Constructors | ForEach {
        $constructor = $_;
        [string]::Format("<a name=""{0}""></a>`r`n### {1} ``constructor```r`n",@($constructor.Link,$constructor.Name))| Out-File -FilePath $destinationFile -Append;  
        AppendSummary -summary $constructor.Summary;
        AppendRemarks -remarks $constructor.Remarks;
        AppendParameters -object $constructor -typeNames $typeNames -baseLink $constructor.Link;
    }
    $type.Properties | ForEach {
        $property = $_;
        [string]::Format("<a name=""{0}""></a>`r`n### {1} ``property```r`n",@($property.Link,$property.Name))| Out-File -FilePath $destinationFile -Append;  
        AppendSummary -summary $property.Summary;
        AppendRemarks -remarks $property.Remarks;
        AppendParameters -object $property -typeNames $typeNames -baseLink $property.Link;
    }
    $type.Constants | ForEach {
        $const = $_;
        [string]::Format("<a name=""{0}""></a>`r`n### {1} ``constants```r`n",@($const.Link,$const.Name))| Out-File -FilePath $destinationFile -Append;  
        AppendSummary -summary $const.Summary;
    }
    $type.Methods | ForEach {
        $method = $_;
        [string]::Format("<a name=""{0}""></a>`r`n### {1} ``method```r`n",@($method.Link,$method.Name))| Out-File -FilePath $destinationFile -Append;  
        AppendSummary -summary $method.Summary;
        AppendRemarks -remarks $method.Remarks;
        AppendParameters -object $method -typeNames $typeNames -baseLink $method.Link;
    }
}