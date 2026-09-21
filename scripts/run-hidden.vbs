' Lancador silencioso: executa um script .ps1 desta pasta SEM abrir janela de console.
' Usado pelas tarefas agendadas (MinecraftP2P-Sync / MinecraftP2P-Backup) para evitar o "flash" do CMD.
' Uso: wscript.exe run-hidden.vbs <script.ps1> [argumentos]
' Sem argumentos roda o sync-world.ps1 (compatibilidade com a antiga tarefa MinecraftP2P-AutoSave).
Dim shell, fso, here, script, args, i
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
script = "sync-world.ps1"
If WScript.Arguments.Count > 0 Then script = WScript.Arguments(0)
args = ""
For i = 1 To WScript.Arguments.Count - 1
    args = args & " " & WScript.Arguments(i)
Next
' O "0" esconde a janela; "True" espera terminar e repassa o codigo de saida para a tarefa agendada.
WScript.Quit shell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\" & script & """" & args, 0, True)
