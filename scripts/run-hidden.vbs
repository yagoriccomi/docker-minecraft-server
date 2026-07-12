' Lancador silencioso: executa o autosave.ps1 (mesma pasta) SEM abrir janela de console.
' Usado pela tarefa agendada MinecraftP2P-AutoSave para evitar o "flash" do CMD a cada 30 min.
Dim shell, fso, here
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
' O "0" esconde a janela; "False" nao espera terminar.
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\autosave.ps1""", 0, False
