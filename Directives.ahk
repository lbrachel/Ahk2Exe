#Include <VersionRes>

ProcessDirectives(ExeFile, module, cmds)
{
	state := { ExeFile: ExeFile, module: module, resLang: 0x409, verInfo: {} }
	for _,cmdline in cmds
	{
		Util_Status("Processing directive: " cmdline)
		if !RegExMatch(cmdline, "^(\w+)(?:\s+(.+))?$", o)
			Util_Error("Error: Invalid directive:`n`n" cmdline)
		args := [], nargs := 0
		StringReplace, o2, o2, ```,, `n, All
		Loop, Parse, o2, `,, %A_Space%%A_Tab%
		{
			StringReplace, ov, A_LoopField, `n, `,, All
			StringReplace, ov, ov, ``n, `n, All
			StringReplace, ov, ov, ``r, `r, All
			StringReplace, ov, ov, ``t, `t, All
			StringReplace, ov, ov, ````, ``, All
			args.Insert(ov), nargs++
		}
		fn := Func("Directive_" o1)
		if !fn
			Util_Error("Error: Invalid directive: " o1)
		if (fn.MinParams-1) > nargs || nargs > (fn.MaxParams-1)
			Util_Error("Error: Wrongly formatted directive:`n`n" cmdline)
		fn.(state, args*)
	}
	
	if !Util_ObjIsEmpty(state.verInfo)
	{
		Util_Status("Changing version information...")
		ChangeVersionInfo(ExeFile, module, state.verInfo)
	}
}

Directive_SetName(state, txt)
{
	state.verInfo.Name := txt
}

Directive_SetDescription(state, txt)
{
	state.verInfo.Description := txt
}

Directive_SetVersion(state, txt)
{
	state.verInfo.Version := txt
}

Directive_SetCopyright(state, txt)
{
	state.verInfo.Copyright := txt
}

Directive_SetOrigFilename(state, txt)
{
	state.verInfo.OrigFilename := txt
}

Directive_UseResourceLang(state, resLang)
{
	if resLang is not integer
		Util_Error("Error: Resource language must be an integer between 0 and 0xFFFF.")
	if resLang not between 0 and 0xFFFF
		Util_Error("Error: Resource language must be an integer between 0 and 0xFFFF.")
	state.resLang := resLang+0
}

Directive_AddResource(state, rsrc, resName := "")
{
	resType := "" ; auto-detect
	if RegExMatch(resFile, "^\*(\w+)\s+(.+)$", o)
		resType := o1, rsrc := o2
	resFile := Util_GetFullPath(rsrc)
	if !resFile
		Util_Error("Error: specified resource does not exist: " rsrc)
	SplitPath, resFile, resFileName,, resExt
	if !resName
		resName := resFileName
	StringUpper, resName, resName
	if resType =
	{
		; Auto-detect resource type
		if resExt in bmp,dib
			resType := 2 ; RT_BITMAP
		else if resExt = ico
			Util_Error("Error: Icon resource adding is not supported yet!")
		else if resExt = cur
			resType := 1 ; RT_CURSOR
		else if resExt in htm,html,mht
			resType := 23 ; RT_HTML
		else
			resType := 10 ; RT_RCDATA
	}
	typeType := "str"
	nameType := "str"
	if resType is integer
		if resType between 0 and 0xFFFF
			typeType := "uint"
	if resName is integer
		if resName between 0 and 0xFFFF
			nameType := "uint"
	
	FileGetSize, fSize, %resFile%
	VarSetCapacity(fData, fSize)
	FileRead, fData, *c %resFile%
	if !DllCall("UpdateResource", "ptr", state.module, typeType, resType, nameType, resName
              , "ushort", state.resLang, "ptr", &fData, "uint", fSize, "uint")
		Util_Error("Error adding resource:`n`n" rsrc)
	VarSetCapacity(fData, 0)
}

ChangeVersionInfo(ExeFile, hUpdate, verInfo)
{
	hModule := DllCall("LoadLibraryEx", "str", ExeFile, "ptr", 0, "ptr", 2, "ptr")
	if !hModule
		Util_Error("Error: Error opening destination file.")
	
	hRsrc := DllCall("FindResource", "ptr", hModule, "ptr", 1, "ptr", 16, "ptr") ; Version Info\1
	hMem := DllCall("LoadResource", "ptr", hModule, "ptr", hRsrc, "ptr")
	vi := new VersionRes(DllCall("LockResource", "ptr", hMem, "ptr"))
	DllCall("FreeLibrary", "ptr", hModule)
	
	ffi := vi.GetDataAddr()
	props := SafeGetViChild(SafeGetViChild(vi, "StringFileInfo"), "040904b0")
	for k,v in verInfo
	{
		if IsLabel(lbl := "_VerInfo_" k)
			gosub %lbl%
		continue
		_VerInfo_Name:
		SafeGetViChild(props, "ProductName").SetText(v)
		SafeGetViChild(props, "InternalName").SetText(v)
		return
		_VerInfo_Description:
		SafeGetViChild(props, "FileDescription").SetText(v)
		return
		_VerInfo_Version:
		SafeGetViChild(props, "FileVersion").SetText(v)
		SafeGetViChild(props, "ProductVersion").SetText(v)
		ver := VersionTextToNumber(v)
		hiPart := (ver >> 32)&0xFFFFFFFF, loPart := ver & 0xFFFFFFFF
		NumPut(hiPart, ffi+8, "UInt"), NumPut(loPart, ffi+12, "UInt")
		NumPut(hiPart, ffi+16, "UInt"), NumPut(loPart, ffi+20, "UInt")
		return
		_VerInfo_Copyright:
		SafeGetViChild(props, "LegalCopyright").SetText(v)
		return
		_VerInfo_OrigFilename:
		SafeGetViChild(props, "OriginalFilename").SetText(v)
		return
	}
	
	VarSetCapacity(newVI, 16384) ; Should be enough
	viSize := vi.Save(&newVI)
	if !DllCall("UpdateResource", "ptr", hUpdate, "ptr", 16, "ptr", 1
	          , "ushort", 0x409, "ptr", &newVI, "uint", viSize, "uint")
		Util_Error("Error changing the version information.")
}

VersionTextToNumber(v)
{
	r := 0, i := 0
	while i < 4 && RegExMatch(v, "O)^(\d+).?", o)
	{
		StringTrimLeft, v, v, % o.Len
		val := o[1] + 0
		r |= (val&0xFFFF) << ((3-i)*16)
		i ++
	}
	return r
}

SafeGetViChild(vi, name)
{
	c := vi.GetChild(name)
	if !c
		Util_Error("Error: Malformed version information data. Block missing:`n`n" vi.Name "\" name)
	return c
}

Util_ObjIsEmpty(obj)
{
	v := true
	for _,__ in obj
	{
		v := false
		break
	}
	return v
}
