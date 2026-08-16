Set-StrictMode -Version Latest


function ConvertTo-WeChatWxMemFsRenamePatchedSource {
	param(
		[Parameter(Mandatory = $true)]
		[string]$Source
	)

	$functionToken = 'rename:function(old_node,new_dir,new_name)'
	$nextFunctionToken = 'unlink:function'
	$mutationToken = (
		'delete old_node["parent"]["contents"][old_node["name"]];' +
		'new_dir["contents"][new_name]=old_node;' +
		'old_node["name"]=new_name;old_node["parent"]=new_dir;'
	)
	$patchMarker = '/*2048-wechat-wxmemfs-rename-v1*/'
	$oldPathPattern = (
		'var (?<variable>[A-Za-z_$][A-Za-z0-9_$]*)=' +
		'WXMEMFS\["getWxPath"\]\(' +
		'FS\["getPath"\]\(old_node\["parent"\]\)\+"/"\+' +
		'old_node\["name"\]\);'
	)

	if ([string]::IsNullOrEmpty($Source)) {
		throw 'WXMEMFS source must not be empty.'
	}
	if ($Source.Contains($patchMarker)) {
		throw 'WXMEMFS rename source is already patched.'
	}
	$functionCount = [regex]::Matches(
		$Source,
		[regex]::Escape($functionToken)
	).Count
	if ($functionCount -ne 1) {
		throw "Expected one WXMEMFS rename function, found $functionCount."
	}
	$mutationCount = [regex]::Matches(
		$Source,
		[regex]::Escape($mutationToken)
	).Count
	if ($mutationCount -ne 1) {
		throw "Expected one WXMEMFS rename mutation anchor, found $mutationCount."
	}
	$oldPathExpression = [regex]::new($oldPathPattern)
	$oldPathMatches = $oldPathExpression.Matches($Source)
	if ($oldPathMatches.Count -ne 1) {
		throw "Expected one late WXMEMFS old-path calculation, found $($oldPathMatches.Count)."
	}
	$functionStart = $Source.IndexOf($functionToken, [StringComparison]::Ordinal)
	$nextFunctionStart = $Source.IndexOf(
		$nextFunctionToken,
		$functionStart + $functionToken.Length,
		[StringComparison]::Ordinal
	)
	if ($functionStart -lt 0 -or $nextFunctionStart -lt 0) {
		throw 'WXMEMFS rename function boundary could not be resolved.'
	}
	$originalFunction = $Source.Substring(
		$functionStart,
		$nextFunctionStart - $functionStart
	)
	if (-not $originalFunction.EndsWith(',', [StringComparison]::Ordinal)) {
		throw 'WXMEMFS rename function does not end at the expected comma boundary.'
	}

	$patchedFunction = @(
		'rename:function(old_node,new_dir,new_name){'
		'var existing;'
		'try{existing=FS["lookupNode"](new_dir,new_name)}catch(e){}'
		'if(existing&&FS["isDir"](old_node["mode"])){'
		'for(var entry in existing["contents"]){throw new FS["ErrnoError"](55)}}'
		'var oldWxPath="";var newWxPath="";'
		'if(WXMEMFS["wxBasePath"]){'
		'oldWxPath=WXMEMFS["getWxPath"]('
		'FS["getPath"](old_node["parent"])+"/"+old_node["name"]);'
		'newWxPath=WXMEMFS["getWxPath"](FS["getPath"](new_dir)+"/"+new_name);'
		'try{wx["getFileSystemManager"]()["renameSync"](oldWxPath,newWxPath);'
		'WXMEMFS["log"]("[WXMEMFS] rename:",oldWxPath,"->",newWxPath)}'
		'catch(e){WXMEMFS["logError"]("[WXMEMFS] rename failed:",e["message"]);'
		'throw new FS["ErrnoError"](29)}}'
		'if(existing){FS["hashRemoveNode"](existing)}'
		'delete old_node["parent"]["contents"][old_node["name"]];'
		'new_dir["contents"][new_name]=old_node;'
		'old_node["name"]=new_name;old_node["parent"]=new_dir;'
		'new_dir["ctime"]=new_dir["mtime"]=old_node["parent"]["ctime"]='
		'old_node["parent"]["mtime"]='
		'Date["now"]();'
		$patchMarker
		'},'
	) -join ''
	$patchedSource = (
		$Source.Substring(0, $functionStart) +
		$patchedFunction +
		$Source.Substring($nextFunctionStart)
	)
	if (-not $patchedSource.Contains($patchedFunction) -or $oldPathExpression.IsMatch($patchedSource)) {
		throw 'WXMEMFS rename patch did not reach its exact postcondition.'
	}
	return $patchedSource
}
