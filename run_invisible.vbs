' Auto-elevating VBS to run clear_ram_loop.bat as Administrator

If Not WScript.Arguments.Named.Exists("elevated") Then
    ' Relaunch the script with admin privileges
    Set shell = CreateObject("Shell.Application")
    shell.ShellExecute "wscript.exe", Chr(34) & _
        WScript.ScriptFullName & Chr(34) & " /elevated", "", "runas", 1
    WScript.Quit
End If

' Now run the batch file from the same folder
Dim scriptPath
scriptPath = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

Set WshShell = CreateObject("WScript.Shell")
' Kill any existing instances first so we don't end up with 10 loops running at once!
WshShell.Run "taskkill /f /im cmd.exe /fi ""WINDOWTITLE eq Administrator:  Windows Optimizer Script""", 0, True
WshShell.Run "taskkill /f /im cmd.exe /fi ""WINDOWTITLE eq Windows Optimizer Script""", 0, True
' Start the new hidden loop
WshShell.Run Chr(34) & scriptPath & "\clear_ram_loop.bat" & Chr(34), 0
Set WshShell = Nothing
