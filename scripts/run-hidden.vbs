' Lancador silencioso: executa um .ps1 desta pasta SEM abrir janela de console.
' Usado pelas tarefas agendadas para evitar o "flash" do CMD.
' Uso: wscript.exe run-hidden.vbs [script.ps1] [argumentos]
' Sem argumentos roda o autosave.ps1 (compatibilidade com a tarefa MinecraftP2P-AutoSave).
Dim shell, fso, here, script, args, i
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
script = "autosave.ps1"
If WScript.Arguments.Count > 0 Then script = WScript.Arguments(0)
args = ""
For i = 1 To WScript.Arguments.Count - 1
    args = args & " " & WScript.Arguments(i)
Next
' O "0" esconde a janela; "True" espera terminar e repassa o codigo de saida para a tarefa
' (assim o "nao rodar duas ao mesmo tempo" do Agendador funciona de verdade).
WScript.Quit shell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\" & script & """" & args, 0, True)
